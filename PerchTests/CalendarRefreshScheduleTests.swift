import AppKit
import XCTest
@testable import Perch

final class CalendarRefreshScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNextRefreshDateAlignsMidMinuteToNextMinuteBoundary() {
        let date = makeDate(hour: 9, minute: 14, second: 37)

        let nextDate = CalendarRefreshSchedule.nextRefreshDate(after: date, calendar: calendar)

        XCTAssertEqual(nextDate, makeDate(hour: 9, minute: 15, second: 0))
    }

    func testNextRefreshDateAtBoundaryUsesFollowingMinute() {
        let date = makeDate(hour: 9, minute: 15, second: 0)

        let nextDate = CalendarRefreshSchedule.nextRefreshDate(after: date, calendar: calendar)

        XCTAssertEqual(nextDate, makeDate(hour: 9, minute: 16, second: 0))
    }

    private func makeDate(hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 5
        components.day = 6
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}

final class UpcomingMeetingNotificationScheduleTests: XCTestCase {
    private let schedule = UpcomingMeetingNotificationSchedule(
        leadTime: 5 * 60,
        postStartDisplayDuration: 5 * 60
    )
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testPresentsMeetingInsideLeadWindow() {
        let event = makeEvent(startDate: now.addingTimeInterval(4 * 60))

        let result = schedule.eventToPresent(
            from: [event],
            selectedCalendarIdentifiers: nil,
            dismissedOccurrences: [],
            now: now
        )

        XCTAssertEqual(result, event)
    }

    func testWaitsUntilFiveMinutesBeforeFutureMeeting() {
        let event = makeEvent(startDate: now.addingTimeInterval(20 * 60))

        let result = schedule.eventToPresent(
            from: [event],
            selectedCalendarIdentifiers: nil,
            dismissedOccurrences: [],
            now: now
        )
        let nextDate = schedule.nextPresentationDate(
            from: [event],
            selectedCalendarIdentifiers: nil,
            dismissedOccurrences: [],
            now: now
        )

        XCTAssertNil(result)
        XCTAssertEqual(nextDate, event.startDate.addingTimeInterval(-5 * 60))
    }

    func testChoosesTheEarliestEligibleMeetingRegardlessOfInputOrder() {
        let later = makeEvent(id: "later", startDate: now.addingTimeInterval(4 * 60))
        let earlier = makeEvent(id: "earlier", startDate: now.addingTimeInterval(2 * 60))

        let result = schedule.eventToPresent(
            from: [later, earlier],
            selectedCalendarIdentifiers: nil,
            dismissedOccurrences: [],
            now: now
        )

        XCTAssertEqual(result, earlier)
    }

    func testSupportsEveryMeetingProvider() {
        let providers: [(MeetingProvider, String)] = [
            (.zoom, "https://zoom.us/j/1234567890"),
            (.googleMeet, "https://meet.google.com/abc-defg-hij"),
            (.microsoftTeams, "https://teams.microsoft.com/l/meetup-join/abc"),
            (.webex, "https://company.webex.com/meet/alex"),
            (.other, "https://calls.example.com/room/weekly")
        ]

        for (index, provider) in providers.enumerated() {
            let event = makeEvent(
                id: "event-\(index)",
                startDate: now.addingTimeInterval(4 * 60),
                meetingLink: MeetingLink(
                    url: URL(string: provider.1)!,
                    provider: provider.0
                )
            )

            XCTAssertEqual(
                schedule.eventToPresent(
                    from: [event],
                    selectedCalendarIdentifiers: nil,
                    dismissedOccurrences: [],
                    now: now
                ),
                event
            )
        }
    }

    func testIgnoresAllDayUnlinkedAndUnselectedEvents() {
        let allDay = makeEvent(
            id: "all-day",
            startDate: now.addingTimeInterval(4 * 60),
            isAllDay: true
        )
        let unlinked = makeEvent(
            id: "unlinked",
            startDate: now.addingTimeInterval(3 * 60),
            meetingLink: nil
        )
        let unselected = makeEvent(
            id: "unselected",
            startDate: now.addingTimeInterval(2 * 60),
            calendarIdentifier: "hidden"
        )

        let result = schedule.eventToPresent(
            from: [allDay, unlinked, unselected],
            selectedCalendarIdentifiers: ["visible"],
            dismissedOccurrences: [],
            now: now
        )

        XCTAssertNil(result)
    }

    func testDismissalIsScopedToOneEventOccurrence() {
        let event = makeEvent(startDate: now.addingTimeInterval(4 * 60))
        let dismissed = Set([UpcomingMeetingOccurrence(event: event)])
        let rescheduledEvent = makeEvent(startDate: now.addingTimeInterval(3 * 60))

        XCTAssertNil(
            schedule.eventToPresent(
                from: [event],
                selectedCalendarIdentifiers: nil,
                dismissedOccurrences: dismissed,
                now: now
            )
        )
        XCTAssertEqual(
            schedule.eventToPresent(
                from: [rescheduledEvent],
                selectedCalendarIdentifiers: nil,
                dismissedOccurrences: dismissed,
                now: now
            ),
            rescheduledEvent
        )
    }

    func testPresentedMeetingRemainsAvailableBrieflyAfterStart() {
        let event = makeEvent(
            startDate: now.addingTimeInterval(-2 * 60),
            endDate: now.addingTimeInterval(30 * 60)
        )

        XCTAssertTrue(
            schedule.shouldKeepPresented(
                event,
                selectedCalendarIdentifiers: nil,
                now: now
            )
        )
        XCTAssertFalse(
            schedule.shouldKeepPresented(
                event,
                selectedCalendarIdentifiers: nil,
                now: event.startDate.addingTimeInterval(5 * 60)
            )
        )
    }

    func testNotificationExpiresWhenAShortMeetingEnds() {
        let event = makeEvent(
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(30)
        )

        XCTAssertEqual(schedule.expirationDate(for: event), event.endDate)
        XCTAssertFalse(
            schedule.shouldKeepPresented(
                event,
                selectedCalendarIdentifiers: nil,
                now: event.endDate
            )
        )
    }

    private func makeEvent(
        id: String = "event",
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        calendarIdentifier: String = "calendar",
        meetingLink: MeetingLink? = MeetingLink(
            url: URL(string: "https://zoom.us/j/1234567890")!,
            provider: .zoom
        )
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Design review",
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(30 * 60),
            isAllDay: isAllDay,
            calendarTitle: "Work",
            calendarColor: .systemBlue,
            calendarIdentifier: calendarIdentifier,
            meetingLink: meetingLink
        )
    }
}
