import AppKit
import EventKit
import Foundation

final class CalendarRefreshCoordinator {
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let refresh: () -> Void

    init(refresh: @escaping () -> Void) {
        self.refresh = refresh
    }

    func start() {
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }

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
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        observers.append(observer)
    }

    deinit {
        stop()
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
