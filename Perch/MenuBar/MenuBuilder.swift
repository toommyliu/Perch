import AppKit
import Foundation

enum CalendarMenuAction: Equatable {
    case requestAccess
    case openPrivacySettings
    case openCalendar
    case openEvent(eventIdentifier: String, startDate: Date)
    case joinZoomMeeting(URL)
    case openSettings
    case closeMenu
    case quit
}

enum CalendarMenuIcon: Equatable {
    case zoom
}

struct CalendarMenuRow: Equatable {
    let title: String
    let toolTip: String?
    let isEnabled: Bool
    let color: NSColor?
    let icon: CalendarMenuIcon?
    let action: CalendarMenuAction?
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let isHidden: Bool
    let allowsKeyEquivalentWhenHidden: Bool
    let isSeparator: Bool
    let isSelected: Bool
    let submenuRows: [CalendarMenuRow]

    init(
        title: String,
        toolTip: String? = nil,
        isEnabled: Bool,
        color: NSColor?,
        icon: CalendarMenuIcon? = nil,
        action: CalendarMenuAction?,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = [],
        isHidden: Bool = false,
        allowsKeyEquivalentWhenHidden: Bool = false,
        isSeparator: Bool = false,
        isSelected: Bool = false,
        submenuRows: [CalendarMenuRow] = []
    ) {
        self.title = title
        self.toolTip = toolTip
        self.isEnabled = isEnabled
        self.color = color
        self.icon = icon
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifierMask = keyEquivalentModifierMask
        self.isHidden = isHidden
        self.allowsKeyEquivalentWhenHidden = allowsKeyEquivalentWhenHidden
        self.isSeparator = isSeparator
        self.isSelected = isSelected
        self.submenuRows = submenuRows
    }

    static var separator: CalendarMenuRow {
        CalendarMenuRow(title: "", isEnabled: false, color: nil, action: nil, isSeparator: true)
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
            && lhs.toolTip == rhs.toolTip
            && lhs.isEnabled == rhs.isEnabled
            && colorsMatch
            && lhs.icon == rhs.icon
            && lhs.action == rhs.action
            && lhs.keyEquivalent == rhs.keyEquivalent
            && lhs.keyEquivalentModifierMask == rhs.keyEquivalentModifierMask
            && lhs.isHidden == rhs.isHidden
            && lhs.allowsKeyEquivalentWhenHidden == rhs.allowsKeyEquivalentWhenHidden
            && lhs.isSeparator == rhs.isSeparator
            && lhs.isSelected == rhs.isSelected
            && lhs.submenuRows == rhs.submenuRows
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
    private let maxEventTitleLength = 48

    func snapshot(
        accessState: CalendarAccessState,
        events: [CalendarEvent],
        globalShortcut: GlobalShortcut = .defaultValue,
        showEventColors: Bool = true,
        showAllDayEvents: Bool = true,
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
            return eventsSnapshot(
                events: events,
                globalShortcut: globalShortcut,
                showEventColors: showEventColors,
                showAllDayEvents: showAllDayEvents,
                now: now,
                calendar: calendar
            )
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
        showEventColors: Bool,
        showAllDayEvents: Bool,
        now: Date,
        calendar: Calendar
    ) -> CalendarMenuSnapshot {
        let visibleEvents = CalendarEventVisibility.upcomingEvents(
            from: events,
            includeAllDayEvents: showAllDayEvents,
            now: now
        )

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
                rows: grouped[day, default: []].flatMap { event in
                    rows(for: event, showEventColors: showEventColors)
                }
            )
        }

        return CalendarMenuSnapshot(
            sections: sections,
            footerRows: standardFooterRows(globalShortcut: globalShortcut)
        )
    }

    private func rows(for event: CalendarEvent, showEventColors: Bool) -> [CalendarMenuRow] {
        let openEventAction = CalendarMenuAction.openEvent(eventIdentifier: event.id, startDate: event.startDate)
        let rowTitle = rowTitle(for: event)
        let fullRowTitle = fullRowTitle(for: event)
        let rowToolTip = rowTitle == fullRowTitle ? nil : fullRowTitle
        let eventRow = CalendarMenuRow(
            title: rowTitle,
            toolTip: rowToolTip,
            isEnabled: true,
            color: showEventColors ? event.calendarColor : .perchMutedWhite,
            action: openEventAction
        )

        guard let zoomMeetingURL = event.zoomMeetingURL else {
            return [eventRow]
        }

        let zoomEventRow = CalendarMenuRow(
            title: rowTitle,
            toolTip: rowToolTip,
            isEnabled: true,
            color: showEventColors ? event.calendarColor : .perchMutedWhite,
            action: nil,
            submenuRows: [
                CalendarMenuRow(
                    title: "Join Zoom Meeting",
                    isEnabled: true,
                    color: nil,
                    action: .joinZoomMeeting(zoomMeetingURL),
                    keyEquivalent: "j"
                ),
                .separator,
                CalendarMenuRow(title: "Update response", isEnabled: false, color: nil, action: nil),
                CalendarMenuRow(
                    title: "Yes",
                    isEnabled: false,
                    color: nil,
                    action: nil,
                    keyEquivalent: "y",
                    isSelected: event.responseStatus == .yes
                ),
                CalendarMenuRow(
                    title: "No",
                    isEnabled: false,
                    color: nil,
                    action: nil,
                    keyEquivalent: "n",
                    isSelected: event.responseStatus == .no
                ),
                CalendarMenuRow(
                    title: "Maybe",
                    isEnabled: false,
                    color: nil,
                    action: nil,
                    keyEquivalent: "m",
                    isSelected: event.responseStatus == .maybe
                ),
                .separator,
                CalendarMenuRow(title: "Show in Calendar", isEnabled: true, color: nil, action: openEventAction)
            ]
        )

        return [
            zoomEventRow,
            CalendarMenuRow(
                title: "Join Zoom Meeting",
                isEnabled: true,
                color: nil,
                icon: .zoom,
                action: .joinZoomMeeting(zoomMeetingURL)
            )
        ]
    }

    private func rowTitle(for event: CalendarEvent) -> String {
        let title = EventTitleTruncator.truncate(event.title, maxLength: maxEventTitleLength)
        return fullRowTitle(for: event, title: title)
    }

    private func fullRowTitle(for event: CalendarEvent) -> String {
        fullRowTitle(for: event, title: event.title)
    }

    private func fullRowTitle(for event: CalendarEvent, title: String) -> String {
        if event.isAllDay {
            return "All day · \(title)"
        }

        return "\(DateFormatting.eventTime(event.startDate)) · \(title)"
    }

    private func menuItem(for row: CalendarMenuRow, target: AnyObject) -> NSMenuItem {
        if row.isSeparator {
            return .separator()
        }

        let item = NSMenuItem(title: row.title, action: selector(for: row.action), keyEquivalent: row.keyEquivalent)
        item.isEnabled = row.isEnabled
        item.target = target
        item.keyEquivalentModifierMask = row.keyEquivalentModifierMask
        item.isHidden = row.isHidden
        item.allowsKeyEquivalentWhenHidden = row.allowsKeyEquivalentWhenHidden
        item.state = row.isSelected ? .on : .off
        item.representedObject = row.action
        item.toolTip = row.toolTip

        if let icon = row.icon {
            item.image = image(for: icon)
        } else if let color = row.color {
            item.image = MenuIconRenderer.colorBar(color: color, size: NSSize(width: 4, height: 14))
        }

        if !row.submenuRows.isEmpty {
            let submenu = NSMenu()
            for submenuRow in row.submenuRows {
                submenu.addItem(menuItem(for: submenuRow, target: target))
            }
            item.submenu = submenu
        }

        return item
    }

    private func image(for icon: CalendarMenuIcon) -> NSImage {
        switch icon {
        case .zoom:
            return MenuIconRenderer.zoomIcon()
        }
    }

    private func selector(for action: CalendarMenuAction?) -> Selector? {
        switch action {
        case .requestAccess:
            return #selector(MenuBarController.requestCalendarAccess)
        case .openPrivacySettings:
            return #selector(MenuBarController.openCalendarPrivacySettings)
        case .openCalendar:
            return #selector(MenuBarController.openCalendarApp)
        case .openEvent:
            return #selector(MenuBarController.openCalendarEvent(_:))
        case .joinZoomMeeting:
            return #selector(MenuBarController.joinZoomMeeting(_:))
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
