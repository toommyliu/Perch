import AppKit
import SwiftUI

final class SettingsWindow: NSPanel {
    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseShortcut(event) {
            requestClose()
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

    override func cancelOperation(_ sender: Any?) {
        requestClose()
    }

    private func requestClose() {
        if let onRequestClose {
            onRequestClose()
        } else {
            performClose(nil)
        }
    }

    private static func isCloseShortcut(_ event: NSEvent) -> Bool {
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

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let minimumContentHeight: CGFloat = 260
    private static let maximumContentHeight: CGFloat = 680
    private static let screenEdgeInset: CGFloat = 8

    var onSettingsChanged: (() -> Void)?
    var onShortcutChangeRequested: ((GlobalShortcut) -> HotKeyRegistrationResult)?
    var onReturnToMenu: (() -> Void)?

    var isPresented: Bool {
        loadedWindow?.isVisible == true
    }

    var hasLoadedSettingsResources: Bool {
        loadedWindow != nil
    }

    private let settingsStore: SettingsStore
    private let permissionController: CalendarPermissionController
    private let calendarProvider: CalendarEventProviding
    private let loginItemManager: LoginItemManaging
    #if DEBUG
    private let dateIconDebugSettings: DateIconDebugSettings
    #endif
    private var settingsWindow: SettingsWindow?
    private var viewModel: SettingsViewModel?
    private weak var anchorView: NSView?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var requestedContentHeight: CGFloat = 520
    private var presentationState: PresentationState = .hidden
    private var transitionGeneration = 0
    private var dismissalCompletions: [() -> Void] = []

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
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
        self.dateIconDebugSettings = dateIconDebugSettings
        super.init(window: nil)
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
        self.calendarProvider = calendarProvider
        self.loginItemManager = loginItemManager
        super.init(window: nil)
    }
    #endif

    private func loadSettingsWindow() -> SettingsWindow {
        if let settingsWindow {
            return settingsWindow
        }

        let window = Self.makeWindow()
        #if DEBUG
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            dateIconDebugSettings: dateIconDebugSettings,
            onShortcutChangeRequested: shortcutChangeHandler,
            onAccessRequestCompleted: accessRequestCompletionHandler,
            onChange: settingsChangeHandler
        )
        #else
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            loginItemManager: loginItemManager,
            onShortcutChangeRequested: shortcutChangeHandler,
            onAccessRequestCompleted: accessRequestCompletionHandler,
            onChange: settingsChangeHandler
        )
        #endif
        configure(window: window, viewModel: viewModel)
        self.window = window
        settingsWindow = window
        return window
    }

    private var loadedWindow: SettingsWindow? {
        settingsWindow
    }

    private var shortcutChangeHandler: (GlobalShortcut) -> HotKeyRegistrationResult {
        { [weak self] shortcut in
            self?.onShortcutChangeRequested?(shortcut) ?? .failure(OSStatus(-1))
        }
    }

    private var accessRequestCompletionHandler: () -> Void {
        { [weak self] in
            self?.restoreAfterAccessRequest()
        }
    }

    private var settingsChangeHandler: () -> Void {
        { [weak self] in
            self?.onSettingsChanged?()
        }
    }

    private static func makeWindow() -> SettingsWindow {
        let window = SettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.contentWidth,
                height: 520
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        // The native window animation races the NSMenu dismissal. The controller
        // owns a coordinated transition instead.
        window.animationBehavior = .none
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.autorecalculatesKeyViewLoop = true
        return window
    }

    private func configure(window: SettingsWindow, viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        window.onRequestClose = { [weak self] in
            self?.dismiss()
        }
        window.contentView = NSHostingView(rootView: SettingsView(
            model: viewModel,
            onReturnToMenu: { [weak self] in
                self?.returnToMenu()
            },
            onContentHeightChange: { [weak self] height in
                DispatchQueue.main.async { [weak self] in
                    self?.resizeWindow(toContentHeight: height)
                }
            }
        ))
    }

    func present(anchoredTo anchorView: NSView? = nil) {
        if let anchorView {
            self.anchorView = anchorView
        }

        permissionController.refreshStatus()
        viewModel?.refreshLaunchAtLoginState()
        viewModel?.refreshAvailableCalendars()

        let window = loadSettingsWindow()
        guard presentationState == .hidden else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        presentationState = .presenting
        resizeWindow(toContentHeight: requestedContentHeight)
        positionWindow()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        configureOuterScrollView()
        (self.anchorView as? NSStatusBarButton)?.highlight(true)
        startOutsideClickMonitoring()

        // SwiftUI reports its measured content height on the next main-loop turn.
        // Keep the panel invisible until that first layout settles so the header
        // and its back button never move after becoming visible.
        window.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.animatePresentation(generation: generation)
            }
        }
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        if let completion {
            dismissalCompletions.append(completion)
        }

        guard let window = loadedWindow,
              presentationState != .hidden,
              window.isVisible
        else {
            discardWindow()
            runDismissalCompletions()
            return
        }
        guard presentationState != .dismissing else { return }

        transitionGeneration += 1
        let generation = transitionGeneration
        presentationState = .dismissing
        stopOutsideClickMonitoring()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated else {
            finishDismissal(generation: generation)
            return
        }

        let endFrame = SettingsPanelTransition.dismissedFrame(
            from: window.frame,
            reduceMotion: reduceMotion
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsPanelTransition.dismissalDuration(reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDismissal(generation: generation)
            }
        }
    }

    func closeBeforeTermination() {
        transitionGeneration += 1
        presentationState = .hidden
        dismissalCompletions.removeAll()
        (anchorView as? NSStatusBarButton)?.highlight(false)
        discardWindow()
    }

    private func returnToMenu() {
        dismiss { [weak self] in
            self?.onReturnToMenu?()
        }
    }

    private func restoreAfterAccessRequest() {
        present(anchoredTo: anchorView)
    }

    private func animatePresentation(generation: Int) {
        guard generation == transitionGeneration,
              presentationState == .presenting,
              let window = loadedWindow,
              window.isVisible
        else {
            return
        }

        resizeWindow(toContentHeight: requestedContentHeight)
        positionWindow()

        let finalFrame = window.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(
            SettingsPanelTransition.presentedStartFrame(
                from: finalFrame,
                reduceMotion: reduceMotion
            ),
            display: true
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsPanelTransition.presentationDuration(reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == transitionGeneration,
                      presentationState == .presenting,
                      let window = self.loadedWindow
                else {
                    return
                }

                presentationState = .presented
                window.alphaValue = 1
                window.setFrame(finalFrame, display: true)
            }
        }
    }

    private func finishDismissal(generation: Int) {
        guard generation == transitionGeneration,
              presentationState == .dismissing,
              let window = loadedWindow
        else {
            return
        }

        window.orderOut(nil)
        window.alphaValue = 1
        (anchorView as? NSStatusBarButton)?.highlight(false)
        presentationState = .hidden
        discardWindow()
        runDismissalCompletions()
    }

    private func runDismissalCompletions() {
        let completions = dismissalCompletions
        dismissalCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func resizeWindow(toContentHeight requestedHeight: CGFloat) {
        requestedContentHeight = requestedHeight
        guard let window = loadedWindow else { return }

        // A legacy-style vertical scroller reserves a gutter when the Developer
        // disclosure makes this view scrollable, which narrows and reflows every
        // settings section. Keep it overlay-only and out of layout at each content
        // height update because SwiftUI may recreate or reconfigure the scroll view.
        configureOuterScrollView()

        guard presentationState != .presented,
              presentationState != .dismissing
        else {
            return
        }

        let targetHeight = min(
            max(requestedHeight, Self.minimumContentHeight),
            maximumAvailableContentHeight
        )
        guard abs(window.frame.height - targetHeight) > 0.5 else { return }

        let targetSize = NSSize(width: SettingsView.contentWidth, height: targetHeight)
        if window.isVisible {
            window.setFrame(positionedFrame(for: targetSize), display: true)
        } else {
            window.setContentSize(targetSize)
        }
        configureOuterScrollView()
    }

    private var maximumAvailableContentHeight: CGFloat {
        let visibleHeight = anchorView?.window?.screen?.visibleFrame.height
            ?? loadedWindow?.screen?.visibleFrame.height
        guard let visibleHeight else { return Self.maximumContentHeight }
        return min(Self.maximumContentHeight, visibleHeight - (Self.screenEdgeInset * 2))
    }

    private func configureOuterScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let contentView = self?.loadedWindow?.contentView else { return }
            let outerScrollView = contentView.descendants(of: NSScrollView.self)
                .max { $0.frame.width < $1.frame.width }
            outerScrollView?.scrollerStyle = .overlay
            outerScrollView?.autohidesScrollers = true
            outerScrollView?.hasVerticalScroller = false
        }
    }

    private func positionWindow() {
        guard let window = loadedWindow else { return }
        window.setFrame(positionedFrame(for: window.frame.size), display: true)
    }

    private func positionedFrame(for panelSize: NSSize) -> NSRect {
        guard let window = loadedWindow else {
            return NSRect(origin: .zero, size: panelSize)
        }
        if let anchorView,
           let anchorWindow = anchorView.window
        {
            let anchorRect = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            let visibleFrame = anchorWindow.screen?.visibleFrame
                ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
            if let visibleFrame {
                return SettingsPanelPlacement.frame(
                    anchorRect: anchorRect,
                    panelSize: panelSize,
                    visibleFrame: visibleFrame
                )
            }
        }

        if window.isVisible {
            return NSRect(
                x: window.frame.midX - (panelSize.width / 2),
                y: window.frame.maxY - panelSize.height,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        return NSRect(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.midY - (panelSize.height / 2),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func startOutsideClickMonitoring() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        #endif
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, let window = self.loadedWindow else { return event }
            if Self.shouldDismiss(for: event.window, panelWindow: window) {
                self.dismiss()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func discardWindow() {
        guard let window = loadedWindow else { return }
        stopOutsideClickMonitoring()
        window.onRequestClose = nil
        window.contentView = nil
        viewModel = nil
        window.close()
        self.window = nil
        settingsWindow = nil
    }

    static func shouldDismiss(for eventWindow: NSWindow?, panelWindow: NSWindow) -> Bool {
        var candidate = eventWindow
        while let window = candidate {
            if window === panelWindow {
                return false
            }
            candidate = window.parent
        }
        return true
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }
}

private enum PresentationState {
    case hidden
    case presenting
    case presented
    case dismissing
}

enum SettingsPanelTransition {
    private static let verticalOffset: CGFloat = 8
    private static let standardPresentationDuration: TimeInterval = 0.20
    private static let standardDismissalDuration: TimeInterval = 0.16
    private static let reducedMotionDuration: TimeInterval = 0.10

    static func presentationDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotionDuration : standardPresentationDuration
    }

    static func dismissalDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotionDuration : standardDismissalDuration
    }

    static func presentedStartFrame(from finalFrame: NSRect, reduceMotion: Bool) -> NSRect {
        offsetFrame(finalFrame, reduceMotion: reduceMotion)
    }

    static func dismissedFrame(from presentedFrame: NSRect, reduceMotion: Bool) -> NSRect {
        offsetFrame(presentedFrame, reduceMotion: reduceMotion)
    }

    private static func offsetFrame(_ frame: NSRect, reduceMotion: Bool) -> NSRect {
        guard !reduceMotion else { return frame }
        return frame.offsetBy(dx: 0, dy: verticalOffset)
    }
}

enum SettingsPanelPlacement {
    private static let edgeInset: CGFloat = 8
    private static let anchorGap: CGFloat = 6

    static func frame(
        anchorRect: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let proposedX = anchorRect.midX - (panelSize.width / 2)
        let minimumX = visibleFrame.minX + edgeInset
        let maximumX = visibleFrame.maxX - panelSize.width - edgeInset
        let x = min(max(proposedX, minimumX), max(minimumX, maximumX))

        let proposedY = anchorRect.minY - panelSize.height - anchorGap
        let minimumY = visibleFrame.minY + edgeInset
        let maximumY = visibleFrame.maxY - panelSize.height - edgeInset
        let y = min(max(proposedY, minimumY), max(minimumY, maximumY))

        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}

private extension NSView {
    func descendants<View: NSView>(of type: View.Type) -> [View] {
        subviews.flatMap { subview in
            let match = (subview as? View).map { [$0] } ?? []
            return match + subview.descendants(of: type)
        }
    }
}
