import AppKit
import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: NSColor
}

extension CalendarEvent: Equatable {
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.calendarTitle == rhs.calendarTitle
            && lhs.calendarColor.isEqual(rhs.calendarColor)
    }
}
