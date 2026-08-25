import AppKit
import XCTest
@testable import Perch

final class UpcomingMeetingNotificationScheduleTests: XCTestCase {
    private let schedule = UpcomingMeetingNotificationSchedule()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMeetingBecomesActiveFiveMinutesBeforeItStarts() {
        let event = makeEvent(id: "meeting", startMinute: 60)

        XCTAssertTrue(activeEvents([event], atMinute: 54, second: 59).isEmpty)
        XCTAssertEqual(activeEvents([event], atMinute: 55).map(\.id), ["meeting"])
    }

    func testStartedMeetingRemainsActiveDuringGracePeriod() {
        let event = makeEvent(id: "meeting", startMinute: 60)
        let now = makeDate(minute: 62)
        let active = schedule.activeEvents(
            from: [event],
            selectedCalendarIdentifiers: nil,
            excluding: [],
            now: now
        )

        XCTAssertEqual(schedule.preferredEvent(from: active, now: now)?.id, "meeting")
        XCTAssertTrue(schedule.activeEvents(
            from: [event],
            selectedCalendarIdentifiers: nil,
            excluding: [],
            now: makeDate(minute: 65)
        ).isEmpty)
    }

    func testStartedMeetingCrossingMidnightCanBePresented() {
        let startDate = makeDate(day: 24, hour: 23, minute: 58)
        let event = makeEvent(
            id: "late-meeting",
            startDate: startDate,
            endDate: makeDate(day: 25, hour: 1, minute: 0)
        )
        let now = makeDate(day: 25, hour: 0, minute: 1)

        XCTAssertEqual(schedule.activeEvents(
            from: [event],
            selectedCalendarIdentifiers: nil,
            excluding: [],
            now: now
        ).map(\.id), ["late-meeting"])
    }

    func testEverySupportedMeetingProviderIsEligible() {
        let providers: [MeetingProvider] = [
            .zoom,
            .googleMeet,
            .microsoftTeams,
            .webex,
            .other
        ]
        let events = providers.enumerated().map { index, provider in
            makeEvent(id: provider.rawValue, startMinute: 60 + index, provider: provider)
        }

        XCTAssertEqual(activeEvents(events, atMinute: 59).count, providers.count)
    }

    func testEligibilityHonorsCalendarSelectionAndEventShape() {
        let selected = makeEvent(id: "selected", startMinute: 60, calendarIdentifier: "work")
        let hidden = makeEvent(id: "hidden", startMinute: 60, calendarIdentifier: "home")
        let allDay = makeEvent(id: "all-day", startMinute: 60, isAllDay: true)
        let noLink = makeEvent(id: "no-link", startMinute: 60, provider: nil)

        let active = schedule.activeEvents(
            from: [selected, hidden, allDay, noLink],
            selectedCalendarIdentifiers: ["work"],
            excluding: [],
            now: makeDate(minute: 59)
        )

        XCTAssertEqual(active.map(\.id), ["selected"])
    }

    func testOverlappingReminderSchedulesTheNextWindowOpening() {
        let first = makeEvent(id: "first", startMinute: 60)
        let second = makeEvent(id: "second", startMinute: 62)

        XCTAssertEqual(
            schedule.nextTransitionDate(
                from: [first, second],
                selectedCalendarIdentifiers: nil,
                excluding: [],
                now: makeDate(minute: 55)
            ),
            makeDate(minute: 57)
        )
    }

    func testLaterReminderReplacesCurrentCardWithoutDismissingIt() {
        let first = makeEvent(id: "first", startMinute: 60)
        let second = makeEvent(id: "second", startMinute: 62)
        var state = UpcomingMeetingNotificationState()

        XCTAssertEqual(reconcile(&state, events: [first, second], atMinute: 55)?.id, "first")
        XCTAssertEqual(reconcile(&state, events: [first, second], atMinute: 57)?.id, "second")

        let firstOccurrence = MeetingNotificationOccurrence(event: first)
        XCTAssertTrue(state.supersededOccurrences.contains(firstOccurrence))
        XCTAssertFalse(state.dismissedOccurrences.contains(firstOccurrence))

        state.dismissPresented()
        XCTAssertNil(reconcile(&state, events: [first, second], atMinute: 57))
    }

    func testStartedCardYieldsToAnUpcomingOverlappingMeeting() {
        let first = makeEvent(id: "first", startMinute: 60)
        let second = makeEvent(id: "second", startMinute: 62)
        var state = UpcomingMeetingNotificationState()

        XCTAssertEqual(reconcile(&state, events: [first, second], atMinute: 58)?.id, "first")
        XCTAssertEqual(reconcile(&state, events: [first, second], atMinute: 60)?.id, "second")
    }

    func testEventRescheduledInsideLeadWindowReplacesCurrentCard() {
        let current = makeEvent(id: "current", startMinute: 65)
        let original = makeEvent(id: "rescheduled", startMinute: 70)
        let movedEarlier = makeEvent(id: "rescheduled", startMinute: 63)
        var state = UpcomingMeetingNotificationState()

        XCTAssertEqual(reconcile(&state, events: [current, original], atMinute: 60)?.id, "current")
        XCTAssertEqual(
            reconcile(&state, events: [current, movedEarlier], atMinute: 61)?.id,
            "rescheduled"
        )
    }

    func testTemporarilyMissingEventDoesNotReplaceCurrentWhenItReturns() {
        let earlier = makeEvent(id: "earlier", startMinute: 64)
        let later = makeEvent(id: "later", startMinute: 65)
        var state = UpcomingMeetingNotificationState()

        XCTAssertEqual(reconcile(&state, events: [earlier, later], atMinute: 60)?.id, "earlier")
        XCTAssertEqual(reconcile(&state, events: [later], atMinute: 60)?.id, "later")
        XCTAssertEqual(reconcile(&state, events: [earlier, later], atMinute: 61)?.id, "later")
    }

    func testDisabledNotificationsClearThePresentedOccurrence() {
        let event = makeEvent(id: "meeting", startMinute: 60)
        var state = UpcomingMeetingNotificationState()

        XCTAssertEqual(reconcile(&state, events: [event], atMinute: 55)?.id, "meeting")
        XCTAssertNil(state.eventToPresent(
            from: [event],
            schedule: schedule,
            selectedCalendarIdentifiers: nil,
            isEnabled: false,
            now: makeDate(minute: 56)
        ))
        XCTAssertNil(state.presentedOccurrence)
    }

    private func activeEvents(
        _ events: [CalendarEvent],
        atMinute minute: Int,
        second: Int = 0
    ) -> [CalendarEvent] {
        schedule.activeEvents(
            from: events,
            selectedCalendarIdentifiers: nil,
            excluding: [],
            now: makeDate(minute: minute, second: second)
        )
    }

    private func reconcile(
        _ state: inout UpcomingMeetingNotificationState,
        events: [CalendarEvent],
        atMinute minute: Int
    ) -> CalendarEvent? {
        state.eventToPresent(
            from: events,
            schedule: schedule,
            selectedCalendarIdentifiers: nil,
            isEnabled: true,
            now: makeDate(minute: minute)
        )
    }

    private func makeEvent(
        id: String,
        startMinute: Int,
        provider: MeetingProvider? = .zoom,
        calendarIdentifier: String = "work",
        isAllDay: Bool = false
    ) -> CalendarEvent {
        let startDate = makeDate(minute: startMinute)
        return makeEvent(
            id: id,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            provider: provider,
            calendarIdentifier: calendarIdentifier,
            isAllDay: isAllDay
        )
    }

    private func makeEvent(
        id: String,
        startDate: Date,
        endDate: Date,
        provider: MeetingProvider? = .zoom,
        calendarIdentifier: String = "work",
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarTitle: "Work",
            calendarColor: .systemBlue,
            calendarIdentifier: calendarIdentifier,
            meetingLink: provider.map {
                MeetingLink(url: URL(string: "https://example.com/\(id)")!, provider: $0)
            }
        )
    }

    private func makeDate(
        day: Int = 25,
        hour: Int = 9,
        minute: Int,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        let hourStart = components.date!
        return hourStart.addingTimeInterval(TimeInterval((minute * 60) + second))
    }
}
