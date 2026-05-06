import AppKit
import XCTest
@testable import Dayline

final class MenuBuilderTests: XCTestCase {
    private let builder = MenuBuilder()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func testEventsGroupIntoTodayTomorrowAndDateHeadings() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0)),
            event(title: "Tomorrow Event", start: date(day: 7, hour: 10, minute: 0), end: date(day: 7, hour: 11, minute: 0)),
            event(title: "Later Event", start: date(day: 8, hour: 10, minute: 0), end: date(day: 8, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.map(\.title), ["Today", "Tomorrow", "Fri May 8"])
    }

    func testPastEndedEventsAreExcludedAndOngoingEventsRemainVisible() {
        let now = date(day: 6, hour: 9, minute: 30)
        let events = [
            event(title: "Past", start: date(day: 6, hour: 8, minute: 0), end: date(day: 6, hour: 9, minute: 0)),
            event(title: "Current", start: date(day: 6, hour: 9, minute: 0), end: date(day: 6, hour: 10, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["9:00 AM · Current"])
    }

    func testAllDayRowsFormatAsAllDayTitle() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "all-day",
                title: "Conference",
                startDate: date(day: 6, hour: 0, minute: 0),
                endDate: date(day: 7, hour: 0, minute: 0),
                isAllDay: true,
                calendarTitle: "School",
                calendarColor: .systemRed
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "All day · Conference")
    }

    func testEmptyAuthorizedStateShowsNoUpcomingEvents() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "No upcoming events")
        XCTAssertFalse(snapshot.sections[0].rows[0].isEnabled)
    }

    func testDeniedStateShowsPrivacySettingsActions() {
        let snapshot = builder.snapshot(accessState: .denied, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), [
            "Calendar access denied",
            "Open Calendar Privacy Settings..."
        ])
        XCTAssertEqual(snapshot.sections[0].rows[1].action, .openPrivacySettings)
    }

    func testFooterRowsExposeMenuKeyEquivalents() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.footerRows[0].title, "Open Calendar")
        XCTAssertEqual(snapshot.footerRows[0].keyEquivalent, "1")
        XCTAssertEqual(snapshot.footerRows[0].keyEquivalentModifierMask, [.command])

        XCTAssertEqual(snapshot.footerRows[1].title, "Settings...")
        XCTAssertEqual(snapshot.footerRows[1].keyEquivalent, ",")
        XCTAssertEqual(snapshot.footerRows[1].keyEquivalentModifierMask, [.command])
    }

    private func event(title: String, start: Date, end: Date) -> CalendarEvent {
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

    private func date(day: Int, hour: Int, minute: Int) -> Date {
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
