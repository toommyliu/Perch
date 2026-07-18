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
    let calendarIdentifier: String
    let meetingLink: MeetingLink?
    let location: String?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        calendarColor: NSColor,
        calendarIdentifier: String = "",
        meetingLink: MeetingLink? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.calendarIdentifier = calendarIdentifier
        self.meetingLink = meetingLink
        self.location = location
    }
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
            && lhs.calendarIdentifier == rhs.calendarIdentifier
            && lhs.meetingLink == rhs.meetingLink
            && lhs.location == rhs.location
    }
}
