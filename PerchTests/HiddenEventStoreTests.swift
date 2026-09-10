import AppKit
import XCTest
@testable import Perch

final class HiddenEventStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBarOnlyHidePersistsWithoutRemovingAgendaOrSuppressingNotifications() {
        let defaults = makeDefaults()
        let item = event(start: now.addingTimeInterval(60))
        let occurrence = CalendarEventOccurrence(event: item)
        let store = HiddenEventStore(userDefaults: defaults)
        store.hide(item, scope: .bar, now: now)
        let reloaded = HiddenEventStore(userDefaults: defaults)
        reloaded.reconcile(events: [item], now: now)

        XCTAssertEqual(reloaded.hiddenOccurrences(now: now), [occurrence])
        XCTAssertTrue(reloaded.hiddenOccurrences(now: now, scope: .completely).isEmpty)
        let label = MenuBarLabelFormatter().labelContent(
            events: [item], settings: .defaultValue,
            hiddenOccurrences: reloaded.hiddenOccurrences(now: now), now: now
        )
        XCTAssertEqual(label, .dateIcon(day: Calendar.current.component(.day, from: now)))
        let snapshot = MenuBuilder().snapshot(
            accessState: .fullAccess, events: [item], hiddenEvents: reloaded.activeEvents(now: now), now: now
        )
        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(snapshot.sections[0].title, DateFormatting.menuSectionTitle(for: item.startDate, now: now, calendar: .current, locale: .autoupdatingCurrent))
        let actions = snapshot.sections[0].rows[0].submenuRows.compactMap(\.action)
        XCTAssertTrue(actions.contains(.restoreEvent(occurrence)))
        XCTAssertTrue(actions.contains(.hideEvent(occurrence)))
        XCTAssertFalse(actions.contains(.hideFromBar(occurrence)))
        XCTAssertEqual(snapshot.footerRows[0].action, .openCalendar)

        reloaded.hide(item, scope: .completely, now: now)
        XCTAssertEqual(reloaded.activeEvents(now: now).count, 1)
        XCTAssertEqual(reloaded.hiddenOccurrences(now: now, scope: .completely), [occurrence])
        reloaded.restore(occurrence, now: now)
        XCTAssertTrue(reloaded.hiddenOccurrences(now: now).isEmpty)
    }

    func testPreviouslySavedHidesRemainCompletelyHidden() throws {
        struct LegacyRecord: Encodable {
            let occurrence: CalendarEventOccurrence
            let title: String
            let endDate: Date
        }
        let item = event(start: now)
        let defaults = makeDefaults()
        defaults.set(try JSONEncoder().encode([
            LegacyRecord(occurrence: CalendarEventOccurrence(event: item), title: item.title, endDate: item.endDate)
        ]), forKey: "HiddenCalendarEvents")

        let store = HiddenEventStore(userDefaults: defaults)

        XCTAssertEqual(store.hiddenOccurrences(now: now, scope: .completely), [CalendarEventOccurrence(event: item)])
    }

    func testHidingSurvivesReloadAndOnlyFiltersOneOccurrence() {
        let defaults = makeDefaults()
        let store = HiddenEventStore(userDefaults: defaults)
        let first = event(start: now.addingTimeInterval(60))
        let next = event(start: now.addingTimeInterval(3600))
        let otherCalendar = event(calendar: "personal", start: first.startDate)
        store.hide(first, now: now)

        let reloaded = HiddenEventStore(userDefaults: defaults)
        let hidden = reloaded.hiddenOccurrences(now: now)
        let visible = CalendarEventVisibility.upcomingEvents(
            from: [first, next, otherCalendar], includeAllDayEvents: true,
            hiddenOccurrences: hidden, now: now
        )
        XCTAssertEqual(visible, [otherCalendar, next])

        let formatter = MenuBarLabelFormatter(locale: Locale(identifier: "en_US"))
        let label = formatter.labelContent(
            events: [first, next], settings: .defaultValue,
            hiddenOccurrences: hidden, now: now
        )
        XCTAssertEqual(label, .event(title: "Standup", relativeText: "in 1h 0m", color: .systemBlue))

        reloaded.restore(CalendarEventOccurrence(event: first), now: now)
        XCTAssertTrue(HiddenEventStore(userDefaults: defaults).hiddenOccurrences(now: now).isEmpty)
        XCTAssertEqual(
            formatter.labelContent(events: [first, next], settings: .defaultValue, hiddenOccurrences: reloaded.hiddenOccurrences(now: now), now: now),
            .event(title: "Standup", relativeText: "in 1m", color: .systemBlue)
        )
    }

    func testMultiDayHideExpiresAtEndAndRestoringOneKeepsAnotherHidden() {
        let defaults = makeDefaults()
        let store = HiddenEventStore(userDefaults: defaults)
        let holiday = event(start: now, end: now.addingTimeInterval(3 * 86400), isAllDay: true)
        let meeting = event(start: now.addingTimeInterval(60))
        store.hide(holiday, now: now)
        store.hide(meeting, now: now)
        store.restore(CalendarEventOccurrence(event: meeting), now: now)

        XCTAssertEqual(store.activeEvents(now: now.addingTimeInterval(2 * 86400)), [HiddenCalendarEvent(event: holiday)])
        store.reconcile(events: [], now: holiday.endDate)
        XCTAssertTrue(HiddenEventStore(userDefaults: defaults).activeEvents(now: now).isEmpty)
    }

    func testRefreshKeepsHiddenEventWhenItsDurationIsExtended() {
        let store = HiddenEventStore(userDefaults: makeDefaults())
        let original = event(start: now, end: now.addingTimeInterval(60))
        store.hide(original, now: now)
        let extended = event(start: original.startDate, end: now.addingTimeInterval(3600))

        store.reconcile(events: [extended], now: now.addingTimeInterval(120))

        XCTAssertEqual(store.activeEvents(now: now.addingTimeInterval(120)), [HiddenCalendarEvent(event: extended)])
    }

    func testRecoveryRemainsAvailableWhenEveryEventIsHidden() {
        let hiddenEvent = event(start: now)
        let hidden = HiddenCalendarEvent(event: hiddenEvent)
        let builder = MenuBuilder()
        let snapshot = builder.snapshot(
            accessState: .fullAccess, events: [hiddenEvent], hiddenEvents: [hidden], now: now
        )
        XCTAssertEqual(snapshot.sections.flatMap(\.rows).map(\.title), ["No upcoming events"])
        XCTAssertEqual(snapshot.footerRows[0].title, "Hidden Events (1)")
        XCTAssertEqual(snapshot.footerRows[1].action, .openCalendar)
        XCTAssertEqual(snapshot.footerRows[0].submenuRows[0].submenuRows[0].action, .restoreEvent(hidden.occurrence))

        let expired = builder.snapshot(
            accessState: .fullAccess, events: [], hiddenEvents: [hidden], now: hidden.endDate
        )
        XCTAssertEqual(expired.footerRows[0].action, .openCalendar)
        let denied = builder.snapshot(accessState: .denied, events: [], hiddenEvents: [hidden], now: now)
        XCTAssertEqual(denied.footerRows[0].action, .openCalendar)
    }

    private func event(calendar: String = "work", start: Date, end: Date? = nil, isAllDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: "recurring-standup", title: "Standup", startDate: start,
            endDate: end ?? start.addingTimeInterval(1800), isAllDay: isAllDay,
            calendarTitle: calendar, calendarColor: .systemBlue, calendarIdentifier: calendar
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "PerchTests.HiddenEventStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
