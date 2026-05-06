import AppKit
import Foundation

enum CalendarMenuAction: Equatable {
    case requestAccess
    case openPrivacySettings
    case openCalendar
    case openSettings
    case quit
}

struct CalendarMenuRow: Equatable {
    let title: String
    let isEnabled: Bool
    let color: NSColor?
    let action: CalendarMenuAction?
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags

    init(
        title: String,
        isEnabled: Bool,
        color: NSColor?,
        action: CalendarMenuAction?,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.color = color
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifierMask = keyEquivalentModifierMask
    }

    static func == (lhs: CalendarMenuRow, rhs: CalendarMenuRow) -> Bool {
        let colorsMatch: Bool
        switch (lhs.color, rhs.color) {
        case let (lhsColor?, rhsColor?):
            colorsMatch = lhsColor.isEqual(rhsColor)
        case (nil, nil):
            colorsMatch = true
        default:
            colorsMatch = false
        }

        return lhs.title == rhs.title
            && lhs.isEnabled == rhs.isEnabled
            && colorsMatch
            && lhs.action == rhs.action
            && lhs.keyEquivalent == rhs.keyEquivalent
            && lhs.keyEquivalentModifierMask == rhs.keyEquivalentModifierMask
    }
}

struct CalendarMenuSection: Equatable {
    let title: String
    let rows: [CalendarMenuRow]
}

struct CalendarMenuSnapshot: Equatable {
    let sections: [CalendarMenuSection]
    let footerRows: [CalendarMenuRow]
}

struct MenuBuilder {
    func snapshot(
        accessState: CalendarAccessState,
        events: [CalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CalendarMenuSnapshot {
        switch accessState {
        case .notDetermined:
            return CalendarMenuSnapshot(
                sections: [
                    CalendarMenuSection(
                        title: "",
                        rows: [
                            CalendarMenuRow(title: "Allow Calendar Access...", isEnabled: true, color: nil, action: .requestAccess)
                        ]
                    )
                ],
                footerRows: standardFooterRows
            )
        case .denied, .restricted, .unknown:
            return CalendarMenuSnapshot(
                sections: [
                    CalendarMenuSection(
                        title: "",
                        rows: [
                            CalendarMenuRow(title: "Calendar access denied", isEnabled: false, color: nil, action: nil),
                            CalendarMenuRow(title: "Open Calendar Privacy Settings...", isEnabled: true, color: nil, action: .openPrivacySettings)
                        ]
                    )
                ],
                footerRows: standardFooterRows
            )
        case .fullAccess:
            return eventsSnapshot(events: events, now: now, calendar: calendar)
        }
    }

    func makeMenu(from snapshot: CalendarMenuSnapshot, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        for section in snapshot.sections {
            if !section.title.isEmpty {
                let header = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }

            for row in section.rows {
                menu.addItem(menuItem(for: row, target: target))
            }
        }

        menu.addItem(.separator())

        for row in snapshot.footerRows {
            menu.addItem(menuItem(for: row, target: target))
        }

        return menu
    }

    private var standardFooterRows: [CalendarMenuRow] {
        [
            CalendarMenuRow(
                title: "Open Calendar",
                isEnabled: true,
                color: nil,
                action: .openCalendar,
                keyEquivalent: "1",
                keyEquivalentModifierMask: [.command]
            ),
            CalendarMenuRow(
                title: "Settings...",
                isEnabled: true,
                color: nil,
                action: .openSettings,
                keyEquivalent: ",",
                keyEquivalentModifierMask: [.command]
            ),
            CalendarMenuRow(title: "Quit Dayline", isEnabled: true, color: nil, action: .quit)
        ]
    }

    private func eventsSnapshot(events: [CalendarEvent], now: Date, calendar: Calendar) -> CalendarMenuSnapshot {
        let visibleEvents = events
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

        guard !visibleEvents.isEmpty else {
            return CalendarMenuSnapshot(
                sections: [
                    CalendarMenuSection(
                        title: "",
                        rows: [
                            CalendarMenuRow(title: "No upcoming events", isEnabled: false, color: nil, action: nil)
                        ]
                    )
                ],
                footerRows: standardFooterRows
            )
        }

        let grouped = Dictionary(grouping: visibleEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }

        let sections = grouped.keys.sorted().map { day in
            CalendarMenuSection(
                title: DateFormatting.menuSectionTitle(for: day, now: now, calendar: calendar),
                rows: grouped[day, default: []].map { event in
                    CalendarMenuRow(
                        title: rowTitle(for: event),
                        isEnabled: false,
                        color: event.calendarColor,
                        action: nil
                    )
                }
            )
        }

        return CalendarMenuSnapshot(sections: sections, footerRows: standardFooterRows)
    }

    private func rowTitle(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "All day · \(event.title)"
        }

        return "\(DateFormatting.eventTime(event.startDate)) · \(event.title)"
    }

    private func menuItem(for row: CalendarMenuRow, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: selector(for: row.action), keyEquivalent: row.keyEquivalent)
        item.isEnabled = row.isEnabled
        item.target = target
        item.keyEquivalentModifierMask = row.keyEquivalentModifierMask

        if let color = row.color {
            item.image = MenuIconRenderer.colorBar(color: color, size: NSSize(width: 4, height: 14))
        }

        return item
    }

    private func selector(for action: CalendarMenuAction?) -> Selector? {
        switch action {
        case .requestAccess:
            return #selector(MenuBarController.requestCalendarAccess)
        case .openPrivacySettings:
            return #selector(MenuBarController.openCalendarPrivacySettings)
        case .openCalendar:
            return #selector(MenuBarController.openCalendarApp)
        case .openSettings:
            return #selector(MenuBarController.openSettings)
        case .quit:
            return #selector(MenuBarController.quit)
        case nil:
            return nil
        }
    }
}
