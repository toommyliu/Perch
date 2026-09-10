import AppKit
import Foundation

enum CalendarMenuAction: Equatable {
    case requestAccess
    case openPrivacySettings
    case openCalendar
    case openReminders
    case openEvent(eventIdentifier: String, startDate: Date)
    case hideEvent(CalendarEventOccurrence)
    case hideFromBar(CalendarEventOccurrence)
    case restoreEvent(CalendarEventOccurrence)
    case joinMeeting(MeetingLink)
    case copyMeetingLink(URL)
    case openSettings
    case closeMenu
    case quit
}

struct CalendarMenuRow: Equatable {
    let title: String
    let toolTip: String?
    let isEnabled: Bool
    let color: NSColor?
    let systemSymbolName: String?
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
        systemSymbolName: String? = nil,
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
        self.systemSymbolName = systemSymbolName
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
            && lhs.systemSymbolName == rhs.systemSymbolName
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
        if event.isUnmodifiedNumber {
            return activeActionMenu?.performKeyEquivalent(with: event) ?? false
        }

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

/// Number keys belong to the visible submenu; AppKit otherwise searches key equivalents in closed submenus too.
final class NumberedActionMenu: NSMenu, NSMenuDelegate {
    private(set) var isOpen = false

    override init(title: String) {
        super.init(title: title)
        delegate = self
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) { isOpen = true }
    func menuDidClose(_ menu: NSMenu) { isOpen = false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isOpen, event.isUnmodifiedNumber,
              let item = items.first(where: { $0.matchesKeyEquivalent(event) }),
              let action = item.action
        else { return false }

        var root: NSMenu = self
        while let parent = root.supermenu { root = parent }
        root.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
        return true
    }
}

private extension NSMenu {
    var activeActionMenu: NumberedActionMenu? {
        for item in items {
            if let active = item.submenu?.activeActionMenu { return active }
        }
        if let menu = self as? NumberedActionMenu, menu.isOpen { return menu }
        return nil
    }
}

private extension NSEvent {
    var isUnmodifiedNumber: Bool {
        type == .keyDown
            && modifierFlags.intersection(TrayMenu.significantModifierFlags).isEmpty
            && charactersIgnoringModifiers.map { $0.count == 1 && "123456789".contains($0) } == true
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
    private let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func snapshot(
        accessState: CalendarAccessState,
        events: [CalendarEvent],
        reminders: [CalendarReminder] = [],
        globalShortcut: GlobalShortcut = .defaultValue,
        showEventColors: Bool = true,
        showAllDayEvents: Bool = true,
        showReminders: Bool = false,
        selectedCalendarIdentifiers: Set<String>? = nil,
        hiddenEvents: [HiddenCalendarEvent] = [],
        displayMode: MenuBarDisplayMode = .within6Hours,
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
            return agendaSnapshot(
                events: events,
                reminders: reminders,
                globalShortcut: globalShortcut,
                showEventColors: showEventColors,
                showAllDayEvents: showAllDayEvents,
                showReminders: showReminders,
                selectedCalendarIdentifiers: selectedCalendarIdentifiers,
                hiddenEvents: hiddenEvents.filter { $0.endDate > now },
                displayMode: displayMode,
                now: now,
                calendar: calendar
            )
        }
    }

    func makeMenu(from snapshot: CalendarMenuSnapshot, target: AnyObject) -> NSMenu {
        let menu = TrayMenu()
        menu.minimumWidth = 272

        for section in snapshot.sections {
            if !section.title.isEmpty {
                let header = NSMenuItem.sectionHeader(title: section.title)
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
            .separator,
            CalendarMenuRow(
                title: "Quit Perch Completely",
                isEnabled: true,
                color: nil,
                action: .quit,
                keyEquivalent: "q",
                keyEquivalentModifierMask: [.command]
            )
        ]
    }

    private func agendaSnapshot(
        events: [CalendarEvent],
        reminders: [CalendarReminder],
        globalShortcut: GlobalShortcut,
        showEventColors: Bool,
        showAllDayEvents: Bool,
        showReminders: Bool,
        selectedCalendarIdentifiers: Set<String>?,
        hiddenEvents: [HiddenCalendarEvent],
        displayMode: MenuBarDisplayMode,
        now: Date,
        calendar: Calendar
    ) -> CalendarMenuSnapshot {
        let completelyHiddenEvents = hiddenEvents.filter { $0.scope == .completely }
        let barHiddenOccurrences = Set(hiddenEvents.filter { $0.scope == .bar }.map(\.occurrence))
        let visibleItems = AgendaItemVisibility.visibleItems(
            events: events,
            reminders: reminders,
            includeAllDayEvents: showAllDayEvents,
            includeReminders: showReminders,
            selectedCalendarIdentifiers: selectedCalendarIdentifiers,
            hiddenOccurrences: Set(completelyHiddenEvents.map(\.occurrence)),
            now: now,
            calendar: calendar
        )

        if visibleItems.isEmpty {
            let emptyTitle: String
            if selectedCalendarIdentifiers?.isEmpty == true {
                emptyTitle = "No calendars selected"
            } else if showReminders {
                emptyTitle = "No upcoming events or reminders"
            } else {
                emptyTitle = "No upcoming events"
            }

            return CalendarMenuSnapshot(
                sections: [
                    CalendarMenuSection(
                        title: "",
                        rows: [
                            CalendarMenuRow(title: emptyTitle, isEnabled: false, color: nil, action: nil)
                        ]
                    )
                ],
                footerRows: hiddenEventRows(completelyHiddenEvents, now: now, calendar: calendar)
                    + standardFooterRows(globalShortcut: globalShortcut)
            )
        }

        let prioritizedIndex = AgendaItemVisibility.prioritizedIndex(
            in: visibleItems,
            displayMode: displayMode,
            excludingOccurrences: barHiddenOccurrences,
            now: now
        )
        let prioritizedItem = prioritizedIndex.map { visibleItems[$0] }
        var remainingItems = visibleItems
        if let prioritizedIndex {
            remainingItems.remove(at: prioritizedIndex)
        }

        let grouped = Dictionary(grouping: remainingItems) { item in
            calendar.startOfDay(for: item.date)
        }

        var sections = grouped.keys.sorted().map { day in
            CalendarMenuSection(
                title: DateFormatting.menuSectionTitle(
                    for: day,
                    now: now,
                    calendar: calendar,
                    locale: locale
                ),
                rows: grouped[day, default: []].flatMap { item in
                    rows(for: item, showEventColors: showEventColors, barHiddenOccurrences: barHiddenOccurrences, calendar: calendar)
                }
            )
        }

        if let prioritizedItem {
            sections.insert(
                CalendarMenuSection(
                    title: upcomingSectionTitle(for: prioritizedItem, now: now, calendar: calendar),
                    rows: rows(for: prioritizedItem, showEventColors: showEventColors, barHiddenOccurrences: barHiddenOccurrences, calendar: calendar)
                ),
                at: 0
            )
        }

        return CalendarMenuSnapshot(
            sections: sections,
            footerRows: hiddenEventRows(completelyHiddenEvents, now: now, calendar: calendar)
                + standardFooterRows(globalShortcut: globalShortcut)
        )
    }

    private func hiddenEventRows(_ events: [HiddenCalendarEvent], now: Date, calendar: Calendar) -> [CalendarMenuRow] {
        guard !events.isEmpty else { return [] }
        return [CalendarMenuRow(
            title: "Hidden Events (\(events.count))",
            isEnabled: true,
            color: nil,
            action: nil,
            submenuRows: events.map { event in
                let day = DateFormatting.menuSectionTitle(
                    for: event.occurrence.startDate, now: now, calendar: calendar, locale: locale
                )
                return CalendarMenuRow(
                    title: "\(day) · \(EventTitleTruncator.truncate(event.title, maxLength: maxEventTitleLength))",
                    toolTip: event.title,
                    isEnabled: true,
                    color: nil,
                    action: nil,
                    submenuRows: [CalendarMenuRow(
                        title: "Show Again", isEnabled: true, color: nil,
                        action: .restoreEvent(event.occurrence)
                    )]
                )
            }
        )]
    }

    private func rows(
        for event: CalendarEvent,
        showEventColors: Bool,
        isHiddenFromBar: Bool,
        calendar: Calendar
    ) -> [CalendarMenuRow] {
        let openEventAction = CalendarMenuAction.openEvent(eventIdentifier: event.id, startDate: event.startDate)
        let rowTitle = rowTitle(for: event, calendar: calendar)
        let fullRowTitle = fullRowTitle(for: event, calendar: calendar)
        let rowToolTip = rowTitle == fullRowTitle ? nil : fullRowTitle
        var actions: [CalendarMenuRow] = []
        if let meetingLink = event.meetingLink {
            actions = [
                CalendarMenuRow(
                    title: "Join \(meetingLink.provider.displayName)",
                    isEnabled: true,
                    color: nil,
                    action: .joinMeeting(meetingLink)
                ),
                CalendarMenuRow(
                    title: "Copy Meeting Link",
                    isEnabled: true,
                    color: nil,
                    action: .copyMeetingLink(meetingLink.url)
                ),
                .separator
            ]
        }
        actions += [
            CalendarMenuRow(title: "Show in Calendar", isEnabled: true, color: nil, action: openEventAction),
            .separator,
            CalendarMenuRow(
                title: isHiddenFromBar ? "Show in menu bar" : "Hide from menu bar", isEnabled: true, color: nil,
                action: isHiddenFromBar
                    ? .restoreEvent(CalendarEventOccurrence(event: event))
                    : .hideFromBar(CalendarEventOccurrence(event: event))
            ),
            CalendarMenuRow(
                title: "Hide completely", isEnabled: true, color: nil,
                action: .hideEvent(CalendarEventOccurrence(event: event))
            )
        ]

        return [CalendarMenuRow(
            title: rowTitle,
            toolTip: rowToolTip,
            isEnabled: true,
            color: showEventColors ? event.calendarColor : .perchMutedWhite,
            action: nil,
            submenuRows: actions
        )]
    }

    private func row(for reminder: CalendarReminder, calendar: Calendar) -> CalendarMenuRow {
        let rowTitle = rowTitle(for: reminder, calendar: calendar)
        let fullRowTitle = fullRowTitle(for: reminder, calendar: calendar)

        return CalendarMenuRow(
            title: rowTitle,
            toolTip: rowTitle == fullRowTitle ? nil : fullRowTitle,
            isEnabled: true,
            color: nil,
            systemSymbolName: "circle",
            action: .openReminders
        )
    }

    private func rows(
        for item: AgendaItem,
        showEventColors: Bool,
        barHiddenOccurrences: Set<CalendarEventOccurrence>,
        calendar: Calendar
    ) -> [CalendarMenuRow] {
        switch item {
        case let .event(event):
            rows(
                for: event, showEventColors: showEventColors,
                isHiddenFromBar: barHiddenOccurrences.contains(CalendarEventOccurrence(event: event)), calendar: calendar
            )
        case let .reminder(reminder):
            [row(for: reminder, calendar: calendar)]
        }
    }

    private func upcomingSectionTitle(
        for item: AgendaItem,
        now: Date,
        calendar: Calendar
    ) -> String {
        switch item {
        case let .event(event):
            if event.startDate <= now && event.endDate >= now {
                return "Ending in \(menuDuration(event.endDate.timeIntervalSince(now)))"
            }
            return "Upcoming in \(menuDuration(event.startDate.timeIntervalSince(now)))"

        case let .reminder(reminder):
            if reminder.isAllDay, calendar.isDate(reminder.dueDate, inSameDayAs: now) {
                return "Due today"
            }
            if reminder.dueDate <= now {
                let elapsed = now.timeIntervalSince(reminder.dueDate)
                return elapsed < 60 ? "Due now" : "Overdue by \(menuDuration(elapsed))"
            }
            return "Due in \(menuDuration(reminder.dueDate.timeIntervalSince(now)))"
        }
    }

    private func menuDuration(_ timeInterval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(timeInterval / 60))
        let days = totalMinutes / (24 * 60)
        if days > 0 {
            let hours = (totalMinutes % (24 * 60)) / 60
            return hours == 0 ? "\(days) d" : "\(days) d \(hours) h"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    private func rowTitle(for event: CalendarEvent, calendar: Calendar) -> String {
        let title = EventTitleTruncator.truncate(event.title, maxLength: maxEventTitleLength)
        return fullRowTitle(for: event, title: title, calendar: calendar)
    }

    private func fullRowTitle(for event: CalendarEvent, calendar: Calendar) -> String {
        fullRowTitle(for: event, title: event.title, calendar: calendar)
    }

    private func fullRowTitle(
        for event: CalendarEvent,
        title: String,
        calendar: Calendar
    ) -> String {
        if event.isAllDay {
            return "All-day · \(title)"
        }

        return "\(DateFormatting.eventTime(event.startDate, locale: locale, calendar: calendar)) · \(title)"
    }

    private func rowTitle(for reminder: CalendarReminder, calendar: Calendar) -> String {
        let title = EventTitleTruncator.truncate(reminder.title, maxLength: maxEventTitleLength)
        return fullRowTitle(for: reminder, title: title, calendar: calendar)
    }

    private func fullRowTitle(for reminder: CalendarReminder, calendar: Calendar) -> String {
        fullRowTitle(for: reminder, title: reminder.title, calendar: calendar)
    }

    private func fullRowTitle(
        for reminder: CalendarReminder,
        title: String,
        calendar: Calendar
    ) -> String {
        if reminder.isAllDay {
            return "All-day · \(title)"
        }

        return "\(DateFormatting.eventTime(reminder.dueDate, locale: locale, calendar: calendar)) · \(title)"
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

        if let systemSymbolName = row.systemSymbolName {
            item.image = NSImage(
                systemSymbolName: systemSymbolName,
                accessibilityDescription: "Reminder"
            )
        } else if let color = row.color {
            item.image = MenuIconRenderer.colorBar(color: color, size: NSSize(width: 4, height: 14))
        }
        if !row.submenuRows.isEmpty {
            let submenu = NumberedActionMenu(title: row.title)
            var shortcutNumber = 1
            for submenuRow in row.submenuRows {
                let submenuItem = menuItem(for: submenuRow, target: target)
                if !submenuRow.isSeparator, !submenuRow.isHidden, submenuRow.isEnabled,
                   submenuRow.action != nil, shortcutNumber <= 9 {
                    submenuItem.keyEquivalent = String(shortcutNumber)
                    submenuItem.keyEquivalentModifierMask = []
                    shortcutNumber += 1
                }
                submenu.addItem(submenuItem)
            }
            item.submenu = submenu
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
        case .openReminders:
            return #selector(MenuBarController.openRemindersApp)
        case .openEvent:
            return #selector(MenuBarController.openCalendarEvent(_:))
        case .hideEvent:
            return #selector(MenuBarController.hideCalendarEvent(_:))
        case .hideFromBar:
            return #selector(MenuBarController.hideCalendarEvent(_:))
        case .restoreEvent:
            return #selector(MenuBarController.restoreCalendarEvent(_:))
        case .joinMeeting:
            return #selector(MenuBarController.joinMeetingFromMenu(_:))
        case .copyMeetingLink:
            return #selector(MenuBarController.copyMeetingLink(_:))
        case .openSettings:
            return #selector(MenuBarController.performSettingsMenuAction)
        case .closeMenu:
            return #selector(MenuBarController.closeTrayMenuFromMenuItem)
        case .quit:
            return #selector(MenuBarController.quit)
        case nil:
            return nil
        }
    }
}
