import AppKit
import Foundation

enum MenuBarLabelContent: Equatable {
    case dateIcon(day: Int)
    case event(title: String, relativeText: String, color: NSColor?)
    case reminder(title: String, relativeText: String)

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
        case let (.reminder(lhsTitle, lhsRelativeText), .reminder(rhsTitle, rhsRelativeText)):
            return lhsTitle == rhsTitle && lhsRelativeText == rhsRelativeText
        default:
            return false
        }
    }
}

struct MenuBarLabelFormatter {
    private let maxTitleLength = 28
    private let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func labelContent(
        events: [CalendarEvent],
        reminders: [CalendarReminder] = [],
        settings: CalendarMenubarSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MenuBarLabelContent {
        let day = calendar.component(.day, from: now)

        guard let nextItem = AgendaItemVisibility.visibleItems(
            events: events,
            reminders: reminders,
            includeAllDayEvents: settings.showAllDayEvents,
            includeReminders: settings.showReminders,
            selectedCalendarIdentifiers: settings.selectedCalendarIdentifiers,
            now: now,
            calendar: calendar
        ).first,
              AgendaItemVisibility.shouldPrioritize(
                nextItem,
                displayMode: settings.displayMode,
                now: now
              )
        else {
            return .dateIcon(day: day)
        }

        switch nextItem {
        case let .event(event):
            return .event(
                title: EventTitleTruncator.truncate(event.title, maxLength: maxTitleLength),
                relativeText: relativeText(
                    for: event,
                    mode: settings.displayMode,
                    now: now,
                    calendar: calendar
                ),
                color: settings.showEventColors ? event.calendarColor : .perchMutedWhite
            )
        case let .reminder(reminder):
            return .reminder(
                title: EventTitleTruncator.truncate(reminder.title, maxLength: maxTitleLength),
                relativeText: relativeText(for: reminder, now: now, calendar: calendar)
            )
        }
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
                return "All-day"
            }

            return mode == .always
                ? DateFormatting.weekday(event.startDate, locale: locale, calendar: calendar)
                : futureRelativeText(from: now, to: event.startDate)
        }

        if event.startDate <= now && event.endDate >= now {
            return remainingRelativeText(from: now, to: event.endDate)
        }

        return futureRelativeText(from: now, to: event.startDate)
    }

    private func futureRelativeText(from now: Date, to startDate: Date) -> String {
        "in \(compactDuration(startDate.timeIntervalSince(now)))"
    }

    private func relativeText(
        for reminder: CalendarReminder,
        now: Date,
        calendar: Calendar
    ) -> String {
        if reminder.isAllDay, calendar.isDate(reminder.dueDate, inSameDayAs: now) {
            return "Due today"
        }

        if reminder.dueDate <= now {
            let elapsed = now.timeIntervalSince(reminder.dueDate)
            return elapsed < 60 ? "Due now" : "\(compactDuration(elapsed)) overdue"
        }

        return futureRelativeText(from: now, to: reminder.dueDate)
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
