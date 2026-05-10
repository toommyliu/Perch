import AppKit
import Foundation

enum MenuBarLabelContent: Equatable {
    case dateIcon(day: Int)
    case event(title: String, relativeText: String, color: NSColor?)

    static func == (lhs: MenuBarLabelContent, rhs: MenuBarLabelContent) -> Bool {
        switch (lhs, rhs) {
        case let (.dateIcon(lhsDay), .dateIcon(rhsDay)):
            return lhsDay == rhsDay
        case let (.event(lhsTitle, lhsRelativeText, lhsColor), .event(rhsTitle, rhsRelativeText, rhsColor)):
            let colorsMatch: Bool
            switch (lhsColor, rhsColor) {
            case let (lhsColor?, rhsColor?):
                colorsMatch = lhsColor.isEqual(rhsColor)
            case (nil, nil):
                colorsMatch = true
            default:
                colorsMatch = false
            }

            return lhsTitle == rhsTitle
                && lhsRelativeText == rhsRelativeText
                && colorsMatch
        default:
            return false
        }
    }
}

struct MenuBarLabelFormatter {
    private let maxTitleLength = 28

    func labelContent(
        events: [CalendarEvent],
        settings: CalendarMenubarSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MenuBarLabelContent {
        let day = calendar.component(.day, from: now)

        guard settings.displayMode != .never,
              let nextEvent = CalendarEventVisibility.upcomingEvents(
                from: events,
                includeAllDayEvents: settings.showAllDayEvents,
                now: now
              ).first
        else {
            return .dateIcon(day: day)
        }

        guard shouldShow(nextEvent, mode: settings.displayMode, now: now) else {
            return .dateIcon(day: day)
        }

        return .event(
            title: EventTitleTruncator.truncate(nextEvent.title, maxLength: maxTitleLength),
            relativeText: relativeText(for: nextEvent, mode: settings.displayMode, now: now, calendar: calendar),
            color: settings.showEventColors ? nextEvent.calendarColor : .perchMutedWhite
        )
    }

    private func shouldShow(_ event: CalendarEvent, mode: MenuBarDisplayMode, now: Date) -> Bool {
        if mode == .always {
            return true
        }

        if event.startDate <= now && event.endDate >= now {
            return true
        }

        guard let leadTime = mode.leadTime else {
            return true
        }

        return event.startDate <= now.addingTimeInterval(leadTime)
    }

    private func relativeText(
        for event: CalendarEvent,
        mode: MenuBarDisplayMode,
        now: Date,
        calendar: Calendar
    ) -> String {
        if event.isAllDay {
            if calendar.isDate(event.startDate, inSameDayAs: now)
                || (event.startDate <= now && event.endDate >= now) {
                return "today"
            }

            return mode == .always ? DateFormatting.weekday(event.startDate) : futureRelativeText(from: now, to: event.startDate)
        }

        if event.startDate <= now && event.endDate >= now {
            return remainingRelativeText(from: now, to: event.endDate)
        }

        return futureRelativeText(from: now, to: event.startDate)
    }

    private func futureRelativeText(from now: Date, to startDate: Date) -> String {
        "in \(compactDuration(startDate.timeIntervalSince(now)))"
    }

    private func remainingRelativeText(from now: Date, to endDate: Date) -> String {
        "\(compactDuration(endDate.timeIntervalSince(now))) left"
    }

    private func compactDuration(_ timeInterval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(timeInterval / 60))
        let days = totalMinutes / (24 * 60)

        if days > 0 {
            let hours = (totalMinutes % (24 * 60)) / 60
            return "\(days)d \(hours)h"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        return "\(hours)h \(minutes)m"
    }

}
