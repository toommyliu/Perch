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
              let nextEvent = nextVisibleEvent(from: events, now: now)
        else {
            return .dateIcon(day: day)
        }

        guard shouldShow(nextEvent, mode: settings.displayMode, now: now) else {
            return .dateIcon(day: day)
        }

        return .event(
            title: truncatedTitle(nextEvent.title),
            relativeText: relativeText(for: nextEvent, mode: settings.displayMode, now: now, calendar: calendar),
            color: settings.showEventColors ? nextEvent.calendarColor : .white
        )
    }

    private func nextVisibleEvent(from events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events
            .filter { $0.endDate >= now }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }

                if $0.endDate != $1.endDate {
                    return $0.endDate < $1.endDate
                }

                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .first
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
            return "now"
        }

        if mode == .always && !calendar.isDate(event.startDate, inSameDayAs: now) {
            return DateFormatting.weekday(event.startDate)
        }

        return futureRelativeText(from: now, to: event.startDate)
    }

    private func futureRelativeText(from now: Date, to startDate: Date) -> String {
        let totalMinutes = max(0, Int(startDate.timeIntervalSince(now) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "in \(minutes)m"
        }

        return "in \(hours)h \(minutes)m"
    }

    private func truncatedTitle(_ title: String) -> String {
        guard title.count > maxTitleLength else {
            return title
        }

        let endIndex = title.index(title.startIndex, offsetBy: maxTitleLength - 1)
        return "\(title[..<endIndex])..."
    }
}
