import AppKit
import EventKit
import Foundation

final class EventKitCalendarProvider: AgendaProviding {
    private let eventStore: EventStoreBox
    private let meetingLinkExtractor = MeetingLinkExtractor()
    private let queryQueue = DispatchQueue(
        label: "com.app.perch.eventkit-query",
        qos: .userInitiated
    )

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = EventStoreBox(eventStore)
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
            granted = try await eventStore.value.requestFullAccessToEvents()
        } catch {
            let error = error as NSError
            PerchLog.calendar.error(
                """
                Calendar access request failed: \
                domain=\(error.domain, privacy: .public) \
                code=\(error.code) \
                error=\(error.localizedDescription, privacy: .private)
                """
            )
            return authorizationState()
        }

        return granted ? .fullAccess : authorizationState()
    }

    func reminderAuthorizationState() -> ReminderAccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .fullAccess
        case .writeOnly:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    func requestFullReminderAccess() async -> ReminderAccessState {
        let granted: Bool

        do {
            granted = try await eventStore.value.requestFullAccessToReminders()
        } catch {
            let error = error as NSError
            PerchLog.calendar.error(
                """
                Reminders access request failed: \
                domain=\(error.domain, privacy: .public) \
                code=\(error.code) \
                error=\(error.localizedDescription, privacy: .private)
                """
            )
            return reminderAuthorizationState()
        }

        return granted ? .fullAccess : reminderAuthorizationState()
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        await withCheckedContinuation { continuation in
            queryQueue.async { [eventStore] in
                let calendars = eventStore.value.calendars(for: .event)
                    .map { calendar in
                        CalendarInfo(
                            id: calendar.calendarIdentifier,
                            title: calendar.title,
                            sourceTitle: calendar.source.title,
                            sourceIdentifier: calendar.source.sourceIdentifier,
                            color: NSColor(cgColor: calendar.cgColor) ?? .controlAccentColor
                        )
                    }
                    .sorted(by: Self.isOrderedBefore)
                continuation.resume(returning: calendars)
            }
        }
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> [CalendarEvent] {
        if calendarIdentifiers?.isEmpty == true {
            return []
        }

        return await withCheckedContinuation { continuation in
            queryQueue.async { [eventStore, meetingLinkExtractor] in
                let calendars = eventStore.value.calendars(for: .event)
                    .filter { calendar in
                        calendarIdentifiers?.contains(calendar.calendarIdentifier) ?? true
                    }
                let predicate = eventStore.value.predicateForEvents(
                    withStart: startDate,
                    end: endDate,
                    calendars: calendars
                )
                let events = eventStore.value.events(matching: predicate)
                    .filter { $0.status != .canceled }
                    .map { event in
                        CalendarEvent(
                            id: event.calendarItemIdentifier,
                            title: event.title?.isEmpty == false ? event.title : "Untitled",
                            startDate: event.startDate,
                            endDate: event.endDate,
                            isAllDay: event.isAllDay,
                            calendarTitle: event.calendar.title,
                            calendarColor: NSColor(cgColor: event.calendar.cgColor) ?? .controlAccentColor,
                            calendarIdentifier: event.calendar.calendarIdentifier,
                            meetingLink: meetingLinkExtractor.meetingLink(from: [
                                event.url?.absoluteString,
                                event.location,
                                event.notes
                            ]),
                            location: event.location
                        )
                    }
                    .sorted(by: Self.isEventOrderedBefore)
                continuation.resume(returning: events)
            }
        }
    }

    func reminders(from startDate: Date, to endDate: Date) async -> [CalendarReminder] {
        await withCheckedContinuation { continuation in
            queryQueue.async { [eventStore] in
                let calendars = eventStore.value.calendars(for: .reminder)
                let predicate = eventStore.value.predicateForIncompleteReminders(
                    withDueDateStarting: startDate,
                    ending: endDate,
                    calendars: calendars
                )
                eventStore.value.fetchReminders(matching: predicate) { reminders in
                    let reminders = (reminders ?? [])
                        .filter { !$0.isCompleted }
                        .compactMap { Self.calendarReminder(from: $0) }
                        .sorted(by: Self.isReminderOrderedBefore)
                    continuation.resume(returning: reminders)
                }
            }
        }
    }

    private static func isOrderedBefore(_ lhs: CalendarInfo, _ rhs: CalendarInfo) -> Bool {
        let sourceComparison = lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle)
        if sourceComparison != .orderedSame {
            return sourceComparison == .orderedAscending
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func isEventOrderedBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func calendarReminder(from reminder: EKReminder) -> CalendarReminder? {
        guard let components = reminder.dueDateComponents,
              let dueDate = reminderDate(from: components)
        else {
            return nil
        }

        return CalendarReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title?.isEmpty == false ? reminder.title : "Untitled",
            dueDate: dueDate,
            isAllDay: components.hour == nil && components.minute == nil && components.second == nil,
            listTitle: reminder.calendar.title,
            listIdentifier: reminder.calendar.calendarIdentifier
        )
    }

    private static func reminderDate(from components: DateComponents) -> Date? {
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? .current

        var normalizedComponents = components
        normalizedComponents.calendar = calendar
        normalizedComponents.timeZone = calendar.timeZone
        return calendar.date(from: normalizedComponents)
    }

    private static func isReminderOrderedBefore(_ lhs: CalendarReminder, _ rhs: CalendarReminder) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

}

// EventKit's synchronous query API is explicitly intended for dispatch queues, but
// EKEventStore predates Sendable annotations. Every query through this box is serialized
// by EventKitCalendarProvider.queryQueue.
private final class EventStoreBox: @unchecked Sendable {
    let value: EKEventStore

    init(_ value: EKEventStore) {
        self.value = value
    }
}
