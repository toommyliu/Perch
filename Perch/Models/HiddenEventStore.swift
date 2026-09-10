import Foundation

struct CalendarEventOccurrence: Codable, Hashable {
    let calendarIdentifier: String
    let eventIdentifier: String
    let startDate: Date

    init(event: CalendarEvent) {
        calendarIdentifier = event.calendarIdentifier
        eventIdentifier = event.id
        startDate = event.startDate
    }
}

enum HiddenEventScope: String, Codable {
    case bar
    case completely
}

struct HiddenCalendarEvent: Codable, Equatable {
    let occurrence: CalendarEventOccurrence
    let title: String
    let endDate: Date
    let scope: HiddenEventScope

    init(event: CalendarEvent, scope: HiddenEventScope = .completely) {
        occurrence = CalendarEventOccurrence(event: event)
        title = event.title
        endDate = event.endDate
        self.scope = scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurrence = try container.decode(CalendarEventOccurrence.self, forKey: .occurrence)
        title = try container.decode(String.self, forKey: .title)
        endDate = try container.decode(Date.self, forKey: .endDate)
        scope = try container.decodeIfPresent(HiddenEventScope.self, forKey: .scope) ?? .completely
    }
}

/// Stores individual occurrences separately from calendar preferences and keeps enough detail to restore unfetched events.
final class HiddenEventStore {
    private let userDefaults: UserDefaults
    private let storageKey = "HiddenCalendarEvents"
    private var records: [HiddenCalendarEvent]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        records = userDefaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([HiddenCalendarEvent].self, from: $0) } ?? []
    }

    func activeEvents(now: Date) -> [HiddenCalendarEvent] {
        records.filter { $0.endDate > now }
            .sorted { $0.occurrence.startDate < $1.occurrence.startDate }
    }

    func hiddenOccurrences(now: Date, scope: HiddenEventScope? = nil) -> Set<CalendarEventOccurrence> {
        Set(activeEvents(now: now).filter { scope == nil || $0.scope == scope }.map(\.occurrence))
    }

    func hide(_ event: CalendarEvent, scope: HiddenEventScope = .completely, now: Date) {
        guard event.endDate > now else { return }
        let record = HiddenCalendarEvent(event: event, scope: scope)
        save(records.filter { $0.endDate > now && $0.occurrence != record.occurrence } + [record])
    }

    func restore(_ occurrence: CalendarEventOccurrence, now: Date) {
        save(records.filter { $0.endDate > now && $0.occurrence != occurrence })
    }

    /// Refresh matching records before expiring them, since an event's end time may have been extended.
    func reconcile(events: [CalendarEvent], now: Date) {
        let eventsByOccurrence = Dictionary(
            events.map { (CalendarEventOccurrence(event: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        save(records.map { record in
            eventsByOccurrence[record.occurrence].map { HiddenCalendarEvent(event: $0, scope: record.scope) } ?? record
        }.filter { $0.endDate > now })
    }

    private func save(_ updated: [HiddenCalendarEvent]) {
        guard updated != records,
              let data = try? JSONEncoder().encode(updated)
        else { return }
        userDefaults.set(data, forKey: storageKey)
        records = updated
    }
}
