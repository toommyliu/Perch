import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var refreshCoordinator: CalendarRefreshCoordinator?
    private var globalHotKeyController: GlobalHotKeyController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerchLog.info("Application did finish launching")
        NSApp.setActivationPolicy(.accessory)

        let settingsStore = SettingsStore()
        let calendarProvider = EventKitCalendarProvider()
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

        // While an NSMenu is tracking, AppKit can postpone Carbon hotkey delivery until
        // after the menu closes. Disable Carbon while open and let the menu's own hidden
        // key equivalent handle the close press immediately.
        menuBarController.onTrayMenuWillOpen = { [weak globalHotKeyController] in
            globalHotKeyController?.setEnabled(false)
        }
        menuBarController.onTrayMenuDidClose = { [weak globalHotKeyController] in
            globalHotKeyController?.setEnabled(true)
        }
        self.globalHotKeyController = globalHotKeyController

        refreshCoordinator.start()
        menuBarController.refresh()
        PerchLog.info("Application setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        PerchLog.info("Application will terminate")
        settingsWindowController?.closeBeforeTermination()
        refreshCoordinator?.stop()
    }
}
