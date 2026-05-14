import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private static let dateIconStatusItemLength: CGFloat = 20

    private let statusItem: NSStatusItem
    private let calendarProvider: CalendarEventProviding
    private let permissionController: CalendarPermissionController
    private let settingsStore: SettingsStore
    private let settingsWindowController: SettingsWindowController
    private let labelFormatter = MenuBarLabelFormatter()
    private let menuBuilder = MenuBuilder()
    private let eventOpenURLBuilder = CalendarEventOpenURLBuilder()
    private let zoomMeetingLaunchURLBuilder = ZoomMeetingLaunchURLBuilder()
    private lazy var refreshCoalescer = CalendarRefreshCoalescer { [weak self] in
        await self?.refreshCalendarData()
    }
    #if DEBUG
    private let dateIconDebugSettings: DateIconDebugSettings
    #endif
    private var events: [CalendarEvent] = []
    private var statusItemPresentation: StatusItemPresentation?
    private var isTrayMenuOpen = false
    var onTrayMenuWillOpen: (() -> Void)?
    var onTrayMenuDidClose: (() -> Void)?

    #if DEBUG
    init(
        calendarProvider: CalendarEventProviding,
        permissionController: CalendarPermissionController,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController,
        dateIconDebugSettings: DateIconDebugSettings
    ) {
        self.calendarProvider = calendarProvider
        self.permissionController = permissionController
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        self.dateIconDebugSettings = dateIconDebugSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        finishInit()
    }
    #else
    init(
        calendarProvider: CalendarEventProviding,
        permissionController: CalendarPermissionController,
        settingsStore: SettingsStore,
        settingsWindowController: SettingsWindowController
    ) {
        self.calendarProvider = calendarProvider
        self.permissionController = permissionController
        self.settingsStore = settingsStore
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        finishInit()
    }
    #endif

    private func finishInit() {
        PerchLog.info("MenuBarController initialized")

        settingsWindowController.onSettingsChanged = { [weak self] in
            Task { @MainActor in
                PerchLog.info("Settings changed; refreshing calendar data")
                self?.refresh()
            }
        }
        configureStatusItem()
        updateMenu(accessState: permissionController.refreshStatus())
        updateStatusItem()
    }

    func refresh() {
        refreshCoalescer.requestRefresh()
    }

    func refreshStatusItem() {
        updateStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            PerchLog.error("Status item has no button")
            return
        }

        button.imagePosition = .imageLeading
        button.toolTip = "Perch"
        button.title = ""
        PerchLog.info("Status item configured")
    }

    private func refreshCalendarData() async {
        let accessState = permissionController.refreshStatus()
        PerchLog.info("Refresh started with access state: \(String(describing: accessState))")

        guard accessState.isSufficientForReadingEvents else {
            events = []
            updateStatusItem()
            updateMenu(accessState: accessState)
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let settings = settingsStore.settings
        let startDate = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: settings.lookAheadDays, to: startDate) ?? now.addingTimeInterval(7 * 24 * 60 * 60)

        do {
            events = try await calendarProvider.events(from: startDate, to: endDate)
            PerchLog.info("Fetched \(events.count) events")
        } catch {
            events = []
            PerchLog.error("Failed to fetch events: \(error.localizedDescription)")
        }

        updateStatusItem()
        updateMenu(accessState: accessState)
    }

    private func updateStatusItem() {
        guard statusItem.button != nil else {
            return
        }

        #if DEBUG
        if dateIconDebugSettings.isOverrideEnabled {
            setStatusItemPresentation(
                .dateIcon(day: dateIconDebugSettings.day, options: dateIconDebugSettings.renderOptions),
                logMessage: "Status item set to debug date icon for day \(dateIconDebugSettings.day)"
            )
            return
        }
        #endif

        let content = labelFormatter.labelContent(events: events, settings: settingsStore.settings)

        switch content {
        case let .dateIcon(day):
            #if DEBUG
            setStatusItemPresentation(.dateIcon(day: day, options: .defaultValue), logMessage: "Status item set to date icon for day \(day)")
            #else
            setStatusItemPresentation(.dateIcon(day: day), logMessage: "Status item set to date icon for day \(day)")
            #endif
        case let .event(title, relativeText, color):
            setStatusItemPresentation(
                .event(title: title, relativeText: relativeText, color: color),
                logMessage: "Status item set to event: \(title) · \(relativeText)"
            )
        }
    }

    private func setStatusItemPresentation(_ presentation: StatusItemPresentation, logMessage: String) {
        guard presentation != statusItemPresentation else {
            return
        }

        statusItemPresentation = presentation
        guard let button = statusItem.button else {
            return
        }

        switch presentation {
        #if DEBUG
        case let .dateIcon(day, options):
            setDateIcon(day: day, options: options, button: button)
        #else
        case let .dateIcon(day):
            setDateIcon(day: day, button: button)
        #endif
        case let .event(title, relativeText, color):
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.image = color.map { MenuIconRenderer.colorBar(color: $0) }
            button.title = "\(color == nil ? "" : " ")\(title) · \(relativeText)"
        }

        PerchLog.info(logMessage)
    }

    #if DEBUG
    private func setDateIcon(day: Int, options: DateIconRenderOptions, button: NSStatusBarButton) {
        statusItem.length = Self.dateIconStatusItemLength
        button.imagePosition = .imageOnly
        button.title = ""
        button.image = MenuIconRenderer.dateIcon(day: day, options: options)
    }
    #else
    private func setDateIcon(day: Int, button: NSStatusBarButton) {
        statusItem.length = Self.dateIconStatusItemLength
        button.imagePosition = .imageOnly
        button.title = ""
        button.image = MenuIconRenderer.dateIcon(day: day)
    }
    #endif

    private func updateMenu(accessState: CalendarAccessState) {
        let settings = settingsStore.settings
        let snapshot = menuBuilder.snapshot(
            accessState: accessState,
            events: events,
            globalShortcut: settings.globalShortcut,
            showEventColors: settings.showEventColors,
            showAllDayEvents: settings.showAllDayEvents
        )
        let menu = menuBuilder.makeMenu(from: snapshot, target: self)
        menu.delegate = self
        statusItem.menu = menu
        PerchLog.info("Menu updated with \(snapshot.sections.count) sections and access state: \(String(describing: accessState))")
    }

    func toggleTrayVisibility() {
        if isTrayMenuOpen {
            PerchLog.info("Closing tray menu from global hotkey")
            statusItem.menu?.cancelTracking()
            return
        }

        guard let button = statusItem.button else {
            PerchLog.error("Cannot open tray menu because status item has no button")
            return
        }

        PerchLog.info("Opening tray menu from global hotkey")
        button.performClick(nil)
    }

    @objc func closeTrayMenuFromMenuItem() {
        PerchLog.info("Closing tray menu from menu key equivalent")
        statusItem.menu?.cancelTracking()
    }

    @objc func requestCalendarAccess() {
        PerchLog.info("Calendar access requested from menu")
        Task { @MainActor in
            _ = await self.permissionController.requestFullAccess()
            self.refresh()
        }
    }

    @objc func openCalendarPrivacySettings() {
        PerchLog.info("Opening Calendar privacy settings")
        permissionController.openPrivacySettings()
    }

    @objc func openCalendarApp() {
        PerchLog.info("Opening Apple Calendar")
        openCalendarAppFallback()
    }

    @objc func openCalendarEvent(_ sender: NSMenuItem) {
        guard case let .openEvent(eventIdentifier, startDate)? = sender.representedObject as? CalendarMenuAction else {
            PerchLog.error("Open event menu item missing event action")
            openCalendarAppFallback()
            return
        }

        guard let url = eventOpenURLBuilder.url(eventIdentifier: eventIdentifier, startDate: startDate) else {
            PerchLog.error("Could not build Calendar event URL")
            openCalendarAppFallback()
            return
        }

        PerchLog.info("Opening Apple Calendar event")
        if !NSWorkspace.shared.open(url) {
            PerchLog.error("Could not open Calendar event URL")
            openCalendarAppFallback()
        }
    }

    @objc func joinZoomMeeting(_ sender: NSMenuItem) {
        guard case let .joinZoomMeeting(url)? = sender.representedObject as? CalendarMenuAction else {
            PerchLog.error("Join Zoom menu item missing Zoom action")
            return
        }

        let launchURL = zoomMeetingLaunchURLBuilder.launchURL(for: url)
        PerchLog.info("Opening Zoom meeting")
        if !NSWorkspace.shared.open(launchURL) {
            PerchLog.error("Could not open Zoom meeting URL")
        }
    }

    private func openCalendarAppFallback() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            PerchLog.error("Could not resolve Apple Calendar bundle id")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @objc func openSettings() {
        PerchLog.info("Opening settings window")
        settingsWindowController.present()
    }

    @objc func quit() {
        PerchLog.info("Quit requested")
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        updateTrayMenuOpenState(true)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        updateTrayMenuOpenState(false)
    }

    private nonisolated func updateTrayMenuOpenState(_ isOpen: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                isTrayMenuOpen = isOpen
                if isOpen {
                    onTrayMenuWillOpen?()
                } else {
                    onTrayMenuDidClose?()
                }
            }
        } else {
            Task { @MainActor in
                isTrayMenuOpen = isOpen
                if isOpen {
                    onTrayMenuWillOpen?()
                } else {
                    onTrayMenuDidClose?()
                }
            }
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
            return lhsTitle == rhsTitle
                && lhsRelativeText == rhsRelativeText
                && colorsAreEqual(lhsColor, rhsColor)
        default:
            return false
        }
    }

    private static func colorsAreEqual(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}
