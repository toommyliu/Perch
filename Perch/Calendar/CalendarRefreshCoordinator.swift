import AppKit
import EventKit
import Foundation

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
