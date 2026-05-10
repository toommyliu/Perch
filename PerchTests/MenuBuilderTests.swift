import AppKit
import XCTest
@testable import Perch

final class MenuBuilderTests: XCTestCase {
    private let builder = MenuBuilder()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func testEventsGroupIntoTodayTomorrowAndDateHeadings() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0)),
            event(title: "Tomorrow Event", start: date(day: 7, hour: 10, minute: 0), end: date(day: 7, hour: 11, minute: 0)),
            event(title: "Later Event", start: date(day: 8, hour: 10, minute: 0), end: date(day: 8, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.map(\.title), ["Today", "Tomorrow", "Fri May 8"])
    }

    func testPastEndedEventsAreExcludedAndOngoingEventsRemainVisible() {
        let now = date(day: 6, hour: 9, minute: 30)
        let events = [
            event(title: "Past", start: date(day: 6, hour: 8, minute: 0), end: date(day: 6, hour: 9, minute: 0)),
            event(title: "Current", start: date(day: 6, hour: 9, minute: 0), end: date(day: 6, hour: 10, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["9:00 AM · Current"])
    }

    func testAllDayRowsFormatAsAllDayTitle() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "all-day",
                title: "Conference",
                startDate: date(day: 6, hour: 0, minute: 0),
                endDate: date(day: 7, hour: 0, minute: 0),
                isAllDay: true,
                calendarTitle: "School",
                calendarColor: .systemRed
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "All day · Conference")
    }

    func testLongTimedEventTitleTruncatesNameButKeepsTimePrefix() {
        let now = date(day: 6, hour: 9, minute: 0)
        let longTitle = "12345678901234567890123456789012345678901234567890"
        let events = [
            event(title: longTitle, start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "10:00 AM · 123456789012345678901234567890123456789012345...")
        XCTAssertEqual(snapshot.sections[0].rows[0].toolTip, "10:00 AM · \(longTitle)")
    }

    func testLongAllDayEventTitleTruncatesNameButKeepsAllDayPrefix() {
        let now = date(day: 6, hour: 9, minute: 0)
        let longTitle = "12345678901234567890123456789012345678901234567890"
        let events = [
            CalendarEvent(
                id: "all-day",
                title: longTitle,
                startDate: date(day: 6, hour: 0, minute: 0),
                endDate: date(day: 7, hour: 0, minute: 0),
                isAllDay: true,
                calendarTitle: "School",
                calendarColor: .systemRed
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "All day · 123456789012345678901234567890123456789012345...")
        XCTAssertEqual(snapshot.sections[0].rows[0].toolTip, "All day · \(longTitle)")
    }

    func testAllDayRowsAreExcludedWhenDisabled() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "all-day",
                title: "Conference",
                startDate: date(day: 6, hour: 0, minute: 0),
                endDate: date(day: 7, hour: 0, minute: 0),
                isAllDay: true,
                calendarTitle: "School",
                calendarColor: .systemRed
            ),
            event(title: "Timed", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            showAllDayEvents: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00 AM · Timed"])
    }

    func testEventRowsUseMutedWhiteColorWhenCalendarColorsAreDisabled() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            showEventColors: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections[0].rows[0].color, .perchMutedWhite)
    }

    func testEventRowsAreEnabledAndOpenCalendarEvent() {
        let now = date(day: 6, hour: 9, minute: 0)
        let startDate = date(day: 6, hour: 10, minute: 0)
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Today Event",
                startDate: startDate,
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertTrue(snapshot.sections[0].rows[0].isEnabled)
        XCTAssertEqual(
            snapshot.sections[0].rows[0].action,
            .openEvent(eventIdentifier: "calendar-item-id", startDate: startDate)
        )
    }

    func testZoomEventRowsExposeActionsSubmenu() {
        let now = date(day: 6, hour: 9, minute: 0)
        let startDate = date(day: 6, hour: 10, minute: 0)
        let zoomURL = URL(string: "https://school.zoom.us/j/1234567890?pwd=abc")!
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: startDate,
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                zoomMeetingURL: zoomURL,
                responseStatus: .maybe
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let row = snapshot.sections[0].rows[0]
        let inlineJoinRow = snapshot.sections[0].rows[1]

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00 AM · Office Hours", "Join Zoom Meeting"])
        XCTAssertTrue(row.isEnabled)
        XCTAssertNil(row.action)
        XCTAssertEqual(row.submenuRows.filter { !$0.isSeparator }.map(\.title), [
            "Join Zoom Meeting",
            "Update response",
            "Yes",
            "No",
            "Maybe",
            "Show in Calendar"
        ])
        XCTAssertEqual(row.submenuRows[0].action, .joinZoomMeeting(zoomURL))
        XCTAssertEqual(row.submenuRows[0].keyEquivalent, "j")
        XCTAssertNil(row.submenuRows[0].icon)
        XCTAssertTrue(row.submenuRows[1].isSeparator)
        XCTAssertFalse(row.submenuRows[2].isEnabled)
        XCTAssertFalse(row.submenuRows[3].isEnabled)
        XCTAssertFalse(row.submenuRows[4].isEnabled)
        XCTAssertFalse(row.submenuRows[5].isEnabled)
        XCTAssertFalse(row.submenuRows[3].isSelected)
        XCTAssertFalse(row.submenuRows[4].isSelected)
        XCTAssertTrue(row.submenuRows[5].isSelected)
        XCTAssertTrue(row.submenuRows[6].isSeparator)
        XCTAssertEqual(row.submenuRows[7].action, .openEvent(eventIdentifier: "calendar-item-id", startDate: startDate))
        XCTAssertEqual(inlineJoinRow.icon, .zoom)
        XCTAssertEqual(inlineJoinRow.action, .joinZoomMeeting(zoomURL))
    }

    func testEmptyAuthorizedStateShowsNoUpcomingEvents() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "No upcoming events")
        XCTAssertFalse(snapshot.sections[0].rows[0].isEnabled)
    }

    func testDeniedStateShowsPrivacySettingsActions() {
        let snapshot = builder.snapshot(accessState: .denied, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), [
            "Calendar access denied",
            "Enable calendar access in System Settings to show upcoming events.",
            "Open Calendar Privacy Settings..."
        ])
        XCTAssertEqual(snapshot.sections[0].rows[2].action, .openPrivacySettings)
    }

    func testWriteOnlyStateShowsFullAccessRequiredAction() {
        let snapshot = builder.snapshot(accessState: .writeOnly, events: [], now: Date(), calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), [
            "Full calendar access required",
            "Perch can only write calendar events. Enable full access in System Settings so it can read upcoming events.",
            "Open Calendar Privacy Settings..."
        ])
        XCTAssertEqual(snapshot.sections[0].rows[2].action, .openPrivacySettings)
    }

    func testFooterRowsExposeMenuKeyEquivalents() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)
        let visibleFooterRows = snapshot.footerRows.filter { !$0.isHidden }

        XCTAssertEqual(visibleFooterRows.map(\.title), ["Open Calendar", "Settings...", "Quit Perch"])
        XCTAssertEqual(visibleFooterRows[0].keyEquivalent, "1")
        XCTAssertEqual(visibleFooterRows[0].keyEquivalentModifierMask, [.command])

        XCTAssertEqual(visibleFooterRows[1].keyEquivalent, ",")
        XCTAssertEqual(visibleFooterRows[1].keyEquivalentModifierMask, [.command])
    }

    func testCloseMenuShortcutRowIsHiddenButAllowsKeyEquivalent() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)

        let closeRow = snapshot.footerRows.first { $0.action == .closeMenu }
        XCTAssertEqual(closeRow?.title, "Close Menu")
        XCTAssertEqual(closeRow?.keyEquivalent, GlobalShortcut.defaultValue.keyEquivalent)
        XCTAssertEqual(closeRow?.keyEquivalentModifierMask, GlobalShortcut.defaultValue.menuModifierFlags)
        XCTAssertEqual(closeRow?.isHidden, true)
        XCTAssertEqual(closeRow?.allowsKeyEquivalentWhenHidden, true)
    }

    func testCloseMenuShortcutRowUsesConfiguredShortcut() {
        let shortcut = GlobalShortcut(
            keyEquivalent: "p",
            keyCode: 35,
            modifiers: [.option, .command]
        )
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], globalShortcut: shortcut, now: Date(), calendar: calendar)

        let closeRow = snapshot.footerRows.first { $0.action == .closeMenu }
        XCTAssertEqual(closeRow?.keyEquivalent, "p")
        XCTAssertEqual(closeRow?.keyEquivalentModifierMask, [.option, .command])
    }

    @MainActor
    func testMenuPerformsCommandOneWhileOpen() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        XCTAssertTrue(menu.performKeyEquivalent(with: keyEvent(characters: "1", modifierFlags: [.command])))
        XCTAssertEqual(target.openCalendarCount, 1)
        XCTAssertEqual(target.openSettingsCount, 0)
    }

    @MainActor
    func testMenuPerformsCommandCommaWhileOpen() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        XCTAssertTrue(menu.performKeyEquivalent(with: keyEvent(characters: ",", modifierFlags: [.command])))
        XCTAssertEqual(target.openCalendarCount, 0)
        XCTAssertEqual(target.openSettingsCount, 1)
    }

    @MainActor
    func testMenuItemPerformsOpenCalendarEvent() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.performActionForItem(at: 1)

        XCTAssertEqual(target.openCalendarEventCount, 1)
    }

    @MainActor
    func testMenuItemUsesRowTooltip() {
        let now = date(day: 6, hour: 9, minute: 0)
        let longTitle = "12345678901234567890123456789012345678901234567890"
        let events = [
            event(title: longTitle, start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let menu = builder.makeMenu(from: snapshot, target: MenuShortcutTarget())

        XCTAssertEqual(menu.item(at: 1)?.toolTip, "10:00 AM · \(longTitle)")
    }

    @MainActor
    func testZoomSubmenuPerformsJoinZoomMeeting() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                zoomMeetingURL: URL(string: "https://school.zoom.us/j/1234567890")!
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 0)

        XCTAssertEqual(target.joinZoomMeetingCount, 1)
        XCTAssertEqual(target.openCalendarEventCount, 0)
    }

    @MainActor
    func testZoomInlineRowPerformsJoinZoomMeeting() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                zoomMeetingURL: URL(string: "https://school.zoom.us/j/1234567890")!
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.performActionForItem(at: 2)

        XCTAssertEqual(target.joinZoomMeetingCount, 1)
        XCTAssertEqual(target.openCalendarEventCount, 0)
    }

    @MainActor
    func testZoomSubmenuPerformsShowInCalendar() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                zoomMeetingURL: URL(string: "https://school.zoom.us/j/1234567890")!
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 7)

        XCTAssertEqual(target.openCalendarEventCount, 1)
        XCTAssertEqual(target.joinZoomMeetingCount, 0)
    }

    @MainActor
    func testZoomSubmenuShowsSelectedResponseAsReadOnlyMenuState() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                zoomMeetingURL: URL(string: "https://school.zoom.us/j/1234567890")!,
                responseStatus: .yes
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let menu = builder.makeMenu(from: snapshot, target: MenuShortcutTarget())
        let submenu = menu.item(at: 1)?.submenu

        XCTAssertEqual(submenu?.item(at: 3)?.title, "Yes")
        XCTAssertFalse(submenu?.item(at: 3)?.isEnabled ?? true)
        XCTAssertEqual(submenu?.item(at: 3)?.state, .on)
        XCTAssertEqual(submenu?.item(at: 4)?.state, .off)
        XCTAssertEqual(submenu?.item(at: 5)?.state, .off)
    }

    @MainActor
    func testMenuShortcutIgnoresCapsLockButRejectsExtraMeaningfulModifiers() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        XCTAssertTrue(menu.performKeyEquivalent(with: keyEvent(characters: ",", modifierFlags: [.command, .capsLock])))
        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: ",", modifierFlags: [.command, .shift])))
        XCTAssertEqual(target.openSettingsCount, 1)
    }

    @MainActor
    func testMenuPerformsConfiguredCloseShortcutWhileOpen() {
        let shortcut = GlobalShortcut(
            keyEquivalent: "p",
            keyCode: 35,
            modifiers: [.option, .command]
        )
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], globalShortcut: shortcut, now: Date(), calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        XCTAssertTrue(menu.performKeyEquivalent(with: keyEvent(characters: "p", modifierFlags: [.option, .command])))
        XCTAssertTrue(menu.performKeyEquivalent(with: keyEvent(characters: "p", modifierFlags: [.option, .command, .capsLock])))
        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: "p", modifierFlags: [.option, .command, .shift])))
        XCTAssertEqual(target.closeMenuCount, 2)
    }

    private func event(title: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarTitle: "School",
            calendarColor: .systemBlue
        )
    }

    private func date(day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 5
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private func keyEvent(characters: String, modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}

private final class MenuShortcutTarget: NSObject {
    private(set) var openCalendarCount = 0
    private(set) var openCalendarEventCount = 0
    private(set) var joinZoomMeetingCount = 0
    private(set) var openSettingsCount = 0
    private(set) var closeMenuCount = 0

    @objc func openCalendarApp() {
        openCalendarCount += 1
    }

    @objc func openCalendarEvent(_ sender: NSMenuItem) {
        openCalendarEventCount += 1
    }

    @objc func joinZoomMeeting(_ sender: NSMenuItem) {
        joinZoomMeetingCount += 1
    }

    @objc func openSettings() {
        openSettingsCount += 1
    }

    @objc func closeTrayMenuFromMenuItem() {
        closeMenuCount += 1
    }
}
