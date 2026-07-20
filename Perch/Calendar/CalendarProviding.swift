import AppKit
import Foundation

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceIdentifier: String
    let sourceTitle: String
    let color: NSColor

    init(
        id: String,
        title: String,
        sourceTitle: String,
        color: NSColor
    ) {
        self.init(
            id: id,
            title: title,
            sourceTitle: sourceTitle,
            sourceIdentifier: sourceTitle,
            color: color
        )
    }

    init(
        id: String,
        title: String,
        sourceTitle: String,
        sourceIdentifier: String,
        color: NSColor
    ) {
        self.id = id
        self.title = title
        self.sourceIdentifier = sourceIdentifier
        self.sourceTitle = sourceTitle
        self.color = color
    }

    static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.sourceIdentifier == rhs.sourceIdentifier
            && lhs.sourceTitle == rhs.sourceTitle
            && lhs.color.isEqual(rhs.color)
    }
}

protocol CalendarPermissionProviding {
    func authorizationState() -> CalendarAccessState
    func requestFullAccess() async -> CalendarAccessState
}

protocol CalendarEventProviding {
    func availableCalendars() async throws -> [CalendarInfo]
    func events(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> [CalendarEvent]
}

typealias CalendarProviding = CalendarPermissionProviding & CalendarEventProviding

#if DEBUG
final class DemoCalendarProvider: CalendarProviding {
    private let calendars = [
        CalendarInfo(id: "demo-calendar", title: "Calendar", sourceTitle: "iCloud", color: .systemRed),
        CalendarInfo(id: "demo-home", title: "Home", sourceTitle: "iCloud", color: .systemTeal),
        CalendarInfo(id: "demo-school", title: "School", sourceTitle: "iCloud", color: .systemBlue),
        CalendarInfo(id: "demo-work", title: "Work", sourceTitle: "iCloud", color: .systemPurple),
        CalendarInfo(id: "demo-birthdays", title: "Birthdays", sourceTitle: "Other", color: .systemGray),
        CalendarInfo(id: "demo-holidays", title: "Holidays in United States", sourceTitle: "Personal", color: .systemGreen),
        CalendarInfo(id: "demo-personal", title: "alex@example.com", sourceTitle: "Personal", color: .systemCyan),
        CalendarInfo(id: "demo-school-holidays", title: "Holidays in United States", sourceTitle: "School", color: .systemGreen),
        CalendarInfo(id: "demo-classes", title: "Class schedule", sourceTitle: "School", color: .systemIndigo),
        CalendarInfo(id: "demo-family", title: "Family", sourceTitle: "Home", color: .systemOrange)
    ]

    func authorizationState() -> CalendarAccessState { .fullAccess }
    func requestFullAccess() async -> CalendarAccessState { .fullAccess }
    func availableCalendars() async throws -> [CalendarInfo] { calendars }

    func events(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let events = [
            CalendarEvent(
                id: "demo-design-review",
                title: "Product design review",
                startDate: now.addingTimeInterval(-12 * 60),
                endDate: now.addingTimeInterval(33 * 60),
                isAllDay: false,
                calendarTitle: "Work",
                calendarColor: .systemBlue,
                calendarIdentifier: "demo-work",
                meetingLink: MeetingLink(
                    url: URL(string: "https://meet.google.com/abc-defg-hij")!,
                    provider: .googleMeet
                )
            ),
            CalendarEvent(
                id: "demo-lunch",
                title: "Lunch with Maya",
                startDate: now.addingTimeInterval(75 * 60),
                endDate: now.addingTimeInterval(135 * 60),
                isAllDay: false,
                calendarTitle: "Personal",
                calendarColor: .systemPurple,
                calendarIdentifier: "demo-personal",
                location: "The Mill, 736 Divisadero St"
            ),
            CalendarEvent(
                id: "demo-planning",
                title: "Weekly planning",
                startDate: now.addingTimeInterval(3.5 * 60 * 60),
                endDate: now.addingTimeInterval(4.25 * 60 * 60),
                isAllDay: false,
                calendarTitle: "Work",
                calendarColor: .systemBlue,
                calendarIdentifier: "demo-work",
                meetingLink: MeetingLink(
                    url: URL(string: "https://company.zoom.us/j/1234567890")!,
                    provider: .zoom
                )
            ),
            CalendarEvent(
                id: "demo-family-day",
                title: "Mom's birthday",
                startDate: tomorrow,
                endDate: calendar.date(byAdding: .day, value: 1, to: tomorrow)!,
                isAllDay: true,
                calendarTitle: "Family",
                calendarColor: .systemOrange,
                calendarIdentifier: "demo-family"
            ),
            CalendarEvent(
                id: "demo-studio",
                title: "Studio session",
                startDate: calendar.date(byAdding: .hour, value: 10, to: tomorrow)!,
                endDate: calendar.date(byAdding: .hour, value: 12, to: tomorrow)!,
                isAllDay: false,
                calendarTitle: "Personal",
                calendarColor: .systemPurple,
                calendarIdentifier: "demo-personal",
                location: "Dogpatch Studios"
            )
        ]

        return events.filter { event in
            event.endDate >= startDate
                && event.startDate <= endDate
                && (calendarIdentifiers?.contains(event.calendarIdentifier) ?? true)
        }
    }
}
#endif
