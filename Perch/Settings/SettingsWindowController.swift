import AppKit
import SwiftUI

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseWindowShortcut(event) {
            performClose(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private static func isCloseWindowShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "w"
        else {
            return false
        }

        let significantFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return significantFlags == .command
    }
}

final class SettingsWindowController: NSWindowController {
    var onSettingsChanged: (() -> Void)?
    var onShortcutChangeRequested: ((GlobalShortcut) -> HotKeyRegistrationResult)?

    private let settingsStore: SettingsStore
    private let permissionController: CalendarPermissionController
    private let loginItemManager: LoginItemManaging
    private var viewModel: SettingsViewModel?

    #if DEBUG
    init(
        settingsStore: SettingsStore,
        permissionController: CalendarPermissionController,
        calendarProvider: CalendarEventProviding,
        loginItemManager: LoginItemManaging,
        dateIconDebugSettings: DateIconDebugSettings
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.loginItemManager = loginItemManager

        let window = Self.makeWindow(height: 560)

        super.init(window: window)

        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            dateIconDebugSettings: dateIconDebugSettings,
            onShortcutChangeRequested: { [weak self] shortcut in
                self?.onShortcutChangeRequested?(shortcut) ?? .failure(OSStatus(-1))
            },
            onAccessRequestCompleted: { [weak self] in
                self?.restoreAfterAccessRequest()
            }
        ) { [weak self] in
            self?.onSettingsChanged?()
        }
        self.viewModel = viewModel
        window.contentView = NSHostingView(rootView: SettingsView(model: viewModel))
    }
    #else
    init(
        settingsStore: SettingsStore,
        permissionController: CalendarPermissionController,
        calendarProvider: CalendarEventProviding,
        loginItemManager: LoginItemManaging
    ) {
        self.settingsStore = settingsStore
        self.permissionController = permissionController
        self.loginItemManager = loginItemManager

        let window = Self.makeWindow(height: 460)

        super.init(window: window)

        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            onShortcutChangeRequested: { [weak self] shortcut in
                self?.onShortcutChangeRequested?(shortcut) ?? .failure(OSStatus(-1))
            },
            onAccessRequestCompleted: { [weak self] in
                self?.restoreAfterAccessRequest()
            }
        ) { [weak self] in
            self?.onSettingsChanged?()
        }
        self.viewModel = viewModel
        window.contentView = NSHostingView(rootView: SettingsView(model: viewModel))
    }
    #endif

    private static func makeWindow(height: CGFloat) -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        return window
    }

    @MainActor
    func present() {
        permissionController.refreshStatus()
        viewModel?.refreshLaunchAtLoginState()
        viewModel?.refreshAvailableCalendars()

        orderWindowFront()
    }

    @MainActor
    private func restoreAfterAccessRequest() {
        orderWindowFront()
    }

    @MainActor
    func closeBeforeTermination() {
        window?.close()
    }

    @MainActor
    private func orderWindowFront() {
        guard let window else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        if !window.isVisible {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        // Accessory apps can lose the first ordering race when opened from an NSMenu.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.level = .normal
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
