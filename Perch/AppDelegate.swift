import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var refreshCoordinator: CalendarRefreshCoordinator?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let usesDemoData = arguments.contains("--demo-data")
        let usesUITestHost = arguments.contains("--ui-testing")
        NSApp.setActivationPolicy(usesUITestHost ? .regular : .accessory)
        let userDefaults = usesDemoData
            ? UserDefaults(suiteName: "com.app.perch.demo") ?? .standard
            : .standard
        #else
        NSApp.setActivationPolicy(.accessory)
        let userDefaults = UserDefaults.standard
        #endif
        let settingsStore = SettingsStore(userDefaults: userDefaults)
        #if DEBUG
        let calendarProvider: CalendarProviding = usesDemoData
            ? DemoCalendarProvider()
            : EventKitCalendarProvider()
        #else
        let calendarProvider = EventKitCalendarProvider()
        #endif
        let permissionController = CalendarPermissionController(permissionProvider: calendarProvider)
        let loginItemManager = LoginItemManager()
        #if DEBUG
        let dateIconDebugSettings = DateIconDebugSettings()
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            dateIconDebugSettings: dateIconDebugSettings
        )
        let menuBarController = MenuBarController(
            calendarProvider: calendarProvider,
            permissionController: permissionController,
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
            loginItemManager: loginItemManager
        )
        let menuBarController = MenuBarController(
            calendarProvider: calendarProvider,
            permissionController: permissionController,
            settingsStore: settingsStore,
            settingsWindowController: settingsWindowController
        )
        #endif

        let refreshCoordinator = CalendarRefreshCoordinator {
            menuBarController.refresh()
        }

        self.menuBarController = menuBarController
        self.settingsWindowController = settingsWindowController
        self.refreshCoordinator = refreshCoordinator
        let globalHotKeyController = GlobalHotKeyController(initialShortcut: settingsStore.settings.globalShortcut) { [weak menuBarController] in
            menuBarController?.toggleTrayVisibility()
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
        refreshCoordinator?.stop()
    }
}
