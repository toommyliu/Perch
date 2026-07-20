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
            return "Privacy Settings..."
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
    static let contentWidth: CGFloat = 420
    private static let headerHeight: CGFloat = 50
    private static let panelCornerRadius: CGFloat = 14
    private static let contentHorizontalPadding: CGFloat = 18
    fileprivate static let shortcutRecorderWidth: CGFloat = 112

    @ObservedObject var model: SettingsViewModel
    @State private var isCalendarChooserPresented = false
    @State private var isDeveloperSettingsExpanded = false
    private let onReturnToMenu: () -> Void
    private let onContentHeightChange: (CGFloat) -> Void

    init(
        model: SettingsViewModel,
        onReturnToMenu: @escaping () -> Void = {},
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.onReturnToMenu = onReturnToMenu
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        ZStack {
            SettingsWindowBackdrop()

            VStack(spacing: 0) {
                panelHeader

                Divider()
                    .opacity(0.48)

                ScrollView(.vertical) {
                    settingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
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
                .contentMargins(
                    .horizontal,
                    Self.contentHorizontalPadding,
                    for: .scrollContent
                )
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
                    guard height > 0 else { return }
                    onContentHeightChange(ceil(height + Self.headerHeight + 1))
                }
            }
        }
        .frame(width: Self.contentWidth)
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .controlSize(.small)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Button(action: onReturnToMenu) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .help("Back to events")
            .accessibilityLabel("Back to events")

            Text("Settings")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: Self.headerHeight)
        .frame(maxWidth: .infinity)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            eventSettings
            appSettings
            #if DEBUG
            developerSettings
            #endif
        }
    }

    private var appSettings: some View {
        SettingsSection(
            title: "App",
            subtitle: "Startup and keyboard access."
        ) {
            SettingsRow(
                title: "Open at login",
                detail: nil
            ) {
                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("Open at login", isOn: $model.launchAtLogin)
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

            SettingsRowDivider()

            SettingsRow(
                title: "Keyboard shortcut",
                detail: nil
            ) {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(shortcut: model.globalShortcut) { event in
                            model.recordShortcut(from: event)
                        }
                        .frame(width: Self.shortcutRecorderWidth, height: 24)

                        Button("Reset") {
                            model.resetShortcutToDefault()
                        }
                        .buttonStyle(.borderless)
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
    }

    #if DEBUG
    private var developerSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isDeveloperSettingsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isDeveloperSettingsExpanded ? 90 : 0))
                        .frame(width: 12, height: 12)

                    Text("Developer")
                        .font(.callout.weight(.semibold))

                    Spacer()
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Developer settings")
            .accessibilityValue(isDeveloperSettingsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Date icon preview controls")

            if isDeveloperSettingsExpanded {
                VStack(spacing: 0) {
                    SettingsRow(
                        title: "Preview date icon",
                        detail: nil
                    ) {
                        Toggle("Preview date icon", isOn: $model.debugDateIconOverrideEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    SettingsRowDivider()

                    SettingsRow(title: "Displayed day", detail: nil) {
                        Stepper(value: $model.debugDateIconDay, in: 1...31) {
                            Text("\(model.debugDateIconDay)")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .leading)
                        }
                        .disabled(!model.debugDateIconOverrideEnabled)
                    }

                    SettingsRowDivider()

                    SettingsRow(title: "Font weight", detail: nil) {
                        SettingsValueMenu(
                            title: "Font weight",
                            selection: $model.debugDateIconFontWeight,
                            options: DateIconDebugFontWeight.allCases,
                            label: \.displayTitle
                        )
                        .disabled(!model.debugDateIconOverrideEnabled)
                    }
                }
                .overlay(alignment: .top) { Divider() }
                .padding(.top, 8)
            }
        }
        .settingsSectionSurface()
    }
    #endif

    private var eventSettings: some View {
        SettingsSection(
            title: "Events",
            subtitle: "Choose what appears in the tray menu and menu bar."
        ) {
            if model.accessState.isSufficientForReadingEvents {
                calendarSelectionRow
            } else {
                calendarAccessRow
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Event range",
                detail: nil
            ) {
                SettingsValueMenu(
                    title: "Event range",
                    selection: $model.lookAheadDays,
                    options: CalendarMenubarSettings.supportedLookAheadDays,
                    label: lookAheadTitle
                )
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Show next event",
                detail: nil
            ) {
                SettingsValueMenu(
                    title: "Show next event",
                    selection: $model.selectedMode,
                    options: MenuBarDisplayMode.allCases,
                    label: \.displayTitle
                )
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Include all-day events",
                detail: nil
            ) {
                Toggle("All-day events", isOn: $model.showAllDayEvents)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Use calendar colors",
                detail: nil
            ) {
                Toggle("Calendar colors", isOn: $model.showEventColors)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var calendarAccessRow: some View {
        SettingsRow(
            title: "Calendar access",
            detail: nil
        ) {
            if model.isRequestingAccess {
                ProgressView()
                    .controlSize(.small)
            } else if let actionTitle = model.accessActionTitle {
                HStack(spacing: 10) {
                    Text("Required")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(actionTitle) {
                        model.performAccessAction()
                    }
                    .controlSize(.small)
                }
            } else {
                Text("Unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isRequestingAccess)
    }

    private var calendarSelectionRow: some View {
        SettingsRow(
            title: "Calendars",
            detail: nil
        ) {
            CalendarSelectionPopoverButton(
                summary: calendarSelectionSummary,
                isEnabled: canEditCalendarSelection,
                isPresented: $isCalendarChooserPresented,
                selectedCalendarIdentifiers: model.selectedCalendarIdentifiers,
                calendars: model.availableCalendars,
                isSelected: { model.isCalendarSelected($0) },
                setSelected: { model.setCalendar($0, isSelected: $1) },
                setCalendarsSelected: { model.setCalendars($0, isSelected: $1) },
                selectAll: model.selectAllCalendars,
                selectNone: model.selectNoCalendars
            )
        }
    }

    private var calendarSelectionSummary: String {
        guard model.accessState.isSufficientForReadingEvents else {
            return "Access required"
        }

        if model.isLoadingCalendars {
            return "Loading…"
        }

        if model.calendarLoadingError != nil {
            return "Unavailable"
        }

        guard !model.availableCalendars.isEmpty else {
            return "No calendars"
        }

        if model.selectedCalendarIdentifiers == nil {
            return "All calendars"
        }

        let selectedCalendars = model.availableCalendars.filter(model.isCalendarSelected)
        switch selectedCalendars.count {
        case 0:
            return "No calendars"
        case 1:
            return selectedCalendars[0].title
        case model.availableCalendars.count:
            return "All calendars"
        default:
            return "\(selectedCalendars.count) calendars"
        }
    }

    private var canEditCalendarSelection: Bool {
        model.accessState.isSufficientForReadingEvents
            && !model.isLoadingCalendars
            && model.calendarLoadingError == nil
            && !model.availableCalendars.isEmpty
    }

    private func lookAheadTitle(for days: Int) -> String {
        days == 1 ? "Today" : "Next \(days) days"
    }
}

private struct CalendarSelectionPopoverButton: View {
    let summary: String
    let isEnabled: Bool
    @Binding var isPresented: Bool
    let selectedCalendarIdentifiers: Set<String>?
    let calendars: [CalendarInfo]
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void
    let setCalendarsSelected: ([CalendarInfo], Bool) -> Void
    let selectAll: () -> Void
    let selectNone: () -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(summary)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!isEnabled)
        .accessibilityLabel("Calendars to show")
        .accessibilityValue(summary)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            CalendarSelectionPopover(
                selectedCalendarIdentifiers: selectedCalendarIdentifiers,
                calendarGroups: calendarGroups,
                isSelected: isSelected,
                setSelected: setSelected,
                setCalendarsSelected: setCalendarsSelected,
                selectAll: selectAll,
                selectNone: selectNone
            )
        }
    }

    private var calendarGroups: [CalendarSourceGroup] {
        calendars.reduce(into: []) { groups, calendar in
            if let index = groups.firstIndex(where: { $0.id == calendar.sourceIdentifier }) {
                groups[index].calendars.append(calendar)
            } else {
                groups.append(CalendarSourceGroup(
                    sourceIdentifier: calendar.sourceIdentifier,
                    sourceTitle: calendar.sourceTitle,
                    calendars: [calendar]
                ))
            }
        }
    }
}

private struct CalendarSelectionPopover: View {
    private static let scrollbarTrailingPadding: CGFloat = 0
    private static let scrollbarAccessoryInset: CGFloat = 8
    private static let scrollbarCueInset: CGFloat = 10

    let selectedCalendarIdentifiers: Set<String>?
    let calendarGroups: [CalendarSourceGroup]
    let isSelected: (CalendarInfo) -> Bool
    let setSelected: (CalendarInfo, Bool) -> Void
    let setCalendarsSelected: ([CalendarInfo], Bool) -> Void
    let selectAll: () -> Void
    let selectNone: () -> Void

    @State private var hasMoreCalendarsBelow = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Calendars")
                    .font(.body.weight(.semibold))

                Spacer()

                Button(selectedCalendarIdentifiers == nil ? "Hide All" : "Show All") {
                    if selectedCalendarIdentifiers == nil {
                        selectNone()
                    } else {
                        selectAll()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            Divider()

            if shouldScroll {
                ScrollView {
                    sourceList
                        .background {
                            CalendarPickerScrollObserver(
                                hasMoreContentBelow: $hasMoreCalendarsBelow
                            )
                        }
                }
                .frame(maxHeight: 304)
                .scrollIndicators(.visible)
                .overlay(alignment: .bottom) {
                    if hasMoreCalendarsBelow {
                        CalendarPickerMoreIndicator()
                            .padding(.trailing, Self.scrollbarCueInset)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: hasMoreCalendarsBelow)
                .padding(.leading, 8)
                .padding(.trailing, Self.scrollbarTrailingPadding)
                .padding(.vertical, 9)
            } else {
                sourceList
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
            }
        }
        .frame(width: 304)
    }

    private var sourceList: some View {
        VStack(spacing: 10) {
            ForEach(calendarGroups) { group in
                sourceGroup(group)
            }
        }
    }

    private func sourceGroup(_ group: CalendarSourceGroup) -> some View {
        let selectedCount = group.calendars.count(where: isSelected)
        let selectsEveryCalendar = selectedCount == group.calendars.count

        return VStack(alignment: .leading, spacing: 2) {
            CalendarPickerSourceRow(
                title: group.sourceTitle,
                selectedCount: selectedCount,
                totalCount: group.calendars.count,
                trailingAccessoryInset: shouldScroll ? Self.scrollbarAccessoryInset : 0
            ) {
                setCalendarsSelected(group.calendars, !selectsEveryCalendar)
            }

            ForEach(group.calendars) { calendar in
                CalendarPickerCalendarRow(
                    calendar: calendar,
                    isSelected: isSelected(calendar),
                    trailingAccessoryInset: shouldScroll ? Self.scrollbarAccessoryInset : 0
                ) {
                    setSelected(calendar, !isSelected(calendar))
                }
            }
        }
    }

    private var shouldScroll: Bool {
        calendarGroups.flatMap(\.calendars).count > 8
    }

}

private struct CalendarPickerMoreIndicator: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0),
                    Color(nsColor: .windowBackgroundColor).opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 14)

            HStack(spacing: 5) {
                Text("More calendars below")

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CalendarPickerSourceRow: View {
    let title: String
    let selectedCount: Int
    let totalCount: Int
    let trailingAccessoryInset: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                CalendarPickerGroupSelectionMark(
                    selectedCount: selectedCount,
                    totalCount: totalCount
                )
            }
            .padding(.leading, 8)
            .padding(.trailing, 8 + trailingAccessoryInset)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityValue("\(selectedCount) of \(totalCount) shown")
        .accessibilityHint(selectedCount == totalCount ? "Hides this source" : "Shows every calendar in this source")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? 0.055 : 0))
    }
}

private struct CalendarPickerGroupSelectionMark: View {
    let selectedCount: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(selectedCount == 0 ? Color.clear : Color.accentColor)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(selectedCount == 0 ? Color.secondary.opacity(0.72) : Color.accentColor, lineWidth: 1)

            if selectedCount > 0 {
                Image(systemName: selectedCount == totalCount ? "checkmark" : "minus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 13, height: 13)
    }
}

private struct CalendarPickerCalendarRow: View {
    let calendar: CalendarInfo
    let isSelected: Bool
    let trailingAccessoryInset: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: calendar.color))
                    .frame(width: 7, height: 7)

                Text(calendar.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 13)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8 + trailingAccessoryInset)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityValue(isSelected ? "Shown" : "Hidden")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? 0.055 : 0))
    }
}

private struct CalendarPickerScrollObserver: NSViewRepresentable {
    @Binding var hasMoreContentBelow: Bool

    func makeNSView(context: Context) -> CalendarPickerScrollObserverView {
        CalendarPickerScrollObserverView { hasMoreContentBelow = $0 }
    }

    func updateNSView(_ nsView: CalendarPickerScrollObserverView, context: Context) {
        nsView.onChange = { hasMoreContentBelow = $0 }
        nsView.attachToEnclosingScrollView()
    }

    static func dismantleNSView(
        _ nsView: CalendarPickerScrollObserverView,
        coordinator: ()
    ) {
        nsView.stopObserving()
    }
}

private final class CalendarPickerScrollObserverView: NSView {
    var onChange: (Bool) -> Void

    private weak var scrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var lastValue: Bool?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToEnclosingScrollView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func attachToEnclosingScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            var ancestor = superview
            while let view = ancestor {
                if let enclosingScrollView = view as? NSScrollView {
                    startObserving(enclosingScrollView)
                    return
                }
                ancestor = view.superview
            }
        }
    }

    func stopObserving() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        boundsObserver = nil
        frameObserver = nil
        scrollView = nil
    }

    private func startObserving(_ scrollView: NSScrollView) {
        configureScroller(scrollView)

        guard self.scrollView !== scrollView else {
            updateVisibility()
            return
        }

        stopObserving()
        self.scrollView = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateVisibility()
        }

        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateVisibility()
            }
        }

        updateVisibility()
    }

    private func configureScroller(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = false

        if !(scrollView.verticalScroller is CalendarPickerScroller) {
            scrollView.verticalScroller = CalendarPickerScroller(frame: .zero)
        }

        scrollView.hasVerticalScroller = true
    }

    private func updateVisibility() {
        guard let scrollView, let documentView = scrollView.documentView else { return }

        let visibleRect = scrollView.documentVisibleRect
        let distanceFromBottom = documentView.isFlipped
            ? documentView.bounds.maxY - visibleRect.maxY
            : visibleRect.minY - documentView.bounds.minY
        let hasMoreContentBelow = distanceFromBottom > 1
        guard hasMoreContentBelow != lastValue else { return }
        lastValue = hasMoreContentBelow

        DispatchQueue.main.async { [weak self] in
            self?.onChange(hasMoreContentBelow)
        }
    }

    deinit {
        stopObserving()
    }
}

private final class CalendarPickerScroller: NSScroller {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        var knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else { return }

        let knobWidth: CGFloat = 4
        knobRect.origin.x = knobRect.midX - (knobWidth / 2)
        knobRect.size.width = knobWidth
        knobRect = knobRect.insetBy(dx: 0, dy: 2)

        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobWidth / 2,
            yRadius: knobWidth / 2
        ).fill()
    }
}

private struct CalendarSourceGroup: Identifiable {
    let sourceIdentifier: String
    let sourceTitle: String
    var calendars: [CalendarInfo]

    var id: String { sourceIdentifier }
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .settingsSectionSurface()
    }
}

private struct SettingsSectionSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.065), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private extension View {
    func settingsSectionSurface() -> some View {
        modifier(SettingsSectionSurface())
    }
}

private struct SettingsWindowBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, detail == nil ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.62)
    }
}

private struct SettingsValueMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            Text(label(selection))
                .lineLimit(1)
                .font(.callout.weight(.medium))
                .frame(minWidth: 112, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
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
