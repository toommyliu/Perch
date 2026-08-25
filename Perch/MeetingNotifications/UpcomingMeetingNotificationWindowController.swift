import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class UpcomingMeetingNotificationWindowController {
    static let contentSize = NSSize(width: 428, height: 86)
    private static let screenMargin: CGFloat = 16
    private static let entranceOffset: CGFloat = 6
    private static let exitOffset: CGFloat = 4
    private static let entranceDuration: TimeInterval = 0.18
    private static let exitDuration: TimeInterval = 0.12
    private static let reducedMotionDuration: TimeInterval = 0.08

    private let panel: NSPanel
    private let hostingController: NSHostingController<AnyView>
    private let keyboardFocus = MeetingNotificationKeyboardFocus()
    private var pendingEntrance: DispatchWorkItem?
    private var transitionGeneration = 0
    private var isPresenting = false
    private var isDismissing = false

    init() {
        hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        panel = MeetingNotificationPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Meeting reminder"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentMinSize = Self.contentSize
        panel.contentMaxSize = Self.contentSize
        panel.contentViewController = hostingController
    }

    func present(
        event: CalendarEvent,
        onJoin: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        hostingController.rootView = AnyView(
            UpcomingMeetingNotificationView(
                event: event,
                keyboardFocus: keyboardFocus,
                onJoin: onJoin,
                onDismiss: onDismiss
            )
        )
        panel.setContentSize(Self.contentSize)

        let finalFrame = panelFrame()
        if panel.isVisible, isPresenting {
            return
        }

        transitionGeneration += 1
        pendingEntrance?.cancel()
        pendingEntrance = nil
        isDismissing = false

        guard !panel.isVisible else {
            panel.alphaValue = 1
            panel.setFrame(finalFrame, display: true)
            return
        }

        let generation = transitionGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isPresenting = true
        let startFrame = reduceMotion
            ? finalFrame
            : finalFrame.offsetBy(dx: 0, dy: Self.entranceOffset)
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()

        let entrance = DispatchWorkItem { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.pendingEntrance = nil

            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion
                    ? Self.reducedMotionDuration
                    : Self.entranceDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
                self.panel.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.transitionGeneration == generation else { return }
                    self.isPresenting = false
                }
            }
        }
        pendingEntrance = entrance
        DispatchQueue.main.async(execute: entrance)
    }

    func dismiss() {
        guard panel.isVisible, !isDismissing else { return }

        transitionGeneration += 1
        let generation = transitionGeneration
        pendingEntrance?.cancel()
        pendingEntrance = nil
        isPresenting = false
        isDismissing = true

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let exitFrame = reduceMotion
            ? panel.frame
            : panel.frame.offsetBy(dx: 0, dy: Self.exitOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion
                ? Self.reducedMotionDuration
                : Self.exitDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(exitFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.hostingController.rootView = AnyView(EmptyView())
                self.isDismissing = false
            }
        }
    }

    func reposition() {
        guard panel.isVisible else { return }
        panel.setFrame(panelFrame(), display: true)
    }

    func focusForKeyboardInteraction() -> Bool {
        guard panel.isVisible, !isDismissing else { return false }
        panel.makeKey()
        guard panel.isKeyWindow else { return false }
        keyboardFocus.focusJoinButton()
        return true
    }

    private func panelFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: panel.frame.origin, size: Self.contentSize)
        }

        let visibleFrame = screen.visibleFrame
        let x = max(
            visibleFrame.minX + Self.screenMargin,
            visibleFrame.maxX - Self.contentSize.width - Self.screenMargin
        )
        let y = max(
            visibleFrame.minY + Self.screenMargin,
            visibleFrame.maxY - Self.contentSize.height - Self.screenMargin
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: Self.contentSize)
    }
}

// Borderless windows cannot normally become key, but explicit shortcut focus must
// work without changing this panel's nonactivating behavior when it first appears.
private final class MeetingNotificationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class MeetingNotificationKeyboardFocus: ObservableObject {
    @Published private(set) var requestID = 0

    func focusJoinButton() {
        requestID += 1
    }
}

private struct UpcomingMeetingNotificationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedAction: FocusedAction?

    let event: CalendarEvent
    @ObservedObject var keyboardFocus: MeetingNotificationKeyboardFocus
    let onJoin: () -> Void
    let onDismiss: () -> Void

    private enum FocusedAction {
        case join
        case dismiss
    }

    private var meetingProvider: MeetingProvider {
        event.meetingLink?.provider ?? .other
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(event.title)

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 6) {
                            Text(countdownText(at: context.date))
                                .foregroundStyle(.primary)
                                .fontWeight(.medium)

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(timeRangeText)
                                .foregroundStyle(.primary.opacity(0.68))
                        }
                        .font(.system(size: 13, weight: .regular))
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onJoin) {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(
                                Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )

                        Text("Join \(meetingProvider.displayName)")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(MeetingJoinButtonStyle(isFocused: focusedAction == .join))
                .focusable()
                .focused($focusedAction, equals: .join)
                .keyboardShortcut(.defaultAction)
                .fixedSize()
                .help("Join \(meetingProvider.displayName)")
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .frame(width: 412, height: 70, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.07), radius: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(bannerBevel, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .offset(x: 10, y: 6)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        focusedAction == .dismiss ? Color.accentColor : surfaceRingColor,
                        lineWidth: focusedAction == .dismiss ? 2 : 0.5
                    )
                    .allowsHitTesting(false)
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .focusable()
            .focused($focusedAction, equals: .dismiss)
            .keyboardShortcut(.cancelAction)
            .help("Dismiss meeting reminder")
            .accessibilityLabel("Dismiss meeting reminder")
        }
        .frame(
            width: UpcomingMeetingNotificationWindowController.contentSize.width,
            height: UpcomingMeetingNotificationWindowController.contentSize.height,
            alignment: .topLeading
        )
        .onChange(of: keyboardFocus.requestID) {
            focusedAction = .join
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting reminder")
    }

    private var surfaceRingColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.14)
            : .black.opacity(0.1)
    }

    private var bannerBevel: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [.white.opacity(0.2), .white.opacity(0.14), .white.opacity(0.1)]
            : [.black.opacity(0.06), .black.opacity(0.08), .black.opacity(0.12)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var timeRangeText: String {
        let formatter = DateIntervalFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate, to: event.endDate)
    }

    private func countdownText(at date: Date) -> String {
        let secondsUntilStart = event.startDate.timeIntervalSince(date)
        if secondsUntilStart > 0 {
            return "in \(max(1, Int(ceil(secondsUntilStart / 60))))m"
        }

        let elapsedMinutes = Int(abs(secondsUntilStart) / 60)
        return elapsedMinutes == 0 ? "now" : "\(elapsedMinutes)m ago"
    }
}

private struct MeetingJoinButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        Color(nsColor: .controlBackgroundColor)
                            .shadow(
                                .inner(
                                    color: configuration.isPressed
                                        ? pressedInnerShadowColor
                                        : bevelHighlightColor,
                                    radius: configuration.isPressed ? 1.5 : 0.5,
                                    x: 0,
                                    y: configuration.isPressed ? 1 : 0.5
                                )
                            )
                    )
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0 : 0.06),
                        radius: 1,
                        y: 1
                    )
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0 : 0.04),
                        radius: 3,
                        y: 2
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor : surfaceRingColor,
                        lineWidth: isFocused ? 2 : 0.5
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }

    private var surfaceRingColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : .black.opacity(0.08)
    }

    private var bevelHighlightColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : .white.opacity(0.72)
    }

    private var pressedInnerShadowColor: Color {
        colorScheme == .dark
            ? .black.opacity(0.48)
            : .black.opacity(0.16)
    }
}
