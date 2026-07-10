import AppKit
import Carbon
import Combine
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general
    case calendars
    case menuBar

    var title: String {
        switch self {
        case .general:
            return "General"
        case .calendars:
            return "Calendars"
        case .menuBar:
            return "Menu Bar"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .calendars:
            return "calendar"
        case .menuBar:
            return "menubar.rectangle"
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedPane: SettingsPane

    @Published var selectedMode: MenuBarDisplayMode {
        didSet {
            settingsStore.updateDisplayMode(selectedMode)
            onChange()
        }
    }

    @Published var lookAheadDays: Int {
        didSet {
            settingsStore.updateLookAheadDays(lookAheadDays)
            onChange()
        }
    }

    @Published var showEventColors: Bool {
        didSet {
            settingsStore.updateShowEventColors(showEventColors)
            onChange()
        }
    }

    @Published var showAllDayEvents: Bool {
        didSet {
            settingsStore.updateShowAllDayEvents(showAllDayEvents)
            onChange()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLoginItemState else {
                return
            }

            applyLaunchAtLoginChange()
        }
    }

    #if DEBUG
    @Published var debugDateIconOverrideEnabled: Bool {
        didSet {
            dateIconDebugSettings?.isOverrideEnabled = debugDateIconOverrideEnabled
        }
    }

    @Published var debugDateIconDay: Int {
        didSet {
            guard !isApplyingDebugDateClamp else {
                return
            }

            let clampedDay = min(max(debugDateIconDay, 1), 31)
            if debugDateIconDay != clampedDay {
                dateIconDebugSettings?.day = clampedDay
                isApplyingDebugDateClamp = true
                debugDateIconDay = clampedDay
                isApplyingDebugDateClamp = false
                return
            }

            dateIconDebugSettings?.day = debugDateIconDay
        }
    }

    @Published var debugDateIconFontWeight: DateIconDebugFontWeight {
        didSet {
            dateIconDebugSettings?.fontWeight = debugDateIconFontWeight
        }
    }
    #endif

    @Published private(set) var accessState: CalendarAccessState
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var globalShortcut: GlobalShortcut
    @Published private(set) var shortcutError: String?
    @Published private(set) var loginItemError: String?
    @Published private(set) var availableCalendars: [CalendarInfo] = []
    @Published private(set) var selectedCalendarIdentifiers: Set<String>?
    @Published private(set) var calendarLoadingError: String?
    @Published private(set) var isLoadingCalendars = false

    private let settingsStore: SettingsStore
    private let permissionController: CalendarPermissionController
    private let calendarProvider: CalendarEventProviding?
    private let loginItemManager: LoginItemManaging
    private var isApplyingLoginItemState = false
    #if DEBUG
    private let dateIconDebugSettings: DateIconDebugSettings?
    private var isApplyingDebugDateClamp = false
    #endif
    private let onChange: () -> Void
    private let onShortcutChangeRequested: (GlobalShortcut) -> HotKeyRegistrationResult
    private let onAccessRequestCompleted: () -> Void
    private var accessStateCancellable: AnyCancellable?
    private var calendarLoadTask: Task<Void, Never>?

    #if DEBUG
    init(
        settingsStore: SettingsStore,
        permissionController: CalendarPermissionController,
        calendarProvider: CalendarEventProviding? = nil,
        loginItemManager: LoginItemManaging = LoginItemManager(),
        dateIconDebugSettings: DateIconDebugSettings? = nil,
        selectedPane: SettingsPane = .general,
        onShortcutChangeRequested: @escaping (GlobalShortcut) -> HotKeyRegistrationResult = { _ in .success },
        onAccessRequestCompleted: @escaping () -> Void = {},
        onChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
        self.dateIconDebugSettings = dateIconDebugSettings
        self.selectedPane = selectedPane
        self.debugDateIconOverrideEnabled = dateIconDebugSettings?.isOverrideEnabled ?? false
        self.debugDateIconDay = dateIconDebugSettings?.day ?? Calendar.current.component(.day, from: Date())
        self.debugDateIconFontWeight = dateIconDebugSettings?.fontWeight ?? .semibold
        let settings = settingsStore.settings
        self.selectedMode = settings.displayMode
        self.lookAheadDays = settings.lookAheadDays
        self.showEventColors = settings.showEventColors
        self.showAllDayEvents = settings.showAllDayEvents
        self.selectedCalendarIdentifiers = settings.selectedCalendarIdentifiers
        self.launchAtLogin = loginItemManager.isEnabled
        self.globalShortcut = settings.globalShortcut
        self.accessState = permissionController.accessState
        self.onShortcutChangeRequested = onShortcutChangeRequested
        self.onAccessRequestCompleted = onAccessRequestCompleted
        self.onChange = onChange

        subscribeToAccessStateChanges()
        refreshAvailableCalendars()
    }
    #else
    init(
        settingsStore: SettingsStore,
        permissionController: CalendarPermissionController,
        calendarProvider: CalendarEventProviding? = nil,
        loginItemManager: LoginItemManaging = LoginItemManager(),
        selectedPane: SettingsPane = .general,
        onShortcutChangeRequested: @escaping (GlobalShortcut) -> HotKeyRegistrationResult = { _ in .success },
        onAccessRequestCompleted: @escaping () -> Void = {},
        onChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
        self.selectedPane = selectedPane
        let settings = settingsStore.settings
        self.selectedMode = settings.displayMode
        self.lookAheadDays = settings.lookAheadDays
        self.showEventColors = settings.showEventColors
        self.showAllDayEvents = settings.showAllDayEvents
        self.selectedCalendarIdentifiers = settings.selectedCalendarIdentifiers
        self.launchAtLogin = loginItemManager.isEnabled
        self.globalShortcut = settings.globalShortcut
        self.accessState = permissionController.accessState
        self.onShortcutChangeRequested = onShortcutChangeRequested
        self.onAccessRequestCompleted = onAccessRequestCompleted
        self.onChange = onChange

        subscribeToAccessStateChanges()
        refreshAvailableCalendars()
    }
    #endif

    private func subscribeToAccessStateChanges() {
        accessStateCancellable = permissionController.$accessState
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] accessState in
                self?.accessState = accessState
                self?.refreshAvailableCalendars()
            }
    }

    func refreshAvailableCalendars() {
        calendarLoadTask?.cancel()

        guard accessState.isSufficientForReadingEvents else {
            isLoadingCalendars = false
            availableCalendars = []
            calendarLoadingError = nil
            return
        }

        guard let calendarProvider else {
            isLoadingCalendars = false
            return
        }

        isLoadingCalendars = true
        calendarLoadingError = nil

        calendarLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let calendars = try await calendarProvider.availableCalendars()
                guard !Task.isCancelled else {
                    return
                }

                availableCalendars = calendars
                calendarLoadingError = nil
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                availableCalendars = []
                calendarLoadingError = "Could not load calendars."
            }

            isLoadingCalendars = false
        }
    }

    func isCalendarSelected(_ calendar: CalendarInfo) -> Bool {
        selectedCalendarIdentifiers?.contains(calendar.id) ?? true
    }

    func setCalendar(_ calendar: CalendarInfo, isSelected: Bool) {
        setCalendars([calendar], isSelected: isSelected)
    }

    func setCalendars(_ calendars: [CalendarInfo], isSelected: Bool) {
        guard !availableCalendars.isEmpty else {
            return
        }

        let availableIdentifiers = Set(availableCalendars.map(\.id))
        let changedIdentifiers = Set(calendars.map(\.id)).intersection(availableIdentifiers)
        guard !changedIdentifiers.isEmpty else {
            return
        }

        var selectedIdentifiers = selectedCalendarIdentifiers ?? availableIdentifiers

        if isSelected {
            selectedIdentifiers.formUnion(changedIdentifiers)
        } else {
            selectedIdentifiers.subtract(changedIdentifiers)
        }

        let normalizedSelection = selectedIdentifiers.isSuperset(of: availableIdentifiers)
            ? nil
            : selectedIdentifiers
        guard normalizedSelection != selectedCalendarIdentifiers else {
            return
        }

        applySelectedCalendarIdentifiers(normalizedSelection)
    }

    func selectAllCalendars() {
        applySelectedCalendarIdentifiers(nil)
    }

    func selectNoCalendars() {
        applySelectedCalendarIdentifiers([])
    }

    private func applySelectedCalendarIdentifiers(_ selectedIdentifiers: Set<String>?) {
        selectedCalendarIdentifiers = selectedIdentifiers
        settingsStore.updateSelectedCalendarIdentifiers(selectedIdentifiers)
        onChange()
    }

    var accessActionTitle: String? {
        switch accessState.settingsAction {
        case .requestAccess:
            return "Allow Access..."
        case .openPrivacySettings:
            return "Open Privacy Settings..."
        case nil:
            return nil
        }
    }

    func performAccessAction() {
        switch accessState.settingsAction {
        case .requestAccess:
            requestCalendarAccess()
        case .openPrivacySettings:
            openCalendarPrivacySettings()
        case nil:
            break
        }
    }

    func requestCalendarAccess() {
        guard !isRequestingAccess else {
            return
        }

        isRequestingAccess = true

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            _ = await permissionController.requestFullAccess()
            isRequestingAccess = false
            onAccessRequestCompleted()
            onChange()
        }
    }

    func openCalendarPrivacySettings() {
        permissionController.openPrivacySettings()
    }

    private func applyLaunchAtLoginChange() {
        do {
            try loginItemManager.setEnabled(launchAtLogin)
            loginItemError = nil
        } catch {
            loginItemError = "Could not update launch at login."
        }

        refreshLaunchAtLoginState()
    }

    func refreshLaunchAtLoginState() {
        isApplyingLoginItemState = true
        launchAtLogin = loginItemManager.isEnabled
        isApplyingLoginItemState = false
    }

    func recordShortcut(from event: NSEvent) {
        guard let candidate = GlobalShortcut.candidate(from: event) else {
            shortcutError = "Press a printable key with Command, Control, or Option."
            return
        }

        applyShortcut(candidate)
    }

    func resetShortcutToDefault() {
        applyShortcut(.defaultValue)
    }

    private func applyShortcut(_ candidate: GlobalShortcut) {
        switch onShortcutChangeRequested(candidate) {
        case .success:
            settingsStore.updateGlobalShortcut(candidate)
            globalShortcut = candidate
            shortcutError = nil
            onChange()
        case .failure:
            shortcutError = "Shortcut is already in use."
        }
    }

    deinit {
        calendarLoadTask?.cancel()
    }
}

struct SettingsView: View {
    static let contentWidth: CGFloat = 560
    fileprivate static let sectionCornerRadius: CGFloat = 11
    fileprivate static let insetCornerRadius: CGFloat = 8
    fileprivate static let menuPickerWidth: CGFloat = 176
    fileprivate static let accessoryColumnWidth: CGFloat = 220
    fileprivate static let shortcutRecorderWidth: CGFloat = 150

    @ObservedObject var model: SettingsViewModel
    @State private var calendarSearchText = ""
    private let onContentHeightChange: (CGFloat) -> Void

    init(
        model: SettingsViewModel,
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        ZStack {
            SettingsWindowBackdrop()

            ScrollView {
                paneContent
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SettingsContentHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            .scrollContentBackground(.hidden)
            .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
                guard height > 0 else {
                    return
                }

                onContentHeightChange(ceil(height))
            }
        }
        .frame(width: Self.contentWidth)
    }

    @ViewBuilder
    private var paneContent: some View {
        Group {
            switch model.selectedPane {
            case .general:
                generalSettings
            case .calendars:
                calendarSettings
            case .menuBar:
                menuBarSettings
            }
        }
        .id(model.selectedPane)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Startup") {
                SettingsRow(
                    title: "Launch at Login",
                    detail: nil
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Toggle("Launch at Login", isOn: $model.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)

                        if let loginItemError = model.loginItemError {
                            Text(loginItemError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            SettingsSection(title: "Keyboard") {
                SettingsRow(
                    title: "Open Menu",
                    detail: nil
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            ShortcutRecorderView(shortcut: model.globalShortcut) { event in
                                model.recordShortcut(from: event)
                            }
                            .frame(width: Self.shortcutRecorderWidth, height: 28)

                            Button("Reset") {
                                model.resetShortcutToDefault()
                            }
                            .disabled(model.globalShortcut == .defaultValue)
                        }

                        if let shortcutError = model.shortcutError {
                            Text(shortcutError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            #if DEBUG
            SettingsSection(title: "Debug") {
                SettingsRow(title: "Date Icon Override", detail: nil) {
                    Toggle("Date Icon Override", isOn: $model.debugDateIconOverrideEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRowDivider()

                SettingsRow(title: "Date", detail: nil) {
                    Stepper(value: $model.debugDateIconDay, in: 1...31) {
                        Text("\(model.debugDateIconDay)")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .leading)
                    }
                    .disabled(!model.debugDateIconOverrideEnabled)
                }

                SettingsRowDivider()

                SettingsStackedRow(title: "Weight") {
                    Picker("Weight", selection: $model.debugDateIconFontWeight) {
                        ForEach(DateIconDebugFontWeight.allCases) { weight in
                            Text(weight.displayTitle).tag(weight)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    .disabled(!model.debugDateIconOverrideEnabled)
                }
            }
            #endif
        }
    }

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Privacy") {
                accessRow
            }

            SettingsSection(title: "Included Calendars") {
                calendarSelectionRow
            }
        }
    }

    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Upcoming Events") {
                SettingsRow(
                    title: "Include Events",
                    detail: nil
                ) {
                    Picker("Include Events", selection: $model.lookAheadDays) {
                        ForEach(CalendarMenubarSettings.supportedLookAheadDays, id: \.self) { days in
                            Text("\(days) \(days == 1 ? "day" : "days")").tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: Self.menuPickerWidth, alignment: .trailing)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "Event Title",
                    detail: nil
                ) {
                    Picker("Event Title", selection: $model.selectedMode) {
                        ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: Self.menuPickerWidth, alignment: .trailing)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "All-Day Events",
                    detail: nil
                ) {
                    Toggle("All-Day Events", isOn: $model.showAllDayEvents)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(title: "Appearance") {
                SettingsRow(
                    title: "Calendar Colors",
                    detail: nil
                ) {
                    Toggle("Calendar Colors", isOn: $model.showEventColors)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var accessRow: some View {
        SettingsRow(title: "Calendar Access", detail: model.accessState.statusDetail) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: model.accessState.isSufficientForReadingEvents ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.accessState.isSufficientForReadingEvents ? .green : .orange)

                    Text(accessStatusDisplayTitle)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.isRequestingAccess {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.58)
                        .frame(width: 16, height: 16)
                        .transition(.opacity)
                }

                if let actionTitle = model.accessActionTitle {
                    Button(actionTitle) {
                        model.performAccessAction()
                    }
                    .controlSize(.small)
                    .disabled(model.isRequestingAccess)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: model.accessState)
            .animation(.easeInOut(duration: 0.16), value: model.isRequestingAccess)
        }
    }

    private var accessStatusDisplayTitle: String {
        switch model.accessState {
        case .notDetermined:
            return "Not set"
        case .fullAccess:
            return "Enabled"
        case .writeOnly:
            return "Write only"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unknown:
            return "Unavailable"
        }
    }

    private var calendarSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Events From")
                        .font(.body)
                    Text(calendarSelectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack(spacing: 6) {
                    Button("All") {
                        model.selectAllCalendars()
                    }
                    .disabled(!canEditCalendarSelection || model.selectedCalendarIdentifiers == nil)
                    .help("Select all calendars")

                    Button("None") {
                        model.selectNoCalendars()
                    }
                    .disabled(!canEditCalendarSelection || model.selectedCalendarIdentifiers?.isEmpty == true)
                    .help("Deselect all calendars")
                }
                .controlSize(.small)
                .disabled(!canEditCalendarSelection)
            }

            calendarSelectionContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
    }

    private var calendarSelectionContent: some View {
        CalendarSelectionContent(
            phase: calendarSelectionPhase,
            calendars: model.availableCalendars,
            calendarListHeight: calendarListHeight,
            isSelected: { model.isCalendarSelected($0) },
            setSelected: { model.setCalendar($0, isSelected: $1) },
            setCalendarsSelected: { model.setCalendars($0, isSelected: $1) },
            searchText: $calendarSearchText
        )
        .id(calendarSelectionPhase.id)
    }

    private var calendarSelectionPhase: CalendarSelectionPhase {
        if !model.accessState.isSufficientForReadingEvents {
            return .needsAccess
        }

        if model.isLoadingCalendars {
            return .loading
        }

        if let calendarLoadingError = model.calendarLoadingError {
            return .error(calendarLoadingError)
        }

        if model.availableCalendars.isEmpty {
            return .empty
        }

        return .loaded
    }

    private var calendarSelectionSummary: String {
        guard model.accessState.isSufficientForReadingEvents else {
            return "Calendar access required"
        }

        if model.isLoadingCalendars {
            return "Loading calendars..."
        }

        return model.selectedCalendarIdentifiers == nil
            ? "All calendars"
            : "\(model.selectedCalendarIdentifiers?.count ?? 0) selected"
    }

    private var canEditCalendarSelection: Bool {
        model.accessState.isSufficientForReadingEvents
            && !model.isLoadingCalendars
            && !model.availableCalendars.isEmpty
    }

    private var calendarListHeight: CGFloat {
        let visibleRows = min(max(model.availableCalendars.count, 1), CalendarPickerLayout.maximumVisibleRows)
        return CGFloat(visibleRows) * CalendarPickerLayout.rowHeight
            + (CalendarPickerLayout.verticalPadding * 2)
    }
}

private enum CalendarPickerLayout {
    static let rowHeight: CGFloat = 36
    static let maximumVisibleRows = 6
    static let verticalPadding: CGFloat = 4
    static let scrollbarGutter: CGFloat = 18
}

private enum CalendarPickerFilter {
    static func matching(_ calendars: [CalendarInfo], query: String) -> [CalendarInfo] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return calendars
        }

        return calendars.filter { calendar in
            calendar.title.localizedCaseInsensitiveContains(query)
                || calendar.sourceTitle.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum CalendarSelectionPhase: Equatable {
    case needsAccess
    case loading
    case error(String)
    case empty
    case loaded

    var id: String {
        switch self {
        case .needsAccess:
            return "needsAccess"
        case .loading:
            return "loading"
        case let .error(message):
            return "error-\(message)"
        case .empty:
            return "empty"
        case .loaded:
            return "loaded"
        }
    }
}

private struct CalendarSelectionContent: View {
    let phase: CalendarSelectionPhase
    let calendars: [CalendarInfo]
    let calendarListHeight: CGFloat
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void
    let setCalendarsSelected: ([CalendarInfo], Bool) -> Void
    @Binding var searchText: String

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .needsAccess:
            CalendarSelectionMessage(systemImage: "lock", text: "Grant access to choose calendars.")
        case .loading:
            CalendarSelectionMessage(systemImage: nil, text: "Loading calendars...", showsProgress: true)
        case let .error(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .empty:
            CalendarSelectionMessage(systemImage: "calendar.badge.exclamationmark", text: "No calendars found")
        case .loaded:
            CalendarPickerContainer(
                calendars: calendars,
                calendarListHeight: calendarListHeight,
                isSelected: isSelected,
                setSelected: setSelected,
                setCalendarsSelected: setCalendarsSelected,
                searchText: $searchText
            )
        }
    }
}

private struct CalendarPickerContainer: View {
    let calendars: [CalendarInfo]
    let calendarListHeight: CGFloat
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void
    let setCalendarsSelected: ([CalendarInfo], Bool) -> Void
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 8) {
            if calendars.count > CalendarPickerLayout.maximumVisibleRows {
                TextField("Search calendars", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search calendars")
            }

            Group {
                if filteredCalendars.isEmpty {
                    CalendarPickerEmptySearch(query: searchText)
                } else {
                    CalendarPickerScrollView(
                        calendars: filteredCalendars,
                        isSelected: isSelected,
                        setSelected: setSelected,
                        setCalendarsSelected: setCalendarsSelected
                    )
                }
            }
            .frame(height: calendarListHeight)
            .modifier(SettingsInsetSurface(cornerRadius: SettingsView.insetCornerRadius))
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var filteredCalendars: [CalendarInfo] {
        CalendarPickerFilter.matching(calendars, query: searchText)
    }
}

private struct CalendarPickerEmptySearch: View {
    let query: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)

            Text("No matching calendars")
                .font(.callout.weight(.medium))

            Text("Try a calendar or account name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No calendars match \(query)")
    }
}

private struct CalendarSelectionMessage: View {
    let systemImage: String?
    let text: String
    var showsProgress = false

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.58)
                    .frame(width: 16, height: 16)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

private struct CalendarPickerScrollView: View {
    let calendars: [CalendarInfo]
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void
    let setCalendarsSelected: ([CalendarInfo], Bool) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(calendarGroups) { group in
                    CalendarPickerGroupHeader(
                        group: group,
                        selectedCount: group.calendars.count(where: isSelected),
                        setSelected: { setCalendarsSelected(group.calendars, $0) }
                    )

                    ForEach(Array(group.calendars.enumerated()), id: \.element.id) { index, calendar in
                        CalendarPickerRow(
                            calendar: calendar,
                            isSelected: isSelected(calendar),
                            setSelected: { setSelected(calendar, $0) },
                            showsDivider: index < group.calendars.count - 1
                        )
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, CalendarPickerLayout.scrollbarGutter)
            .padding(.vertical, CalendarPickerLayout.verticalPadding)
        }
        .scrollIndicators(.automatic)
    }

    private var calendarGroups: [CalendarPickerGroup] {
        calendars.reduce(into: []) { groups, calendar in
            if let index = groups.firstIndex(where: { $0.sourceTitle == calendar.sourceTitle }) {
                groups[index].calendars.append(calendar)
            } else {
                groups.append(CalendarPickerGroup(sourceTitle: calendar.sourceTitle, calendars: [calendar]))
            }
        }
    }
}

private struct CalendarPickerGroup: Identifiable {
    let sourceTitle: String
    var calendars: [CalendarInfo]

    var id: String { sourceTitle }
}

private struct CalendarPickerGroupHeader: View {
    let group: CalendarPickerGroup
    let selectedCount: Int
    let setSelected: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(group.sourceTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(selectedCount == group.calendars.count ? "Clear" : "Select All") {
                setSelected(selectedCount != group.calendars.count)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: 27)
        .accessibilityElement(children: .contain)
    }
}

private struct CalendarPickerRow: View {
    let calendar: CalendarInfo
    let isSelected: Bool
    let setSelected: (Bool) -> Void
    let showsDivider: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            setSelected(!isSelected)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                Circle()
                    .fill(Color(nsColor: calendar.color))
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(calendar.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: CalendarPickerLayout.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Divider()
                        .padding(.leading, 42)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(calendar.title), \(calendar.sourceTitle)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles whether events from this calendar are shown")
    }

    private var rowBackground: Color {
        if isHovering {
            return Color.primary.opacity(0.065)
        }

        return isSelected ? Color.accentColor.opacity(0.075) : .clear
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content
            }
            .modifier(SettingsGroupSurface(cornerRadius: SettingsView.sectionCornerRadius))
        }
    }
}

private struct SettingsWindowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if colorScheme == .dark {
                Color.black.opacity(0.08)
            } else {
                Color.black.opacity(0.035)
            }
        }
        .ignoresSafeArea()
    }
}

private struct SettingsGroupSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        if colorScheme == .dark {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.82), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: cardShadow, radius: 2, y: 1)
    }

    private var cardShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.22)
            : Color.black.opacity(0.055)
    }
}

private struct SettingsInsetSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                insetShape
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        insetShape
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.1 : 0.025))
                    }
            }
            .overlay {
                insetShape
                    .stroke(Color(nsColor: .separatorColor).opacity(0.9), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .clipShape(insetShape)
    }

    private var insetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 18)

            accessory
                .frame(width: SettingsView.accessoryColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

private struct SettingsStackedRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.callout)

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onRecord: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
        button.onRecordingChanged = { isRecording in
            context.coordinator.isRecording = isRecording
            updateTitle(for: button, isRecording: isRecording)
        }
        button.onKeyDown = { event in
            guard event.keyCode != UInt16(kVK_Escape) else {
                button.stopRecording()
                return
            }

            onRecord(event)
            button.stopRecording()
        }
        updateTitle(for: button, isRecording: context.coordinator.isRecording)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        updateTitle(for: button, isRecording: context.coordinator.isRecording)
    }

    private func updateTitle(for button: ShortcutRecorderButton, isRecording: Bool) {
        button.title = isRecording ? "Type shortcut" : shortcut.displayTitle
    }

    final class Coordinator {
        var isRecording = false
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecordingChanged: ((Bool) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    func stopRecording() {
        isRecording = false
        onRecordingChanged?(false)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        onKeyDown?(event)
    }
}
