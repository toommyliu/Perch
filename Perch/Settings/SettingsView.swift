import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
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
        onShortcutChangeRequested: @escaping (GlobalShortcut) -> HotKeyRegistrationResult = { _ in .success },
        onAccessRequestCompleted: @escaping () -> Void = {},
        onChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
        self.dateIconDebugSettings = dateIconDebugSettings
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
        onShortcutChangeRequested: @escaping (GlobalShortcut) -> HotKeyRegistrationResult = { _ in .success },
        onAccessRequestCompleted: @escaping () -> Void = {},
        onChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
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
        guard !availableCalendars.isEmpty else {
            return
        }

        var selectedIdentifiers = selectedCalendarIdentifiers ?? Set(availableCalendars.map(\.id))

        if isSelected {
            selectedIdentifiers.insert(calendar.id)
        } else {
            selectedIdentifiers.remove(calendar.id)
        }

        applySelectedCalendarIdentifiers(selectedIdentifiers)
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
    private static let contentWidth: CGFloat = 640
    fileprivate static let controlWidth: CGFloat = 132
    fileprivate static let accessoryColumnWidth: CGFloat = 216
    fileprivate static let shortcutRecorderWidth: CGFloat = 150

    @ObservedObject var model: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: "Calendar") {
                    accessRow
                    SettingsRowDivider()
                    calendarSelectionRow
                }

                SettingsSection(title: "Menu Bar") {
                    SettingsRow(
                        title: "Include Events",
                        detail: "How far ahead Perch looks for upcoming events."
                    ) {
                        Picker("Include Events", selection: $model.lookAheadDays) {
                            ForEach(CalendarMenubarSettings.supportedLookAheadDays, id: \.self) { days in
                                Text("\(days) \(days == 1 ? "day" : "days")").tag(days)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: Self.controlWidth)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        title: "Event Title",
                        detail: "When to show the next event title beside the menu bar icon."
                    ) {
                        Picker("Event Title", selection: $model.selectedMode) {
                            ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayTitle).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: Self.controlWidth)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        title: "All-Day Events",
                        detail: "Include all-day events in the menu and label."
                    ) {
                        Toggle("All-Day Events", isOn: $model.showAllDayEvents)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        title: "Calendar Colors",
                        detail: "Use calendar colors to identify events."
                    ) {
                        Toggle("Calendar Colors", isOn: $model.showEventColors)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsSection(title: "App") {
                    SettingsRow(
                        title: "Launch at Login",
                        detail: "Start Perch automatically when you sign in."
                    ) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Toggle("Launch at Login", isOn: $model.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)

                            if let loginItemError = model.loginItemError {
                                Text(loginItemError)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        title: "Open Menu",
                        detail: "Press this shortcut to open or close the Perch menu."
                    ) {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 8) {
                                ShortcutRecorderView(shortcut: model.globalShortcut) { event in
                                    model.recordShortcut(from: event)
                                }
                                .frame(width: Self.shortcutRecorderWidth, height: 26)

                                Button("Reset") {
                                    model.resetShortcutToDefault()
                                }
                                .controlSize(.small)
                                .disabled(model.globalShortcut == .defaultValue)
                            }

                            if let shortcutError = model.shortcutError {
                                Text(shortcutError)
                                    .font(.callout)
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
                        HStack {
                            Picker("Weight", selection: $model.debugDateIconFontWeight) {
                                ForEach(DateIconDebugFontWeight.allCases) { weight in
                                    Text(weight.displayTitle).tag(weight)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                            .disabled(!model.debugDateIconOverrideEnabled)

                            Spacer(minLength: 0)
                        }
                    }
                }
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: Self.contentWidth)
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
                    Text("Calendars")
                        .font(.callout)
                    Text(calendarSelectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack(spacing: 8) {
                    Button("Select All") {
                        model.selectAllCalendars()
                    }
                    .controlSize(.small)
                    .disabled(!canEditCalendarSelection || model.selectedCalendarIdentifiers == nil)

                    Button("Deselect All") {
                        model.selectNoCalendars()
                    }
                    .controlSize(.small)
                    .disabled(!canEditCalendarSelection || model.selectedCalendarIdentifiers?.isEmpty == true)
                }
                .frame(width: Self.accessoryColumnWidth, alignment: .trailing)
            }

            calendarSelectionContent
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    private var calendarSelectionContent: some View {
        CalendarSelectionContent(
            phase: calendarSelectionPhase,
            calendars: model.availableCalendars,
            calendarListHeight: calendarListHeight,
            isSelected: { model.isCalendarSelected($0) },
            setSelected: { model.setCalendar($0, isSelected: $1) }
        )
        .id(calendarSelectionPhase.id)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.18), value: calendarSelectionPhase.id)
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
        let rowHeight: CGFloat = 38
        let visibleRows = min(max(model.availableCalendars.count, 1), 4)
        return CGFloat(visibleRows) * rowHeight
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
                setSelected: setSelected
            )
        }
    }
}

private struct CalendarPickerContainer: View {
    let calendars: [CalendarInfo]
    let calendarListHeight: CGFloat
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void

    var body: some View {
        CalendarPickerScrollView(
            calendars: calendars,
            isSelected: isSelected,
            setSelected: setSelected
        )
        .frame(height: calendarListHeight)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
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

private struct CalendarPickerScrollView: NSViewRepresentable {
    let calendars: [CalendarInfo]
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> EdgeAwareScrollView {
        let scrollView = EdgeAwareScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: rowsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width]
        context.coordinator.hostingView = hostingView
        scrollView.documentView = hostingView

        return scrollView
    }

    func updateNSView(_ scrollView: EdgeAwareScrollView, context: Context) {
        guard let hostingView = context.coordinator.hostingView else {
            return
        }

        hostingView.rootView = rowsView
        updateDocumentSize(hostingView, in: scrollView)
    }

    private var rowsView: CalendarPickerRows {
        CalendarPickerRows(
            calendars: calendars,
            isSelected: isSelected,
            setSelected: setSelected
        )
    }

    private func updateDocumentSize(_ hostingView: NSHostingView<CalendarPickerRows>, in scrollView: NSScrollView) {
        let width = max(scrollView.contentView.bounds.width, 1)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(fittingSize.height, scrollView.contentView.bounds.height)
        )
    }

    final class Coordinator {
        var hostingView: NSHostingView<CalendarPickerRows>?
    }
}

private struct CalendarPickerRows: View {
    let calendars: [CalendarInfo]
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                CalendarPickerRow(
                    calendar: calendar,
                    isSelected: isSelected(calendar),
                    setSelected: { setSelected(calendar, $0) }
                )

                if index < calendars.count - 1 {
                    Divider()
                        .padding(.leading, 42)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarPickerRow: View {
    let calendar: CalendarInfo
    let isSelected: Bool
    let setSelected: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: setSelected
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 14, height: 14)
            .padding(.top, 5)

            Circle()
                .fill(Color(nsColor: calendar.color))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(calendar.title)
                    .lineLimit(1)

                Text(calendar.sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .onTapGesture {
            setSelected(!isSelected)
        }
    }
}

final class EdgeAwareScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard canScrollVertically else {
            nextResponder?.scrollWheel(with: event)
            return
        }

        let visibleMinY = contentView.bounds.minY
        let maxY = max((documentView?.bounds.height ?? 0) - contentView.bounds.height, 0)
        let wantsToScrollUp = event.scrollingDeltaY > 0
        let wantsToScrollDown = event.scrollingDeltaY < 0

        if (wantsToScrollUp && visibleMinY > 0) || (wantsToScrollDown && visibleMinY < maxY) {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func layout() {
        super.layout()

        guard let documentView else {
            return
        }

        documentView.frame.size.width = contentView.bounds.width
    }

    private var canScrollVertically: Bool {
        guard let documentView else {
            return false
        }

        return documentView.bounds.height > contentView.bounds.height
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 1)

            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(sectionStroke, lineWidth: 0.5)
            }
        }
    }

    private var sectionStroke: Color {
        colorScheme == .dark
            ? Color(nsColor: .separatorColor).opacity(0.34)
            : Color(nsColor: .separatorColor).opacity(0.42)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 48)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
