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
