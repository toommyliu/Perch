import Foundation
import XCTest
@testable import Dayline

final class SettingsStoreTests: XCTestCase {
    func testDefaultDisplayModeIsWithinSixHours() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.settings.displayMode, .within6Hours)
        XCTAssertEqual(store.settings.lookAheadDays, 3)
        XCTAssertEqual(store.settings.globalShortcut, .defaultValue)
    }

    func testPersistedDisplayModeRoundTripsThroughUserDefaults() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.updateDisplayMode(.always)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.settings.displayMode, .always)
    }

    func testPersistedLookAheadDaysRoundTripsThroughUserDefaults() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.updateLookAheadDays(14)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.settings.lookAheadDays, 14)
    }

    func testPersistedGlobalShortcutRoundTripsThroughUserDefaults() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        let shortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])

        store.updateGlobalShortcut(shortcut)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.settings.globalShortcut, shortcut)
    }

    func testUnsupportedLookAheadDaysAreIgnored() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.updateLookAheadDays(2)

        XCTAssertEqual(store.settings.lookAheadDays, 3)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: "CalendarMenubarSettings")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.settings, .defaultValue)
    }

    func testStoredSettingsWithoutGlobalShortcutMigrateToDefaultShortcut() throws {
        let defaults = makeDefaults()
        let legacySettings = LegacySettings(displayMode: .always, lookAheadDays: 14)
        defaults.set(try JSONEncoder().encode(legacySettings), forKey: "CalendarMenubarSettings")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.settings.displayMode, .always)
        XCTAssertEqual(store.settings.lookAheadDays, 14)
        XCTAssertEqual(store.settings.globalShortcut, .defaultValue)
    }

    func testInvalidStoredGlobalShortcutFallsBackToDefaultShortcut() throws {
        let defaults = makeDefaults()
        let storedSettings = StoredSettings(
            displayMode: .always,
            lookAheadDays: 14,
            globalShortcut: GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [])
        )
        defaults.set(try JSONEncoder().encode(storedSettings), forKey: "CalendarMenubarSettings")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.settings.displayMode, .always)
        XCTAssertEqual(store.settings.lookAheadDays, 14)
        XCTAssertEqual(store.settings.globalShortcut, .defaultValue)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DaylineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct LegacySettings: Codable {
    let displayMode: MenuBarDisplayMode
    let lookAheadDays: Int
}

private struct StoredSettings: Codable {
    let displayMode: MenuBarDisplayMode
    let lookAheadDays: Int
    let globalShortcut: GlobalShortcut
}
