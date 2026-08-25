import AppKit
import EventKit
import Foundation
import SwiftUI

final class CalendarRefreshCoordinator {
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, observer: NSObjectProtocol)] = []
    private let refresh: () -> Void
    private let now: () -> Date
    private let calendar: Calendar
    private let timerTolerance: TimeInterval

    init(
        calendar: Calendar = .current,
        timerTolerance: TimeInterval = CalendarRefreshSchedule.defaultTimerTolerance,
        now: @escaping () -> Date = Date.init,
        refresh: @escaping () -> Void
    ) {
        self.calendar = calendar
        self.timerTolerance = timerTolerance
        self.now = now
        self.refresh = refresh
    }

    func start() {
        stop()
        scheduleNextTimer(after: now())

        let notificationCenter = NotificationCenter.default
        observe(.EKEventStoreChanged, center: notificationCenter)
        observe(.NSSystemClockDidChange, center: notificationCenter)
        observe(.NSCalendarDayChanged, center: notificationCenter)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        for observer in observers {
            observer.center.removeObserver(observer.observer)
        }

        observers.removeAll()
    }

    private func scheduleNextTimer(after date: Date) {
        timer?.invalidate()

        let timer = Timer(fire: CalendarRefreshSchedule.nextRefreshDate(after: date, calendar: calendar), interval: 0, repeats: false) { [weak self] _ in
            self?.timerDidFire()
        }
        timer.tolerance = timerTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerDidFire() {
        refresh()
        scheduleNextTimer(after: now())
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.timerDidFire()
        }
        observers.append((center, observer))
    }

    deinit {
        stop()
    }
}

enum CalendarRefreshSchedule {
    static let defaultTimerTolerance: TimeInterval = 1

    static func nextRefreshDate(after date: Date, calendar: Calendar = .current) -> Date {
        guard let minuteInterval = calendar.dateInterval(of: .minute, for: date) else {
            return date.addingTimeInterval(60)
        }

        let nextMinute = minuteInterval.end
        guard nextMinute > date else {
            return date.addingTimeInterval(60)
        }

        return nextMinute
    }
}

@MainActor
final class CalendarRefreshCoalescer {
    private let refresh: () async -> Void
    private var isRefreshing = false
    private var needsFollowUpRefresh = false

    init(refresh: @escaping () async -> Void) {
        self.refresh = refresh
    }

    func requestRefresh() {
        if isRefreshing {
            needsFollowUpRefresh = true
            return
        }

        isRefreshing = true
        Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    private func runRefreshLoop() async {
        while true {
            needsFollowUpRefresh = false
            await refresh()

            guard needsFollowUpRefresh else {
                isRefreshing = false
                return
            }
        }
    }
}

struct UpcomingMeetingOccurrence: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let startDate: Date

    init(event: CalendarEvent) {
        eventIdentifier = event.id
        calendarIdentifier = event.calendarIdentifier
        startDate = event.startDate
    }
}

struct UpcomingMeetingNotificationSchedule {
    static let defaultLeadTime: TimeInterval = 5 * 60
    static let defaultPostStartDisplayDuration: TimeInterval = 5 * 60

    let leadTime: TimeInterval
    let postStartDisplayDuration: TimeInterval

    init(
        leadTime: TimeInterval = Self.defaultLeadTime,
        postStartDisplayDuration: TimeInterval = Self.defaultPostStartDisplayDuration
    ) {
        self.leadTime = max(0, leadTime)
        self.postStartDisplayDuration = max(0, postStartDisplayDuration)
    }

    func eventToPresent(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        dismissedOccurrences: Set<UpcomingMeetingOccurrence>,
        now: Date
    ) -> CalendarEvent? {
        eligibleEvents(
            from: events,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            dismissedOccurrences: dismissedOccurrences
        )
        .first { event in
            notificationDate(for: event) <= now && event.startDate > now
        }
    }

    func nextPresentationDate(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        dismissedOccurrences: Set<UpcomingMeetingOccurrence>,
        now: Date
    ) -> Date? {
        eligibleEvents(
            from: events,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            dismissedOccurrences: dismissedOccurrences
        )
        .lazy
        .filter { $0.startDate > now }
        .map(notificationDate(for:))
        .filter { $0 > now }
        .min()
    }

    func shouldKeepPresented(
        _ event: CalendarEvent,
        selectedCalendarIdentifiers: Set<String>?,
        now: Date
    ) -> Bool {
        isEligible(event, selectedCalendarIdentifiers: selectedCalendarIdentifiers)
            && now < expirationDate(for: event)
    }

    func notificationDate(for event: CalendarEvent) -> Date {
        event.startDate.addingTimeInterval(-leadTime)
    }

    func expirationDate(for event: CalendarEvent) -> Date {
        min(
            event.endDate,
            event.startDate.addingTimeInterval(postStartDisplayDuration)
        )
    }

    func shouldRetainDismissal(_ occurrence: UpcomingMeetingOccurrence, now: Date) -> Bool {
        occurrence.startDate.addingTimeInterval(postStartDisplayDuration) > now
    }

    private func eligibleEvents(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        dismissedOccurrences: Set<UpcomingMeetingOccurrence>
    ) -> [CalendarEvent] {
        events
            .filter { event in
                isEligible(event, selectedCalendarIdentifiers: selectedCalendarIdentifiers)
                    && !dismissedOccurrences.contains(UpcomingMeetingOccurrence(event: event))
            }
            .sorted(by: Self.isOrderedBefore)
    }

    private func isEligible(
        _ event: CalendarEvent,
        selectedCalendarIdentifiers: Set<String>?
    ) -> Bool {
        !event.isAllDay
            && event.meetingLink != nil
            && event.endDate > event.startDate
            && (selectedCalendarIdentifiers?.contains(event.calendarIdentifier) ?? true)
    }

    private static func isOrderedBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}

final class MeetingNotificationAgendaProvider: AgendaProviding {
    private let base: AgendaProviding
    private let didFetchEvents: @MainActor ([CalendarEvent]) -> Void

    init(
        base: AgendaProviding,
        didFetchEvents: @MainActor @escaping ([CalendarEvent]) -> Void
    ) {
        self.base = base
        self.didFetchEvents = didFetchEvents
    }

    func authorizationState() -> CalendarAccessState {
        base.authorizationState()
    }

    func requestFullAccess() async -> CalendarAccessState {
        await base.requestFullAccess()
    }

    func reminderAuthorizationState() -> ReminderAccessState {
        base.reminderAuthorizationState()
    }

    func requestFullReminderAccess() async -> ReminderAccessState {
        await base.requestFullReminderAccess()
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        try await base.availableCalendars()
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> [CalendarEvent] {
        let events = try await base.events(
            from: startDate,
            to: endDate,
            calendarIdentifiers: calendarIdentifiers
        )
        await didFetchEvents(events)
        return events
    }

    func reminders(from startDate: Date, to endDate: Date) async -> [CalendarReminder] {
        await base.reminders(from: startDate, to: endDate)
    }
}

@MainActor
final class UpcomingMeetingNotificationCoordinator {
    private let schedule: UpcomingMeetingNotificationSchedule
    private let now: () -> Date
    private let selectedCalendarIdentifiers: () -> Set<String>?
    private let canReadEvents: () -> Bool
    private let openMeeting: (MeetingLink) -> Void
    private let windowController = UpcomingMeetingNotificationWindowController()

    private var events: [CalendarEvent] = []
    private var dismissedOccurrences: Set<UpcomingMeetingOccurrence> = []
    private var presentedOccurrence: UpcomingMeetingOccurrence?
    private var presentedEvent: CalendarEvent?
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, observer: NSObjectProtocol)] = []

    init(
        userDefaults: UserDefaults,
        schedule: UpcomingMeetingNotificationSchedule = UpcomingMeetingNotificationSchedule(),
        now: @escaping () -> Date = Date.init,
        selectedCalendarIdentifiers: @escaping () -> Set<String>?,
        canReadEvents: @escaping () -> Bool,
        openMeeting: @escaping (MeetingLink) -> Void = UpcomingMeetingNotificationCoordinator.openMeeting
    ) {
        self.schedule = schedule
        self.now = now
        self.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        self.canReadEvents = canReadEvents
        self.openMeeting = openMeeting

        let notificationCenter = NotificationCenter.default
        observe(.EKEventStoreChanged, center: notificationCenter)
        observe(.NSSystemClockDidChange, center: notificationCenter)
        observe(.NSCalendarDayChanged, center: notificationCenter)
        observe(NSApplication.didChangeScreenParametersNotification, center: notificationCenter)
        observe(UserDefaults.didChangeNotification, center: notificationCenter, object: userDefaults)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
    }

    func update(events: [CalendarEvent]) {
        self.events = events
        reconcile()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        windowController.dismiss()
        presentedOccurrence = nil
        presentedEvent = nil

        for observer in observers {
            observer.center.removeObserver(observer.observer)
        }
        observers.removeAll()
    }

    private func reconcile() {
        timer?.invalidate()
        timer = nil

        let currentDate = now()
        dismissedOccurrences = Set(dismissedOccurrences.filter {
            schedule.shouldRetainDismissal($0, now: currentDate)
        })

        guard canReadEvents() else {
            clearPresentedNotification(markAsDismissed: false)
            return
        }

        let selectedIdentifiers = selectedCalendarIdentifiers()
        if let presentedOccurrence,
           let updatedEvent = events.first(where: {
               UpcomingMeetingOccurrence(event: $0) == presentedOccurrence
           }),
           schedule.shouldKeepPresented(
               updatedEvent,
               selectedCalendarIdentifiers: selectedIdentifiers,
               now: currentDate
           )
        {
            presentedEvent = updatedEvent
            showWindow(for: updatedEvent, occurrence: presentedOccurrence)
            scheduleTimer(at: schedule.expirationDate(for: updatedEvent))
            return
        }

        clearPresentedNotification(markAsDismissed: false)

        if let event = schedule.eventToPresent(
            from: events,
            selectedCalendarIdentifiers: selectedIdentifiers,
            dismissedOccurrences: dismissedOccurrences,
            now: currentDate
        ) {
            present(event)
            scheduleTimer(at: schedule.expirationDate(for: event))
            return
        }

        if let nextDate = schedule.nextPresentationDate(
            from: events,
            selectedCalendarIdentifiers: selectedIdentifiers,
            dismissedOccurrences: dismissedOccurrences,
            now: currentDate
        ) {
            scheduleTimer(at: nextDate)
        }
    }

    private func present(_ event: CalendarEvent) {
        let occurrence = UpcomingMeetingOccurrence(event: event)
        presentedOccurrence = occurrence
        presentedEvent = event
        showWindow(for: event, occurrence: occurrence)
    }

    private func showWindow(
        for event: CalendarEvent,
        occurrence: UpcomingMeetingOccurrence
    ) {
        windowController.present(
            event: event,
            onJoin: { [weak self] in
                self?.joinMeeting(for: occurrence)
            },
            onDismiss: { [weak self] in
                self?.dismissNotification(for: occurrence)
            }
        )
    }

    private func joinMeeting(for occurrence: UpcomingMeetingOccurrence) {
        guard occurrence == presentedOccurrence,
              let meetingLink = presentedEvent?.meetingLink
        else {
            return
        }

        clearPresentedNotification(markAsDismissed: true)
        openMeeting(meetingLink)
        reconcile()
    }

    private func dismissNotification(for occurrence: UpcomingMeetingOccurrence) {
        guard occurrence == presentedOccurrence else { return }
        clearPresentedNotification(markAsDismissed: true)
        reconcile()
    }

    private func clearPresentedNotification(markAsDismissed: Bool) {
        if markAsDismissed, let presentedOccurrence {
            dismissedOccurrences.insert(presentedOccurrence)
        }

        presentedOccurrence = nil
        presentedEvent = nil
        windowController.dismiss()
    }

    private func scheduleTimer(at date: Date) {
        guard date > now() else { return }

        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observe(
        _ name: Notification.Name,
        center: NotificationCenter,
        object: Any? = nil
    ) {
        let observer = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
        observers.append((center, observer))
    }

    private static func openMeeting(_ link: MeetingLink) {
        let url = MeetingLaunchURLBuilder().launchURL(for: link)
        if !NSWorkspace.shared.open(url) {
            PerchLog.actions.error(
                """
                Meeting notification launch failed: \
                provider=\(link.provider.rawValue, privacy: .public) \
                scheme=\(url.scheme ?? "none", privacy: .public)
                """
            )
        }
    }
}

@MainActor
private final class UpcomingMeetingNotificationWindowController {
    fileprivate static let contentSize = NSSize(width: 536, height: 112)
    private static let screenMargin: CGFloat = 16

    private let panel: NSPanel
    private let hostingController: NSHostingController<AnyView>

    init() {
        hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
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
        panel.animationBehavior = .alertPanel
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
                onJoin: onJoin,
                onDismiss: onDismiss
            )
        )
        panel.setContentSize(Self.contentSize)
        positionPanel()
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel.orderOut(nil)
        hostingController.rootView = AnyView(EmptyView())
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - panel.frame.width - Self.screenMargin,
                y: visibleFrame.maxY - panel.frame.height - Self.screenMargin
            )
        )
    }
}

private struct UpcomingMeetingNotificationView: View {
    let event: CalendarEvent
    let onJoin: () -> Void
    let onDismiss: () -> Void

    private var meetingProvider: MeetingProvider {
        event.meetingLink?.provider ?? .other
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(event.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 6) {
                            Text(timingText(at: context.date))
                                .foregroundStyle(.orange)

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(event.startDate, style: .time)
                            Text("–")
                            Text(event.endDate, style: .time)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }

                Spacer(minLength: 0)

                Button(action: onJoin) {
                    Label("Join \(meetingProvider.displayName)", systemImage: "video.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.leading, 28)
            .padding(.trailing, 16)
            .frame(width: 520, height: 96, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
            .shadow(radius: 13, y: 6)
            .offset(x: 12, y: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
            .accessibilityLabel("Dismiss meeting notification")
        }
        .frame(
            width: UpcomingMeetingNotificationWindowController.contentSize.width,
            height: UpcomingMeetingNotificationWindowController.contentSize.height,
            alignment: .topLeading
        )
    }

    private func timingText(at date: Date) -> String {
        let secondsUntilStart = event.startDate.timeIntervalSince(date)
        if secondsUntilStart > 90 {
            return "in \(Int(ceil(secondsUntilStart / 60)))m"
        }

        if secondsUntilStart > 0 {
            return "in \(max(1, Int(ceil(secondsUntilStart))))s"
        }

        let elapsedSeconds = abs(secondsUntilStart)
        if elapsedSeconds < 60 {
            return "now"
        }

        return "\(Int(elapsedSeconds / 60))m ago"
    }
}
