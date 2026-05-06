import AppKit
import Foundation

enum CalendarMenuAction: Equatable {
    case requestAccess
    case openPrivacySettings
    case openCalendar
    case openSettings
    case closeMenu
    case quit
}

struct CalendarMenuRow: Equatable {
    let title: String
    let isEnabled: Bool
    let color: NSColor?
    let action: CalendarMenuAction?
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let isHidden: Bool
    let allowsKeyEquivalentWhenHidden: Bool

    init(
        title: String,
        isEnabled: Bool,
        color: NSColor?,
        action: CalendarMenuAction?,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = [],
        isHidden: Bool = false,
        allowsKeyEquivalentWhenHidden: Bool = false
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.color = color
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifierMask = keyEquivalentModifierMask
        self.isHidden = isHidden
        self.allowsKeyEquivalentWhenHidden = allowsKeyEquivalentWhenHidden
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
            && lhs.isHidden == rhs.isHidden
            && lhs.allowsKeyEquivalentWhenHidden == rhs.allowsKeyEquivalentWhenHidden
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

final class TrayMenu: NSMenu {
    fileprivate static let significantModifierFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let item = items.first(where: { $0.matchesKeyEquivalent(event) }) {
            cancelTracking()
            performAction(for: item)
            return true
        }

        if items.contains(where: { $0.hasKeyEquivalentKey(for: event) }) {
            return false
        }

        return super.performKeyEquivalent(with: event)
    }

    private func performAction(for item: NSMenuItem) {
        guard let action = item.action else {
            return
        }

        NSApp.sendAction(action, to: item.target, from: item)
    }
}

private extension NSMenuItem {
    func hasKeyEquivalentKey(for event: NSEvent) -> Bool {
        event.type == .keyDown
            && !keyEquivalent.isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == keyEquivalent.lowercased()
    }

    func matchesKeyEquivalent(_ event: NSEvent) -> Bool {
        guard hasKeyEquivalentKey(for: event),
              isEnabled,
              (!isHidden || allowsKeyEquivalentWhenHidden),
              action != nil
        else {
            return false
        }

        let eventFlags = event.modifierFlags.intersection(TrayMenu.significantModifierFlags)
        let itemFlags = keyEquivalentModifierMask.intersection(TrayMenu.significantModifierFlags)
        return eventFlags == itemFlags
    }
}

struct MenuBuilder {
    func snapshot(
        accessState: CalendarAccessState,
        events: [CalendarEvent],
        globalShortcut: GlobalShortcut = .defaultValue,
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
                footerRows: standardFooterRows(globalShortcut: globalShortcut)
            )
        case .writeOnly, .denied, .restricted, .unknown:
            return CalendarMenuSnapshot(
                sections: [
                    CalendarMenuSection(
                        title: "",
                        rows: [
                            CalendarMenuRow(title: accessState.statusTitle, isEnabled: false, color: nil, action: nil),
                            CalendarMenuRow(title: accessState.statusDetail, isEnabled: false, color: nil, action: nil),
                            CalendarMenuRow(title: "Open Calendar Privacy Settings...", isEnabled: true, color: nil, action: .openPrivacySettings)
                        ]
                    )
                ],
                footerRows: standardFooterRows(globalShortcut: globalShortcut)
            )
        case .fullAccess:
            return eventsSnapshot(events: events, globalShortcut: globalShortcut, now: now, calendar: calendar)
        }
    }

    func makeMenu(from snapshot: CalendarMenuSnapshot, target: AnyObject) -> NSMenu {
        let menu = TrayMenu()

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

    private func standardFooterRows(globalShortcut: GlobalShortcut) -> [CalendarMenuRow] {
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
            // During NSMenu tracking, app-level hotkeys and local monitors are unreliable.
            // Keep this item hidden, but opt it into hidden key-equivalent matching.
            CalendarMenuRow(
                title: "Close Menu",
                isEnabled: true,
                color: nil,
                action: .closeMenu,
                keyEquivalent: globalShortcut.keyEquivalent,
                keyEquivalentModifierMask: globalShortcut.menuModifierFlags,
                isHidden: true,
                allowsKeyEquivalentWhenHidden: true
            ),
            CalendarMenuRow(title: "Quit Perch", isEnabled: true, color: nil, action: .quit)
        ]
    }

    private func eventsSnapshot(
        events: [CalendarEvent],
        globalShortcut: GlobalShortcut,
        now: Date,
        calendar: Calendar
    ) -> CalendarMenuSnapshot {
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
                footerRows: standardFooterRows(globalShortcut: globalShortcut)
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

        return CalendarMenuSnapshot(sections: sections, footerRows: standardFooterRows(globalShortcut: globalShortcut))
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
        item.isHidden = row.isHidden
        item.allowsKeyEquivalentWhenHidden = row.allowsKeyEquivalentWhenHidden

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
        case .closeMenu:
            return #selector(MenuBarController.closeTrayMenuFromMenuItem)
        case .quit:
            return #selector(MenuBarController.quit)
        case nil:
            return nil
        }
    }
}
