import Foundation

enum CalendarEventVisibility {
    static func upcomingEvents(
        from events: [CalendarEvent],
        includeAllDayEvents: Bool,
        selectedCalendarIdentifiers: Set<String>? = nil,
        now: Date
    ) -> [CalendarEvent] {
        events
            .filter { event in
                event.endDate >= now
                    && (includeAllDayEvents || !event.isAllDay)
                    && (selectedCalendarIdentifiers?.contains(event.calendarIdentifier) ?? true)
            }
            .sorted(by: isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum AgendaItem: Equatable {
    case event(CalendarEvent)
    case reminder(CalendarReminder)

    var date: Date {
        switch self {
        case let .event(event): event.startDate
        case let .reminder(reminder): reminder.dueDate
        }
    }

    var title: String {
        switch self {
        case let .event(event): event.title
        case let .reminder(reminder): reminder.title
        }
    }

    private var secondaryDate: Date {
        switch self {
        case let .event(event): event.endDate
        case let .reminder(reminder): reminder.dueDate
        }
    }

    private var typeOrder: Int {
        switch self {
        case .event: 0
        case .reminder: 1
        }
    }

    static func isOrderedBefore(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }

        if lhs.secondaryDate != rhs.secondaryDate {
            return lhs.secondaryDate < rhs.secondaryDate
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.typeOrder < rhs.typeOrder
    }
}

enum AgendaItemVisibility {
    static func visibleItems(
        events: [CalendarEvent],
        reminders: [CalendarReminder],
        includeAllDayEvents: Bool,
        includeReminders: Bool,
        selectedCalendarIdentifiers: Set<String>?,
        now: Date,
        calendar: Calendar
    ) -> [AgendaItem] {
        let visibleEvents = CalendarEventVisibility.upcomingEvents(
            from: events,
            includeAllDayEvents: includeAllDayEvents,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            now: now
        )
        let startOfToday = calendar.startOfDay(for: now)
        let visibleReminders = includeReminders
            ? reminders.filter { $0.dueDate >= startOfToday }
            : []

        return (
            visibleEvents.map(AgendaItem.event)
                + visibleReminders.map(AgendaItem.reminder)
        ).sorted(by: AgendaItem.isOrderedBefore)
    }

    static func shouldPrioritize(
        _ item: AgendaItem,
        displayMode: MenuBarDisplayMode,
        now: Date
    ) -> Bool {
        guard displayMode != .never else {
            return false
        }

        switch item {
        case let .event(event):
            if event.startDate <= now && event.endDate >= now {
                return true
            }

            guard let leadTime = displayMode.leadTime else {
                return true
            }
            return event.startDate <= now.addingTimeInterval(leadTime)

        case let .reminder(reminder):
            if reminder.dueDate <= now {
                return true
            }

            guard let leadTime = displayMode.leadTime else {
                return true
            }
            return reminder.dueDate <= now.addingTimeInterval(leadTime)
        }
    }
}
