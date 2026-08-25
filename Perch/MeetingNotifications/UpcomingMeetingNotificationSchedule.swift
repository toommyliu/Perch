import Foundation

struct MeetingNotificationOccurrence: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let startDate: Date

    init(event: CalendarEvent) {
        eventIdentifier = event.id
        calendarIdentifier = event.calendarIdentifier
        startDate = event.startDate
    }
}

/// Calculates meeting-reminder eligibility and the dates when the decision can change.
struct UpcomingMeetingNotificationSchedule {
    static let defaultLeadTime: TimeInterval = 5 * 60
    static let defaultPostStartDisplayDuration: TimeInterval = 5 * 60
    static let calendarFetchLookback = defaultPostStartDisplayDuration
    static let calendarFetchLookahead = defaultLeadTime

    let leadTime: TimeInterval
    let postStartDisplayDuration: TimeInterval

    init(
        leadTime: TimeInterval = Self.defaultLeadTime,
        postStartDisplayDuration: TimeInterval = Self.defaultPostStartDisplayDuration
    ) {
        self.leadTime = max(0, leadTime)
        self.postStartDisplayDuration = max(0, postStartDisplayDuration)
    }

    func activeEvents(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        excluding excludedOccurrences: Set<MeetingNotificationOccurrence>,
        now: Date
    ) -> [CalendarEvent] {
        eligibleEvents(
            from: events,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            excluding: excludedOccurrences
        )
        .filter { event in
            notificationDate(for: event) <= now && now < expirationDate(for: event)
        }
    }

    /// Prefers the meeting that starts soonest, then the most recently started meeting.
    func preferredEvent(from activeEvents: [CalendarEvent], now: Date) -> CalendarEvent? {
        if let upcomingEvent = activeEvents
            .filter({ $0.startDate > now })
            .sorted(by: Self.isOrderedBefore)
            .first
        {
            return upcomingEvent
        }

        return activeEvents
            .filter { $0.startDate <= now }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate > rhs.startDate
                }
                return Self.isOrderedBefore(lhs, rhs)
            }
            .first
    }

    func nextTransitionDate(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        excluding excludedOccurrences: Set<MeetingNotificationOccurrence>,
        now: Date
    ) -> Date? {
        eligibleEvents(
            from: events,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            excluding: excludedOccurrences
        )
        .flatMap { event in
            [
                notificationDate(for: event),
                event.startDate,
                expirationDate(for: event)
            ]
        }
        .filter { $0 > now }
        .min()
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

    func shouldRetain(_ occurrence: MeetingNotificationOccurrence, now: Date) -> Bool {
        occurrence.startDate.addingTimeInterval(postStartDisplayDuration) > now
    }

    private func eligibleEvents(
        from events: [CalendarEvent],
        selectedCalendarIdentifiers: Set<String>?,
        excluding excludedOccurrences: Set<MeetingNotificationOccurrence>
    ) -> [CalendarEvent] {
        events.filter { event in
            !event.isAllDay
                && event.meetingLink != nil
                && event.endDate > event.startDate
                && (selectedCalendarIdentifiers?.contains(event.calendarIdentifier) ?? true)
                && !excludedOccurrences.contains(MeetingNotificationOccurrence(event: event))
        }
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

/// Tracks explicit dismissals separately from cards replaced by a later reminder.
struct UpcomingMeetingNotificationState {
    private(set) var presentedOccurrence: MeetingNotificationOccurrence?
    private(set) var dismissedOccurrences: Set<MeetingNotificationOccurrence> = []
    private(set) var supersededOccurrences: Set<MeetingNotificationOccurrence> = []
    // Retaining activations through brief provider omissions prevents a restored event
    // from looking like a newly opened reminder window.
    private var activatedOccurrences: Set<MeetingNotificationOccurrence> = []

    var excludedOccurrences: Set<MeetingNotificationOccurrence> {
        dismissedOccurrences.union(supersededOccurrences)
    }

    mutating func eventToPresent(
        from events: [CalendarEvent],
        schedule: UpcomingMeetingNotificationSchedule,
        selectedCalendarIdentifiers: Set<String>?,
        isEnabled: Bool,
        now: Date
    ) -> CalendarEvent? {
        prune(using: schedule, now: now)

        guard isEnabled else {
            resetPresentation()
            activatedOccurrences.removeAll()
            return nil
        }

        let activeEvents = schedule.activeEvents(
            from: events,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            excluding: excludedOccurrences,
            now: now
        )
        let activeOccurrences = Set(activeEvents.map(MeetingNotificationOccurrence.init))
        defer { activatedOccurrences.formUnion(activeOccurrences) }

        if let presentedOccurrence,
           let currentEvent = activeEvents.first(where: {
               MeetingNotificationOccurrence(event: $0) == presentedOccurrence
           })
        {
            let newlyActivatedEvents = activeEvents.filter { event in
                MeetingNotificationOccurrence(event: event) != presentedOccurrence
                    && !activatedOccurrences.contains(MeetingNotificationOccurrence(event: event))
            }
            let newlyActivatedReplacement = schedule.preferredEvent(
                from: newlyActivatedEvents,
                now: now
            )
            let upcomingReplacement = currentEvent.startDate <= now
                ? schedule.preferredEvent(
                    from: activeEvents.filter { $0.startDate > now },
                    now: now
                )
                : nil

            if let replacement = newlyActivatedReplacement ?? upcomingReplacement {
                supersededOccurrences.insert(presentedOccurrence)
                setPresented(replacement)
                return replacement
            }

            return currentEvent
        }

        resetPresentation()
        guard let event = schedule.preferredEvent(from: activeEvents, now: now) else {
            return nil
        }

        setPresented(event)
        return event
    }

    @discardableResult
    mutating func dismissPresented() -> MeetingNotificationOccurrence? {
        guard let presentedOccurrence else { return nil }
        dismissedOccurrences.insert(presentedOccurrence)
        resetPresentation()
        return presentedOccurrence
    }

    mutating func resetPresentation() {
        presentedOccurrence = nil
    }

    private mutating func setPresented(_ event: CalendarEvent) {
        presentedOccurrence = MeetingNotificationOccurrence(event: event)
    }

    private mutating func prune(
        using schedule: UpcomingMeetingNotificationSchedule,
        now: Date
    ) {
        dismissedOccurrences = Set(dismissedOccurrences.filter {
            schedule.shouldRetain($0, now: now)
        })
        supersededOccurrences = Set(supersededOccurrences.filter {
            schedule.shouldRetain($0, now: now)
        })
        activatedOccurrences = Set(activatedOccurrences.filter {
            schedule.shouldRetain($0, now: now)
        })
    }
}
