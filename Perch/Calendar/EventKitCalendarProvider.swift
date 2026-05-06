import AppKit
import EventKit
import Foundation

final class EventKitCalendarProvider: CalendarProviding {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        PerchLog.info("EventKitCalendarProvider initialized")
    }

    func authorizationState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestFullAccess() async -> CalendarAccessState {
        let granted: Bool

        do {
            granted = try await eventStore.requestFullAccessToEvents()
        } catch {
            PerchLog.error("Calendar full access request failed: \(error.localizedDescription)")
            return authorizationState()
        }

        PerchLog.info("Calendar full access request completed: \(granted)")
        return granted ? .fullAccess : authorizationState()
    }

    func events(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)

        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? "\(event.title ?? "")-\(event.startDate.timeIntervalSince1970)",
                    title: event.title?.isEmpty == false ? event.title : "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title,
                    calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .controlAccentColor
                )
            }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }

                if $0.endDate != $1.endDate {
                    return $0.endDate < $1.endDate
                }

                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}
