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
    private(set) var openSettingsCount = 0
    private(set) var closeMenuCount = 0

    @objc func openCalendarApp() {
        openCalendarCount += 1
    }

    @objc func openSettings() {
        openSettingsCount += 1
    }

    @objc func closeTrayMenuFromMenuItem() {
        closeMenuCount += 1
    }
}
