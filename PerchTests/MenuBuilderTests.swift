import AppKit
import XCTest
@testable import Perch

final class MenuBuilderTests: XCTestCase {
    private let builder = MenuBuilder(locale: Locale(identifier: "en_US@hours=h12"))
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func testNextEventIsPrioritizedBeforeDayGroups() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0)),
            event(title: "Later Today", start: date(day: 6, hour: 13, minute: 0), end: date(day: 6, hour: 14, minute: 0)),
            event(title: "Tomorrow Event", start: date(day: 7, hour: 10, minute: 0), end: date(day: 7, hour: 11, minute: 0)),
            event(title: "Later Event", start: date(day: 8, hour: 10, minute: 0), end: date(day: 8, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.map(\.title), ["Upcoming in 1 h", "Today", "Tomorrow", "Fri, May 8"])
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00\u{202F}AM · Today Event"])
    }

    func testPrioritizingRecurringOccurrenceKeepsLaterOccurrencesWithSameIdentifier() {
        let now = date(day: 6, hour: 9, minute: 0)
        let recurringIdentifier = "daily-standup"
        let events = [
            CalendarEvent(
                id: recurringIdentifier,
                title: "Daily Standup",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 10, minute: 30),
                isAllDay: false,
                calendarTitle: "Work",
                calendarColor: .systemBlue
            ),
            CalendarEvent(
                id: recurringIdentifier,
                title: "Daily Standup",
                startDate: date(day: 7, hour: 10, minute: 0),
                endDate: date(day: 7, hour: 10, minute: 30),
                isAllDay: false,
                calendarTitle: "Work",
                calendarColor: .systemBlue
            )
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections.map(\.title), ["Upcoming in 1 h", "Tomorrow"])
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00\u{202F}AM · Daily Standup"])
        XCTAssertEqual(snapshot.sections[1].rows.map(\.title), ["10:00\u{202F}AM · Daily Standup"])
    }

    func testNeverDisplayModeLeavesEventsInDayGroups() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Today Event", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            displayMode: .never,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections.map(\.title), ["Today"])
    }

    func testPastEndedEventsAreExcludedAndOngoingEventsRemainVisible() {
        let now = date(day: 6, hour: 9, minute: 30)
        let events = [
            event(title: "Past", start: date(day: 6, hour: 8, minute: 0), end: date(day: 6, hour: 9, minute: 0)),
            event(title: "Current", start: date(day: 6, hour: 9, minute: 0), end: date(day: 6, hour: 10, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(snapshot.sections[0].title, "Ending in 30 min")
        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["9:00\u{202F}AM · Current"])
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

        XCTAssertEqual(snapshot.sections[0].title, "Ending in 15 h")
        XCTAssertEqual(snapshot.sections[0].rows[0].title, "All-day · Conference")
    }

    func testLongTimedEventTitleTruncatesNameButKeepsTimePrefix() {
        let now = date(day: 6, hour: 9, minute: 0)
        let longTitle = "12345678901234567890123456789012345678901234567890"
        let events = [
            event(title: longTitle, start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "10:00\u{202F}AM · 123456789012345678901234567890123456789012345...")
        XCTAssertEqual(snapshot.sections[0].rows[0].toolTip, "10:00\u{202F}AM · \(longTitle)")
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

        XCTAssertEqual(snapshot.sections[0].rows[0].title, "All-day · 123456789012345678901234567890123456789012345...")
        XCTAssertEqual(snapshot.sections[0].rows[0].toolTip, "All-day · \(longTitle)")
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

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00\u{202F}AM · Timed"])
    }

    func testEventsFromUnselectedCalendarsAreExcluded() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Work Standup", calendarIdentifier: "work", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0)),
            event(title: "Holiday", calendarIdentifier: "holidays", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            selectedCalendarIdentifiers: ["work"],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00\u{202F}AM · Work Standup"])
    }

    func testExplicitEmptyCalendarSelectionShowsNoCalendarsSelected() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Work Standup", calendarIdentifier: "work", start: date(day: 6, hour: 10, minute: 0), end: date(day: 6, hour: 11, minute: 0))
        ]

        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            selectedCalendarIdentifiers: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["No calendars selected"])
        XCTAssertFalse(snapshot.sections[0].rows[0].isEnabled)
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
                meetingLink: MeetingLink(url: zoomURL, provider: .zoom)
            )
        ]

        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let row = snapshot.sections[0].rows[0]

        XCTAssertEqual(snapshot.sections[0].rows.map(\.title), ["10:00\u{202F}AM · Office Hours"])
        XCTAssertTrue(row.isEnabled)
        XCTAssertNil(row.action)
        XCTAssertEqual(row.submenuRows.filter { !$0.isSeparator }.map(\.title), [
            "Join Zoom",
            "Copy Meeting Link",
            "Show in Calendar"
        ])
        XCTAssertEqual(row.submenuRows[0].action, .joinMeeting(MeetingLink(url: zoomURL, provider: .zoom)))
        XCTAssertEqual(row.submenuRows[0].keyEquivalent, "j")
        XCTAssertEqual(row.submenuRows[1].action, .copyMeetingLink(zoomURL))
        XCTAssertTrue(row.submenuRows[2].isSeparator)
        XCTAssertEqual(row.submenuRows[3].action, .openEvent(eventIdentifier: "calendar-item-id", startDate: startDate))
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
        let visibleFooterRows = snapshot.footerRows.filter { !$0.isHidden && !$0.isSeparator }

        XCTAssertEqual(visibleFooterRows.map(\.title), ["Open Calendar", "Settings...", "Quit Perch Completely"])
        XCTAssertEqual(visibleFooterRows[0].keyEquivalent, "1")
        XCTAssertEqual(visibleFooterRows[0].keyEquivalentModifierMask, [.command])

        XCTAssertEqual(visibleFooterRows[1].keyEquivalent, ",")
        XCTAssertEqual(visibleFooterRows[1].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(snapshot.footerRows.filter(\.isSeparator).count, 1)
    }

    @MainActor
    func testDayLabelsUseNoninteractiveStandardMenuTypography() {
        let now = date(day: 6, hour: 9, minute: 0)
        let events = [
            event(title: "Ongoing Event", start: date(day: 6, hour: 8, minute: 30), end: date(day: 6, hour: 9, minute: 30)),
            event(title: "Today Event", start: date(day: 6, hour: 12, minute: 0), end: date(day: 6, hour: 13, minute: 0)),
            event(title: "Tomorrow Event", start: date(day: 7, hour: 10, minute: 0), end: date(day: 7, hour: 11, minute: 0))
        ]
        let snapshot = builder.snapshot(
            accessState: .fullAccess,
            events: events,
            displayMode: .within6Hours,
            now: now,
            calendar: calendar
        )
        let menu = builder.makeMenu(from: snapshot, target: MenuShortcutTarget())

        XCTAssertEqual(snapshot.sections.map(\.title), ["Ending in 30 min", "Today", "Tomorrow"])
        for section in snapshot.sections {
            let header = menu.items.first { $0.title == section.title }
            XCTAssertNotNil(header)
            XCTAssertFalse(header?.isSectionHeader ?? true)
            XCTAssertFalse(header?.isEnabled ?? true)
            XCTAssertNil(header?.action)
        }
        XCTAssertEqual(menu.minimumWidth, 272)
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
    func testMenuLeavesNavigationKeysToNativeMenuTracking() {
        let snapshot = builder.snapshot(accessState: .fullAccess, events: [], now: Date(), calendar: calendar)
        let menu = builder.makeMenu(from: snapshot, target: MenuShortcutTarget())

        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: "\u{F700}", modifierFlags: [])))
        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: "\u{F701}", modifierFlags: [])))
        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: "\r", modifierFlags: [])))
        XCTAssertFalse(menu.performKeyEquivalent(with: keyEvent(characters: "\u{1B}", modifierFlags: [])))
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

        XCTAssertEqual(menu.item(at: 1)?.toolTip, "10:00\u{202F}AM · \(longTitle)")
    }

    @MainActor
    func testZoomSubmenuPerformsJoinMeeting() {
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
                meetingLink: MeetingLink(
                    url: URL(string: "https://school.zoom.us/j/1234567890")!,
                    provider: .zoom
                )
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 0)

        XCTAssertEqual(target.joinMeetingCount, 1)
        XCTAssertEqual(target.openCalendarEventCount, 0)
    }

    @MainActor
    func testGoogleMeetSubmenuPerformsGenericMeetingAction() {
        let now = date(day: 6, hour: 9, minute: 0)
        let meetingLink = MeetingLink(
            url: URL(string: "https://meet.google.com/abc-defg-hij")!,
            provider: .googleMeet
        )
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                meetingLink: meetingLink
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 0)

        XCTAssertEqual(target.joinMeetingCount, 1)
        XCTAssertEqual(snapshot.sections[0].rows[0].submenuRows[0].title, "Join Google Meet")
        XCTAssertEqual(snapshot.sections[0].rows[0].submenuRows[0].action, .joinMeeting(meetingLink))
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
                meetingLink: MeetingLink(
                    url: URL(string: "https://school.zoom.us/j/1234567890")!,
                    provider: .zoom
                )
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 3)

        XCTAssertEqual(target.openCalendarEventCount, 1)
        XCTAssertEqual(target.joinMeetingCount, 0)
    }

    @MainActor
    func testMeetingSubmenuPerformsCopyMeetingLink() {
        let now = date(day: 6, hour: 9, minute: 0)
        let zoomURL = URL(string: "https://school.zoom.us/j/1234567890")!
        let events = [
            CalendarEvent(
                id: "calendar-item-id",
                title: "Office Hours",
                startDate: date(day: 6, hour: 10, minute: 0),
                endDate: date(day: 6, hour: 11, minute: 0),
                isAllDay: false,
                calendarTitle: "School",
                calendarColor: .systemBlue,
                meetingLink: MeetingLink(url: zoomURL, provider: .zoom)
            )
        ]
        let snapshot = builder.snapshot(accessState: .fullAccess, events: events, now: now, calendar: calendar)
        let target = MenuShortcutTarget()
        let menu = builder.makeMenu(from: snapshot, target: target)

        menu.item(at: 1)?.submenu?.performActionForItem(at: 1)

        XCTAssertEqual(target.copyMeetingLinkCount, 1)
        XCTAssertEqual(snapshot.sections[0].rows[0].submenuRows[1].action, .copyMeetingLink(zoomURL))
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

    private func event(
        title: String,
        calendarIdentifier: String = "school",
        start: Date,
        end: Date
    ) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarTitle: "School",
            calendarColor: .systemBlue,
            calendarIdentifier: calendarIdentifier
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
    private(set) var joinMeetingCount = 0
    private(set) var copyMeetingLinkCount = 0
    private(set) var openSettingsCount = 0
    private(set) var closeMenuCount = 0

    @objc func openCalendarApp() {
        openCalendarCount += 1
    }

    @objc func openCalendarEvent(_ sender: NSMenuItem) {
        openCalendarEventCount += 1
    }

    @objc func joinMeetingFromMenu(_ sender: NSMenuItem) {
        joinMeetingCount += 1
    }

    @objc func copyMeetingLink(_ sender: NSMenuItem) {
        copyMeetingLinkCount += 1
    }

    @objc func performSettingsMenuAction() {
        openSettingsCount += 1
    }

    @objc func closeTrayMenuFromMenuItem() {
        closeMenuCount += 1
    }
}
