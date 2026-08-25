import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var refreshCoordinator: CalendarRefreshCoordinator?
    private var meetingNotificationCoordinator: UpcomingMeetingNotificationCoordinator?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let usesDemoData = arguments.contains("--demo-data")
        let usesUITestHost = arguments.contains("--ui-testing")
        let showsMeetingNotificationPreview = usesDemoData
            && arguments.contains("--show-meeting-notification")
        NSApp.setActivationPolicy(usesUITestHost ? .regular : .accessory)
        let userDefaults = usesDemoData
            ? UserDefaults(suiteName: "com.app.perch.demo") ?? .standard
            : .standard
        #else
        let showsMeetingNotificationPreview = false
        NSApp.setActivationPolicy(.accessory)
        let userDefaults = UserDefaults.standard
        #endif
        let settingsStore = SettingsStore(userDefaults: userDefaults)
        #if DEBUG
        let calendarProvider: AgendaProviding = usesDemoData
            ? DemoCalendarProvider(
                showsMeetingNotificationPreview: showsMeetingNotificationPreview
            )
            : EventKitCalendarProvider()
        #else
        let calendarProvider = EventKitCalendarProvider()
        #endif
        let permissionController = CalendarPermissionController(permissionProvider: calendarProvider)
        let reminderPermissionController = ReminderPermissionController(permissionProvider: calendarProvider)
        let loginItemManager = LoginItemManager()
        #if DEBUG
        let dateIconDebugSettings = DateIconDebugSettings()
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            reminderPermissionController: reminderPermissionController,
            dateIconDebugSettings: dateIconDebugSettings
        )
        let menuBarController = MenuBarController(
            calendarProvider: calendarProvider,
            permissionController: permissionController,
            reminderProvider: calendarProvider,
            reminderPermissionController: reminderPermissionController,
            settingsStore: settingsStore,
            settingsWindowController: settingsWindowController,
            dateIconDebugSettings: dateIconDebugSettings
        )
        dateIconDebugSettings.onChange = { [weak menuBarController] in
            menuBarController?.refreshStatusItem()
        }
        #else
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            reminderPermissionController: reminderPermissionController
        )
        let menuBarController = MenuBarController(
            calendarProvider: calendarProvider,
            permissionController: permissionController,
            reminderProvider: calendarProvider,
            reminderPermissionController: reminderPermissionController,
            settingsStore: settingsStore,
            settingsWindowController: settingsWindowController
        )
        #endif

        let refreshCoordinator = CalendarRefreshCoordinator {
            menuBarController.refresh()
        }
        let meetingNotificationCoordinator = UpcomingMeetingNotificationCoordinator(
            isEnabled: {
                settingsStore.settings.showMeetingNotifications
                    || showsMeetingNotificationPreview
            },
            selectedCalendarIdentifiers: {
                settingsStore.settings.selectedCalendarIdentifiers
            },
            canReadEvents: {
                permissionController.accessState.isSufficientForReadingEvents
            }
        )
        menuBarController.onCalendarEventsUpdated = { [weak meetingNotificationCoordinator] events in
            meetingNotificationCoordinator?.update(events: events)
        }

        self.menuBarController = menuBarController
        self.settingsWindowController = settingsWindowController
        self.refreshCoordinator = refreshCoordinator
        self.meetingNotificationCoordinator = meetingNotificationCoordinator
        let globalHotKeyController = GlobalHotKeyController(
            initialShortcut: settingsStore.settings.globalShortcut
        ) { [weak menuBarController, weak meetingNotificationCoordinator] in
            // A visible reminder gets the shortcut before the status menu so keyboard
            // users can act on it without the panel stealing focus when it appears.
            if meetingNotificationCoordinator?.focusPresentedNotification() != true {
                menuBarController?.toggleTrayVisibility()
            }
        }
        settingsWindowController.onShortcutChangeRequested = { [weak globalHotKeyController] shortcut in
            globalHotKeyController?.applyShortcut(shortcut) ?? .failure(OSStatus(-1))
        }

        // Carbon hotkeys are postponed while NSMenu tracks. The menu carries the same
        // shortcut as a hidden key equivalent so a second press closes it immediately.
        menuBarController.onTrayMenuWillOpen = { [weak globalHotKeyController] in
            globalHotKeyController?.setEnabled(false)
        }
        menuBarController.onTrayMenuDidClose = { [weak globalHotKeyController] in
            globalHotKeyController?.setEnabled(true)
        }

        self.globalHotKeyController = globalHotKeyController

        meetingNotificationCoordinator.start()
        refreshCoordinator.start()
        menuBarController.refresh()

        #if DEBUG
        if usesDemoData, arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                menuBarController.openSettings()
            }
        }
        if usesDemoData, arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                menuBarController.toggleTrayVisibility()
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsWindowController?.closeBeforeTermination()
        meetingNotificationCoordinator?.stop()
        refreshCoordinator?.stop()
    }
}
