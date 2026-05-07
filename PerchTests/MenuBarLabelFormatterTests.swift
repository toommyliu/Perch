import AppKit
import XCTest
@testable import Perch

final class MenuBarLabelFormatterTests: XCTestCase {
    private let formatter = MenuBarLabelFormatter()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func testDateModeReturnsTodayIconWhenNoEventsExist() {
        let now = date(hour: 9, minute: 0)

        let content = formatter.labelContent(
            events: [],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .dateIcon(day: 6))
    }

    func testWithinSixHoursShowsEventFiveHoursFiftyNineMinutesAway() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(hour: 14, minute: 59), end: date(hour: 15, minute: 30))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 5h 59m", color: .systemBlue))
    }

    func testWithinSixHoursDoesNotShowEventSixHoursOneMinuteAway() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(hour: 15, minute: 1), end: date(hour: 16, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .dateIcon(day: 6))
    }

    func testAlwaysShowsNextEventBeyondSixHours() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(day: 7, hour: 11, minute: 30), end: date(day: 7, hour: 12, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: CalendarMenubarSettings(displayMode: .always, lookAheadDays: 7),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "Thu", color: .systemBlue))
    }

    func testNeverDoesNotShowEventText() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(hour: 9, minute: 10), end: date(hour: 10, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: CalendarMenubarSettings(displayMode: .never, lookAheadDays: 7),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .dateIcon(day: 6))
    }

    func testEventColorIsMutedWhiteWhenCalendarColorsAreDisabled() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(hour: 10, minute: 0), end: date(hour: 11, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: CalendarMenubarSettings(displayMode: .within6Hours, lookAheadDays: 7, showEventColors: false),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 1h 0m", color: .perchMutedWhite))
    }

    func testOngoingTimedEventFormatsAsNow() {
        let now = date(hour: 9, minute: 30)
        let event = makeEvent(start: date(hour: 9, minute: 0), end: date(hour: 10, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "now", color: .systemBlue))
    }

    func testAllDayEventFormatsAsToday() {
        let now = date(hour: 9, minute: 30)
        let event = CalendarEvent(
            id: "all-day",
            title: "Conference",
            startDate: date(hour: 0, minute: 0),
            endDate: date(day: 7, hour: 0, minute: 0),
            isAllDay: true,
            calendarTitle: "School",
            calendarColor: .systemBlue
        )

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "Conference", relativeText: "today", color: .systemBlue))
    }

    func testAllDayEventIsIgnoredWhenDisabled() {
        let now = date(hour: 9, minute: 30)
        let allDayEvent = CalendarEvent(
            id: "all-day",
            title: "Conference",
            startDate: date(hour: 0, minute: 0),
            endDate: date(day: 7, hour: 0, minute: 0),
            isAllDay: true,
            calendarTitle: "School",
            calendarColor: .systemBlue
        )
        let timedEvent = makeEvent(start: date(hour: 10, minute: 0), end: date(hour: 11, minute: 0))

        let content = formatter.labelContent(
            events: [allDayEvent, timedEvent],
            settings: CalendarMenubarSettings(displayMode: .within6Hours, lookAheadDays: 7, showAllDayEvents: false),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 30m", color: .systemBlue))
    }

    func testLongTitleTruncatesWhilePreservingRelativeTime() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(
            title: "Extremely Long Calendar Event Title That Should Be Truncated",
            start: date(hour: 10, minute: 0),
            end: date(hour: 11, minute: 0)
        )

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            content,
            .event(title: "Extremely Long Calendar Eve...", relativeText: "in 1h 0m", color: .systemBlue)
        )
    }

    private func makeEvent(
        title: String = "CMPE172",
        start: Date,
        end: Date
    ) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarTitle: "School",
            calendarColor: .systemBlue
        )
    }

    private func date(day: Int = 6, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 5
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
