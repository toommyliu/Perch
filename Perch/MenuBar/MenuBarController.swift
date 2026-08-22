import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private static let dateIconStatusItemLength: CGFloat = 20
    private static let maximumAgendaStatusItemWidth: CGFloat = 200

    private let statusItem: NSStatusItem
    private let calendarProvider: CalendarEventProviding
    private let reminderProvider: ReminderEventProviding?
    private let permissionController: CalendarPermissionController
    private let reminderPermissionController: ReminderPermissionController?
    private let settingsStore: SettingsStore
    private let settingsWindowController: SettingsWindowController
    private let labelFormatter = MenuBarLabelFormatter()
    private let menuBuilder = MenuBuilder()
    private let eventOpenURLBuilder = CalendarEventOpenURLBuilder()
    private let meetingLaunchURLBuilder = MeetingLaunchURLBuilder()
    private lazy var refreshCoalescer = CalendarRefreshCoalescer { [weak self] in
        await self?.refreshCalendarData()
    }
    #if DEBUG
    private let dateIconDebugSettings: DateIconDebugSettings
    #endif

    private var allEvents: [CalendarEvent] = []
    private var allReminders: [CalendarReminder] = []
    private var accessState: CalendarAccessState = .unknown
    private var reminderAccessState: ReminderAccessState = .unknown
    private var accessStateCancellable: AnyCancellable?
    private var reminderAccessStateCancellable: AnyCancellable?
    private var lastRefreshFailed = false
    private var lastFetchedLookAheadDays: Int?
    private var lastFetchedShowReminders: Bool?
    private var presentedMenu: NSMenu?
    private var statusItemPresentation: StatusItemPresentation?
    private var isTrayMenuOpen = false
    private var presentsSettingsAfterMenuCloses = false

    var onTrayMenuWillOpen: (() -> Void)?
    var onTrayMenuDidClose: (() -> Void)?

    #if DEBUG
    init(
        calendarProvider: CalendarEventProviding,
        permissionController: CalendarPermissionController,
        reminderProvider: ReminderEventProviding? = nil,
        reminderPermissionController: ReminderPermissionController? = nil,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController,
        dateIconDebugSettings: DateIconDebugSettings
    ) {
        self.calendarProvider = calendarProvider
        self.permissionController = permissionController
        self.reminderProvider = reminderProvider
        self.reminderPermissionController = reminderPermissionController
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        self.dateIconDebugSettings = dateIconDebugSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        finishInit()
    }
    #else
    init(
        calendarProvider: CalendarEventProviding,
        permissionController: CalendarPermissionController,
        reminderProvider: ReminderEventProviding? = nil,
        reminderPermissionController: ReminderPermissionController? = nil,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.calendarProvider = calendarProvider
        self.permissionController = permissionController
        self.reminderProvider = reminderProvider
        self.reminderPermissionController = reminderPermissionController
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        finishInit()
    }
    #endif

    private func finishInit() {
        configureStatusItem()
        settingsWindowController.onReturnToMenu = { [weak self] in
            self?.showAgendaMenu()
        }
        settingsWindowController.onSettingsChanged = { [weak self] in
            guard let self else { return }
            let settings = settingsStore.settings
            let lookAheadChanged = lastFetchedLookAheadDays.map {
                $0 != settings.lookAheadDays
            } ?? false
            let remindersVisibilityChanged = lastFetchedShowReminders.map {
                $0 != settings.showReminders
            } ?? false
            syncPresentation()
            if lookAheadChanged || remindersVisibilityChanged {
                refresh()
            }
        }
        accessState = permissionController.refreshStatus()
        reminderAccessState = reminderPermissionController?.refreshStatus() ?? .unknown
        observeAccessStateChanges()
        observeReminderAccessStateChanges()
        syncPresentation()
    }

    private func observeAccessStateChanges() {
        accessStateCancellable = permissionController.$accessState
            .removeDuplicates()
            .sink { [weak self] newAccessState in
                guard let self, accessState != newAccessState else { return }

                let readabilityChanged = accessState.isSufficientForReadingEvents
                    != newAccessState.isSufficientForReadingEvents
                accessState = newAccessState
                syncPresentation()

                if readabilityChanged {
                    refresh()
                }
            }
    }

    private func observeReminderAccessStateChanges() {
        guard let reminderPermissionController else { return }

        reminderAccessStateCancellable = reminderPermissionController.$accessState
            .removeDuplicates()
            .sink { [weak self] newAccessState in
                guard let self, reminderAccessState != newAccessState else { return }

                let readabilityChanged = reminderAccessState.isSufficientForReadingReminders
                    != newAccessState.isSufficientForReadingReminders
                reminderAccessState = newAccessState
                if !newAccessState.isSufficientForReadingReminders {
                    allReminders = []
                    syncPresentation()
                }

                if readabilityChanged, settingsStore.settings.showReminders {
                    refresh()
                }
            }
    }

    func refresh() {
        refreshCoalescer.requestRefresh()
    }

    func refreshStatusItem() {
        updateStatusItem()
    }

    func toggleTrayVisibility() {
        if settingsWindowController.isPresented {
            settingsWindowController.dismiss()
            return
        }

        if isTrayMenuOpen {
            presentedMenu?.cancelTracking()
            return
        }
        showAgendaMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            PerchLog.presentation.fault("Status item setup failed: reason=buttonUnavailable")
            return
        }
        button.imagePosition = .imageLeading
        button.toolTip = defaultStatusItemToolTip
        button.title = ""
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        if settingsWindowController.isPresented {
            let opensContextMenu = NSApp.currentEvent?.type == .rightMouseUp
            settingsWindowController.dismiss { [weak self] in
                if opensContextMenu {
                    self?.showContextMenu()
                } else {
                    self?.showAgendaMenu()
                }
            }
            return
        }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            showAgendaMenu()
        }
    }

    private func showAgendaMenu() {
        guard !isTrayMenuOpen else { return }
        present(menu: makeAgendaMenu())
    }

    private func present(menu: NSMenu) {
        guard let button = statusItem.button else { return }
        menu.delegate = self
        presentedMenu = menu
        statusItem.menu = menu
        button.performClick(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Calendars", action: #selector(refreshFromContextMenu), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = .command
        refreshItem.target = self
        menu.addItem(refreshItem)
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Perch Completely", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        present(menu: menu)
    }

    @objc private func refreshFromContextMenu() {
        refresh()
    }

    private func refreshCalendarData() async {
        accessState = permissionController.refreshStatus()
        reminderAccessState = reminderPermissionController?.refreshStatus() ?? .unknown
        guard accessState.isSufficientForReadingEvents else {
            allEvents = []
            allReminders = []
            lastRefreshFailed = false
            syncPresentation()
            return
        }

        let now = Date()
        let startDate = Calendar.current.startOfDay(for: now)
        let settings = settingsStore.settings
        let lookAheadDays = settings.lookAheadDays
        lastFetchedLookAheadDays = lookAheadDays
        lastFetchedShowReminders = settings.showReminders
        let endDate = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: startDate)
            ?? now.addingTimeInterval(TimeInterval(lookAheadDays * 24 * 60 * 60))
        allReminders = []
        do {
            allEvents = try await calendarProvider.events(
                from: startDate,
                to: endDate,
                calendarIdentifiers: nil
            )
        } catch {
            if !lastRefreshFailed {
                let error = error as NSError
                PerchLog.calendar.error(
                    """
                    Event refresh failed: \
                    domain=\(error.domain, privacy: .public) \
                    code=\(error.code) \
                    lookAheadDays=\(lookAheadDays) \
                    error=\(error.localizedDescription, privacy: .private)
                    """
                )
            }
            lastRefreshFailed = true
            syncPresentation()
            return
        }

        if settings.showReminders,
           reminderAccessState.isSufficientForReadingReminders,
           let reminderProvider
        {
            allReminders = await reminderProvider.reminders(from: startDate, to: endDate)
        }

        if lastRefreshFailed {
            PerchLog.calendar.notice(
                """
                Event refresh recovered: \
                eventCount=\(self.allEvents.count) \
                reminderCount=\(self.allReminders.count) \
                lookAheadDays=\(lookAheadDays)
                """
            )
        }
        lastRefreshFailed = false
        syncPresentation()
    }

    private func syncPresentation() {
        updateStatusItem()
    }

    private func makeAgendaMenu() -> NSMenu {
        let settings = settingsStore.settings
        let snapshot = menuBuilder.snapshot(
            accessState: accessState,
            events: allEvents,
            reminders: allReminders,
            globalShortcut: settings.globalShortcut,
            showEventColors: settings.showEventColors,
            showAllDayEvents: settings.showAllDayEvents,
            showReminders: settings.showReminders,
            selectedCalendarIdentifiers: settings.selectedCalendarIdentifiers,
            displayMode: settings.displayMode
        )
        let menu = menuBuilder.makeMenu(from: snapshot, target: self)
        if lastRefreshFailed {
            let warning = NSMenuItem(title: "Calendar data may be out of date", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Warning")
            menu.insertItem(warning, at: min(2, menu.items.count))
        }
        menu.delegate = self
        return menu
    }

    private func updateStatusItem() {
        guard statusItem.button != nil else { return }
        #if DEBUG
        if dateIconDebugSettings.isOverrideEnabled {
            setStatusItemPresentation(.dateIcon(day: dateIconDebugSettings.day, options: dateIconDebugSettings.renderOptions))
            return
        }
        #endif

        switch labelFormatter.labelContent(
            events: allEvents,
            reminders: allReminders,
            settings: settingsStore.settings
        ) {
        case let .dateIcon(day):
            #if DEBUG
            setStatusItemPresentation(.dateIcon(day: day, options: .defaultValue))
            #else
            setStatusItemPresentation(.dateIcon(day: day))
            #endif
        case let .event(title, relativeText, color):
            setStatusItemPresentation(.event(title: title, relativeText: relativeText, color: color))
        case let .reminder(title, relativeText):
            setStatusItemPresentation(.reminder(title: title, relativeText: relativeText))
        }
    }

    private func setStatusItemPresentation(_ presentation: StatusItemPresentation) {
        guard presentation != statusItemPresentation, let button = statusItem.button else { return }
        statusItemPresentation = presentation
        switch presentation {
        #if DEBUG
        case let .dateIcon(day, options):
            statusItem.length = Self.dateIconStatusItemLength
            button.imagePosition = .imageOnly
            button.title = ""
            button.image = MenuIconRenderer.dateIcon(day: day, options: options)
            button.toolTip = defaultStatusItemToolTip
        #else
        case let .dateIcon(day):
            statusItem.length = Self.dateIconStatusItemLength
            button.imagePosition = .imageOnly
            button.title = ""
            button.image = MenuIconRenderer.dateIcon(day: day)
            button.toolTip = defaultStatusItemToolTip
        #endif
        case let .event(title, relativeText, color):
            setAgendaStatusItem(
                title: title,
                relativeText: relativeText,
                image: color.map { MenuIconRenderer.colorBar(color: $0) },
                button: button
            )
        case let .reminder(title, relativeText):
            setAgendaStatusItem(
                title: title,
                relativeText: relativeText,
                image: NSImage(systemSymbolName: "circle", accessibilityDescription: "Reminder"),
                button: button
            )
        }
    }

    private func setAgendaStatusItem(
        title: String,
        relativeText: String,
        image: NSImage?,
        button: NSStatusBarButton
    ) {
        statusItem.length = NSStatusItem.variableLength
        button.imagePosition = .imageLeading
        button.image = image

        let leadingText = image == nil ? "" : " "
        button.title = "\(leadingText)\(relativeText)"
        button.toolTip = title

        guard let widthMeasurer = MenuBarStatusItemWidthMeasurer(button: button) else { return }
        button.title = MenuBarLabelWidthLimiter.fit(
            title: title,
            relativeText: relativeText,
            leadingText: leadingText,
            maximumWidth: Self.maximumAgendaStatusItemWidth
        ) { candidate in
            widthMeasurer.width(for: candidate)
        }
    }

    private var defaultStatusItemToolTip: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Perch"
    }

    @objc func closeTrayMenuFromMenuItem() {
        presentedMenu?.cancelTracking()
    }

    @objc func requestCalendarAccess() {
        Task { @MainActor in
            _ = await permissionController.requestFullAccess()
        }
    }

    @objc func openCalendarPrivacySettings() {
        permissionController.openPrivacySettings()
    }

    @objc func openCalendarApp() {
        openCalendarAppFallback()
    }

    @objc func openRemindersApp() {
        openApplication(bundleIdentifier: "com.apple.reminders", displayName: "Reminders")
    }

    @objc func openCalendarEvent(_ sender: NSMenuItem) {
        guard case let .openEvent(eventIdentifier, startDate)? = sender.representedObject as? CalendarMenuAction,
              let url = eventOpenURLBuilder.url(eventIdentifier: eventIdentifier, startDate: startDate),
              NSWorkspace.shared.open(url)
        else {
            openCalendarAppFallback()
            return
        }
    }

    @objc func joinMeetingFromMenu(_ sender: NSMenuItem) {
        guard case let .joinMeeting(link)? = sender.representedObject as? CalendarMenuAction else { return }
        openMeeting(link)
    }

    @objc func copyMeetingLink(_ sender: NSMenuItem) {
        guard case let .copyMeetingLink(url)? = sender.representedObject as? CalendarMenuAction else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func openMeeting(_ link: MeetingLink) {
        let url = meetingLaunchURLBuilder.launchURL(for: link)
        if !NSWorkspace.shared.open(url) {
            PerchLog.actions.error(
                """
                Meeting launch failed: \
                provider=\(link.provider.rawValue, privacy: .public) \
                scheme=\(url.scheme ?? "none", privacy: .public)
                """
            )
        }
    }

    private func openCalendarAppFallback() {
        openApplication(bundleIdentifier: "com.apple.iCal", displayName: "Calendar")
    }

    private func openApplication(bundleIdentifier: String, displayName: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            PerchLog.actions.error("\(displayName, privacy: .public) launch failed: reason=applicationNotFound")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            guard let error else { return }
            let nsError = error as NSError
            PerchLog.actions.error(
                """
                \(displayName, privacy: .public) launch failed: \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code) \
                error=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
    }

    @objc func openSettings() {
        guard !isTrayMenuOpen else {
            presentsSettingsAfterMenuCloses = true
            return
        }

        settingsWindowController.present(anchoredTo: statusItem.button)
    }

    @objc func performSettingsMenuAction() {
        openSettings()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        updateTrayOpenState(true, menu: menu)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        updateTrayOpenState(false, menu: menu)
    }

    private nonisolated func updateTrayOpenState(_ isOpen: Bool, menu: NSMenu) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                applyTrayOpenState(isOpen, menu: menu)
            }
        } else {
            Task { @MainActor in
                applyTrayOpenState(isOpen, menu: menu)
            }
        }
    }

    private func applyTrayOpenState(_ isOpen: Bool, menu: NSMenu) {
        if !isOpen, presentedMenu === menu {
            if statusItem.menu === menu {
                statusItem.menu = nil
            }
            presentedMenu = nil
        }

        isTrayMenuOpen = isOpen
        if isOpen { onTrayMenuWillOpen?() } else { onTrayMenuDidClose?() }

        guard !isOpen, presentsSettingsAfterMenuCloses else { return }
        presentsSettingsAfterMenuCloses = false
        DispatchQueue.main.async { [weak self] in
            guard let self, !isTrayMenuOpen else { return }
            settingsWindowController.present(anchoredTo: statusItem.button)
        }
    }
}

private enum StatusItemPresentation: Equatable {
    #if DEBUG
    case dateIcon(day: Int, options: DateIconRenderOptions)
    #else
    case dateIcon(day: Int)
    #endif
    case event(title: String, relativeText: String, color: NSColor?)
    case reminder(title: String, relativeText: String)

    static func == (lhs: StatusItemPresentation, rhs: StatusItemPresentation) -> Bool {
        switch (lhs, rhs) {
        #if DEBUG
        case let (.dateIcon(lhsDay, lhsOptions), .dateIcon(rhsDay, rhsOptions)):
            return lhsDay == rhsDay && lhsOptions == rhsOptions
        #else
        case let (.dateIcon(lhsDay), .dateIcon(rhsDay)):
            return lhsDay == rhsDay
        #endif
        case let (.event(lhsTitle, lhsRelativeText, lhsColor), .event(rhsTitle, rhsRelativeText, rhsColor)):
            let colorsMatch: Bool
            switch (lhsColor, rhsColor) {
            case let (lhs?, rhs?): colorsMatch = lhs.isEqual(rhs)
            case (nil, nil): colorsMatch = true
            default: colorsMatch = false
            }
            return lhsTitle == rhsTitle && lhsRelativeText == rhsRelativeText && colorsMatch
        case let (.reminder(lhsTitle, lhsRelativeText), .reminder(rhsTitle, rhsRelativeText)):
            return lhsTitle == rhsTitle && lhsRelativeText == rhsRelativeText
        default:
            return false
        }
    }
}
