import AppKit

/// Reconciles fetched calendar events with the persistent meeting-reminder panel.
@MainActor
final class UpcomingMeetingNotificationCoordinator {
    private let schedule: UpcomingMeetingNotificationSchedule
    private let now: () -> Date
    private let isEnabled: () -> Bool
    private let selectedCalendarIdentifiers: () -> Set<String>?
    private let canReadEvents: () -> Bool
    private let openMeeting: @MainActor (MeetingLink) -> Void
    private let windowController: UpcomingMeetingNotificationWindowController

    private var events: [CalendarEvent] = []
    private var state = UpcomingMeetingNotificationState()
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, observer: NSObjectProtocol)] = []

    init(
        schedule: UpcomingMeetingNotificationSchedule = UpcomingMeetingNotificationSchedule(),
        now: @escaping () -> Date = Date.init,
        isEnabled: @escaping () -> Bool,
        selectedCalendarIdentifiers: @escaping () -> Set<String>?,
        canReadEvents: @escaping () -> Bool,
        openMeeting: (@MainActor (MeetingLink) -> Void)? = nil,
        windowController: UpcomingMeetingNotificationWindowController? = nil
    ) {
        self.schedule = schedule
        self.now = now
        self.isEnabled = isEnabled
        self.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        self.canReadEvents = canReadEvents
        self.openMeeting = openMeeting ?? { MeetingLauncher().open($0) }
        self.windowController = windowController ?? UpcomingMeetingNotificationWindowController()
    }

    func start() {
        stop()

        let notificationCenter = NotificationCenter.default
        observe(.NSSystemClockDidChange, center: notificationCenter)
        observe(.NSCalendarDayChanged, center: notificationCenter)
        observe(NSApplication.didChangeScreenParametersNotification, center: notificationCenter)
        observe(UserDefaults.didChangeNotification, center: notificationCenter)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
        reconcile()
    }

    func update(events: [CalendarEvent]) {
        self.events = events
        reconcile()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        for observer in observers {
            observer.center.removeObserver(observer.observer)
        }
        observers.removeAll()

        state.resetPresentation()
        windowController.dismiss()
    }

    private func reconcile() {
        timer?.invalidate()
        timer = nil

        let currentDate = now()
        let notificationsAreEnabled = isEnabled() && canReadEvents()
        let selectedIdentifiers = selectedCalendarIdentifiers()
        let event = state.eventToPresent(
            from: events,
            schedule: schedule,
            selectedCalendarIdentifiers: selectedIdentifiers,
            isEnabled: notificationsAreEnabled,
            now: currentDate
        )

        if let event {
            let occurrence = MeetingNotificationOccurrence(event: event)
            windowController.present(
                event: event,
                onJoin: { [weak self] in
                    self?.joinMeeting(for: occurrence)
                },
                onDismiss: { [weak self] in
                    self?.dismissNotification(for: occurrence)
                }
            )
        } else {
            windowController.dismiss()
        }

        guard notificationsAreEnabled,
              let nextDate = schedule.nextTransitionDate(
                  from: events,
                  selectedCalendarIdentifiers: selectedIdentifiers,
                  excluding: state.excludedOccurrences,
                  now: currentDate
              )
        else {
            return
        }

        scheduleTimer(at: nextDate)
    }

    private func joinMeeting(for occurrence: MeetingNotificationOccurrence) {
        guard occurrence == state.presentedOccurrence,
              let meetingLink = events.first(where: {
                  MeetingNotificationOccurrence(event: $0) == occurrence
              })?.meetingLink
        else {
            return
        }

        state.dismissPresented()
        openMeeting(meetingLink)
        reconcile()
    }

    private func dismissNotification(for occurrence: MeetingNotificationOccurrence) {
        guard occurrence == state.presentedOccurrence else { return }
        state.dismissPresented()
        reconcile()
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

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.windowController.reposition()
                self?.reconcile()
            }
        }
        observers.append((center, observer))
    }
}
