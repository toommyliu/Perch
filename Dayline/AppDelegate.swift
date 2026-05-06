import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var refreshCoordinator: CalendarRefreshCoordinator?
    private var globalHotKeyController: GlobalHotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DaylineLog.info("Application did finish launching")
        NSApp.setActivationPolicy(.accessory)

        let settingsStore = SettingsStore()
        let calendarProvider = EventKitCalendarProvider()
        let permissionController = CalendarPermissionController(permissionProvider: calendarProvider)
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            permissionController: permissionController
        )
        let menuBarController = MenuBarController(
            calendarProvider: calendarProvider,
            permissionController: permissionController,
            settingsStore: settingsStore,
            settingsWindowController: settingsWindowController
        )

        let refreshCoordinator = CalendarRefreshCoordinator {
            menuBarController.refresh()
        }

        self.menuBarController = menuBarController
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
        DaylineLog.info("Application setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaylineLog.info("Application will terminate")
        refreshCoordinator?.stop()
    }
}
