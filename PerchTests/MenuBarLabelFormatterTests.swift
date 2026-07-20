import AppKit
import XCTest
@testable import Perch

final class MenuBarLabelFormatterTests: XCTestCase {
    private let formatter = MenuBarLabelFormatter(locale: Locale(identifier: "en_US"))
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

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 1d 2h", color: .systemBlue))
    }

    func testFutureTimedEventTomorrowInAlwaysModeShowsCountdown() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(day: 7, hour: 8, minute: 12), end: date(day: 7, hour: 9, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: CalendarMenubarSettings(displayMode: .always, lookAheadDays: 7),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 23h 12m", color: .systemBlue))
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

    func testOngoingTimedEventShowsTimeRemaining() {
        let now = date(hour: 9, minute: 30)
        let event = makeEvent(start: date(hour: 9, minute: 0), end: date(hour: 10, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "30m left", color: .systemBlue))
    }

    func testOngoingTimedEventShowsHoursAndMinutesRemaining() {
        let now = date(hour: 9, minute: 30)
        let event = makeEvent(start: date(hour: 9, minute: 0), end: date(hour: 10, minute: 45))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "1h 15m left", color: .systemBlue))
    }

    func testEventStartingInLessThanOneMinuteShowsZeroMinuteCountdown() {
        let now = date(hour: 9, minute: 0, second: 30)
        let event = makeEvent(start: date(hour: 9, minute: 0, second: 59), end: date(hour: 10, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "in 0m", color: .systemBlue))
    }

    func testEventEndingInLessThanOneMinuteShowsZeroMinutesLeft() {
        let now = date(hour: 9, minute: 59, second: 30)
        let event = makeEvent(start: date(hour: 9, minute: 0), end: date(hour: 9, minute: 59, second: 59))

        let content = formatter.labelContent(
            events: [event],
            settings: .defaultValue,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "CMPE172", relativeText: "0m left", color: .systemBlue))
    }

    func testAllDayEventFormatsAsAllDay() {
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

        XCTAssertEqual(content, .event(title: "Conference", relativeText: "All-day", color: .systemBlue))
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

    func testEventFromUnselectedCalendarIsIgnored() {
        let now = date(hour: 9, minute: 0)
        let holiday = makeEvent(
            title: "Holiday",
            calendarIdentifier: "holidays",
            start: date(hour: 9, minute: 30),
            end: date(hour: 10, minute: 0)
        )
        let work = makeEvent(
            title: "Standup",
            calendarIdentifier: "work",
            start: date(hour: 10, minute: 0),
            end: date(hour: 10, minute: 30)
        )

        let content = formatter.labelContent(
            events: [holiday, work],
            settings: CalendarMenubarSettings(
                displayMode: .within6Hours,
                lookAheadDays: 7,
                selectedCalendarIdentifiers: ["work"]
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .event(title: "Standup", relativeText: "in 1h 0m", color: .systemBlue))
    }

    func testExplicitEmptyCalendarSelectionShowsDateIcon() {
        let now = date(hour: 9, minute: 0)
        let event = makeEvent(start: date(hour: 10, minute: 0), end: date(hour: 11, minute: 0))

        let content = formatter.labelContent(
            events: [event],
            settings: CalendarMenubarSettings(
                displayMode: .within6Hours,
                lookAheadDays: 7,
                selectedCalendarIdentifiers: []
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content, .dateIcon(day: 6))
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
            .event(title: "Extremely Long Calendar E...", relativeText: "in 1h 0m", color: .systemBlue)
        )
    }

    private func makeEvent(
        title: String = "CMPE172",
        calendarIdentifier: String = "school",
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
            calendarColor: .systemBlue,
            calendarIdentifier: calendarIdentifier
        )
    }

    private func date(day: Int = 6, hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 5
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}

final class DateFormattingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testEventTimeUsesLocalePreferredHourCycle() {
        let date = makeDate(day: 14, hour: 13, minute: 5)

        let twelveHourTime = DateFormatting.eventTime(
            date,
            locale: Locale(identifier: "en_US@hours=h12"),
            calendar: calendar
        )
        let twentyFourHourTime = DateFormatting.eventTime(
            date,
            locale: Locale(identifier: "en_US@hours=h23"),
            calendar: calendar
        )

        XCTAssertTrue(twelveHourTime.hasPrefix("1:05"))
        XCTAssertTrue(twelveHourTime.hasSuffix("PM"))
        XCTAssertEqual(twentyFourHourTime, "13:05")
    }

    func testMenuSectionDateOrderFollowsLocale() {
        let date = makeDate(day: 14, hour: 13, minute: 5)
        let now = makeDate(day: 12, hour: 9, minute: 0)

        XCTAssertEqual(
            DateFormatting.menuSectionTitle(
                for: date,
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en_US")
            ),
            "Wed, Jan 14"
        )
        XCTAssertEqual(
            DateFormatting.menuSectionTitle(
                for: date,
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en_GB")
            ),
            "Wed 14 Jan"
        )
        XCTAssertEqual(
            DateFormatting.menuSectionTitle(
                for: date,
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "ja_JP")
            ),
            "1月14日(水)"
        )
    }

    func testRelativeDayTitlesUseLocale() {
        let now = makeDate(day: 14, hour: 9, minute: 0)

        XCTAssertEqual(
            DateFormatting.menuSectionTitle(
                for: makeDate(day: 14, hour: 13, minute: 5),
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "de_DE")
            ),
            "Heute"
        )
        XCTAssertEqual(
            DateFormatting.menuSectionTitle(
                for: makeDate(day: 15, hour: 13, minute: 5),
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "de_DE")
            ),
            "Morgen"
        )
    }

    func testWeekdayUsesLocale() {
        let date = makeDate(day: 14, hour: 13, minute: 5)

        XCTAssertEqual(
            DateFormatting.weekday(
                date,
                locale: Locale(identifier: "en_US"),
                calendar: calendar
            ),
            "Wed"
        )
        XCTAssertEqual(
            DateFormatting.weekday(
                date,
                locale: Locale(identifier: "ja_JP"),
                calendar: calendar
            ),
            "水"
        )
    }

    private func makeDate(day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
