import AppKit
import SwiftUI

final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseWindowShortcut(event) {
            performClose(nil)
            return true
        }

        if Self.isSelectAllShortcut(event),
           let fieldEditor = firstResponder as? NSTextView
        {
            fieldEditor.selectAll(nil)
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

    private static func isSelectAllShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "a"
        else {
            return false
        }

        let significantFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return significantFlags == .command
    }
}

final class SettingsWindowController: NSWindowController {
    private static let minimumContentHeight: CGFloat = 200
    private static let maximumContentHeight: CGFloat = 520
    private static let selectedPaneDefaultsKey = "SettingsWindowSelectedPane"
    private static let toolbarIdentifier = NSToolbar.Identifier("PerchSettingsToolbar")

    var onSettingsChanged: (() -> Void)?
    var onShortcutChangeRequested: ((GlobalShortcut) -> HotKeyRegistrationResult)?

    private let settingsStore: SettingsStore
    private let permissionController: CalendarPermissionController
    private let loginItemManager: LoginItemManaging
    private var viewModel: SettingsViewModel?
    private var lastSizedPane: SettingsPane?

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

        let selectedPane = Self.restoredPane
        let window = Self.makeWindow(height: 360, title: selectedPane.title)

        super.init(window: window)

        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            dateIconDebugSettings: dateIconDebugSettings,
            selectedPane: selectedPane,
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
        window.contentView = NSHostingView(rootView: SettingsView(
            model: viewModel,
            onContentHeightChange: { [weak self] height in
                self?.resizeWindow(toContentHeight: height)
            }
        ))
        configureToolbar(selectedPane: selectedPane)
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

        let selectedPane = Self.restoredPane
        let window = Self.makeWindow(height: 300, title: selectedPane.title)

        super.init(window: window)

        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            selectedPane: selectedPane,
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
        window.contentView = NSHostingView(rootView: SettingsView(
            model: viewModel,
            onContentHeightChange: { [weak self] height in
                self?.resizeWindow(toContentHeight: height)
            }
        ))
        configureToolbar(selectedPane: selectedPane)
    }
    #endif

    private static var restoredPane: SettingsPane {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedPaneDefaultsKey) else {
            return .general
        }

        return SettingsPane(rawValue: rawValue) ?? .general
    }

    private static func makeWindow(height: CGFloat, title: String) -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.contentWidth, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.autorecalculatesKeyViewLoop = true
        return window
    }

    private func resizeWindow(toContentHeight requestedHeight: CGFloat) {
        guard let window else {
            return
        }

        let targetHeight = min(
            max(requestedHeight, Self.minimumContentHeight),
            Self.maximumContentHeight
        )
        let currentContentHeight = window.contentRect(forFrameRect: window.frame).height
        let heightDelta = targetHeight - currentContentHeight
        let selectedPane = viewModel?.selectedPane
        let shouldAnimate = window.isVisible
            && lastSizedPane != nil
            && lastSizedPane != selectedPane
        lastSizedPane = selectedPane
        guard abs(heightDelta) > 0.5 else {
            return
        }

        var targetFrame = window.frame
        targetFrame.origin.y -= heightDelta
        targetFrame.size.height += heightDelta
        window.setFrame(targetFrame, display: true, animate: shouldAnimate)
    }

    private func configureToolbar(selectedPane: SettingsPane) {
        guard let window else {
            return
        }

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = selectedPane.toolbarItemIdentifier

        window.toolbar = toolbar
        window.toolbarStyle = .preference
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(toolbarItemIdentifier: sender.itemIdentifier) else {
            return
        }

        viewModel?.selectedPane = pane
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        UserDefaults.standard.set(pane.rawValue, forKey: Self.selectedPaneDefaultsKey)
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

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(toolbarItemIdentifier: itemIdentifier) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = pane.title
        item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
}

private extension SettingsPane {
    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("PerchSettings.\(rawValue)")
    }

    init?(toolbarItemIdentifier: NSToolbarItem.Identifier) {
        let prefix = "PerchSettings."
        guard toolbarItemIdentifier.rawValue.hasPrefix(prefix) else {
            return nil
        }

        self.init(rawValue: String(toolbarItemIdentifier.rawValue.dropFirst(prefix.count)))
    }
}
