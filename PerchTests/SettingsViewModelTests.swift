import AppKit
import XCTest
@testable import Perch

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testInitializesWithSettingsAndPermissionState() {
        let defaults = makeDefaults()
        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.updateDisplayMode(.always)
        settingsStore.updateLookAheadDays(14)
        settingsStore.updateShowEventColors(false)
        settingsStore.updateShowAllDayEvents(false)
        let shortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])
        settingsStore.updateGlobalShortcut(shortcut)
        let provider = FakePermissionProvider(state: .writeOnly)
        let permissionController = CalendarPermissionController(permissionProvider: provider)

        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            onChange: {}
        )

        XCTAssertEqual(model.selectedMode, .always)
        XCTAssertEqual(model.lookAheadDays, 14)
        XCTAssertFalse(model.showEventColors)
        XCTAssertFalse(model.showAllDayEvents)
        XCTAssertEqual(model.globalShortcut, shortcut)
        XCTAssertEqual(model.accessState, .writeOnly)
        XCTAssertEqual(model.accessActionTitle, "Open Privacy Settings...")
        XCTAssertNil(model.selectedCalendarIdentifiers)
    }

    func testLoadsAvailableCalendarsWhenAccessAllowsEvents() async {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let calendarProvider = FakeCalendarEventProvider(calendars: [
            CalendarInfo(id: "holidays", title: "US Holidays", sourceTitle: "Subscribed", color: .systemRed),
            CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", color: .systemBlue)
        ])

        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider,
            onChange: {}
        )

        await waitForAsyncModelUpdate {
            model.availableCalendars.count == 2
        }

        XCTAssertEqual(model.availableCalendars.map(\.id), ["holidays", "work"])
        XCTAssertNil(model.calendarLoadingError)
    }

    func testTogglingCalendarPersistsExplicitSelectionAndNotifies() async {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let workCalendar = CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", color: .systemBlue)
        let holidayCalendar = CalendarInfo(id: "holidays", title: "US Holidays", sourceTitle: "Subscribed", color: .systemRed)
        let calendarProvider = FakeCalendarEventProvider(calendars: [workCalendar, holidayCalendar])
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider
        ) {
            changeCount += 1
        }

        await waitForAsyncModelUpdate {
            model.availableCalendars.count == 2
        }
        XCTAssertEqual(calendarProvider.availableCalendarsCallCount, 1)

        model.setCalendar(holidayCalendar, isSelected: false)
        await Task.yield()

        XCTAssertEqual(model.selectedCalendarIdentifiers, ["work"])
        XCTAssertEqual(settingsStore.settings.selectedCalendarIdentifiers, ["work"])
        XCTAssertTrue(model.isCalendarSelected(workCalendar))
        XCTAssertFalse(model.isCalendarSelected(holidayCalendar))
        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(calendarProvider.availableCalendarsCallCount, 1)
    }

    func testTogglingCalendarDoesNotReloadCalendarsWhenSettingsRefreshPermissionStatus() async {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let workCalendar = CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", color: .systemBlue)
        let holidayCalendar = CalendarInfo(id: "holidays", title: "US Holidays", sourceTitle: "Subscribed", color: .systemRed)
        let calendarProvider = FakeCalendarEventProvider(calendars: [workCalendar, holidayCalendar])
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider
        ) {
            permissionController.refreshStatus()
        }

        await waitForAsyncModelUpdate {
            model.availableCalendars.count == 2
        }
        XCTAssertEqual(calendarProvider.availableCalendarsCallCount, 1)

        model.setCalendar(holidayCalendar, isSelected: false)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(calendarProvider.availableCalendarsCallCount, 1)
        XCTAssertFalse(model.isLoadingCalendars)
    }

    func testSelectingNoCalendarsPersistsExplicitEmptySelection() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController
        ) {
            changeCount += 1
        }

        model.selectNoCalendars()

        XCTAssertEqual(model.selectedCalendarIdentifiers, [])
        XCTAssertEqual(settingsStore.settings.selectedCalendarIdentifiers, [])
        XCTAssertEqual(changeCount, 1)
    }

    func testSelectingAllCalendarsRestoresDefaultAllCalendarsBehavior() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        settingsStore.updateSelectedCalendarIdentifiers(["work"])
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController
        ) {
            changeCount += 1
        }

        model.selectAllCalendars()

        XCTAssertNil(model.selectedCalendarIdentifiers)
        XCTAssertNil(settingsStore.settings.selectedCalendarIdentifiers)
        XCTAssertEqual(changeCount, 1)
    }

    func testChangingColorVisibilityPersistsAndNotifies() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController
        ) {
            changeCount += 1
        }

        model.showEventColors = false

        XCTAssertFalse(settingsStore.settings.showEventColors)
        XCTAssertEqual(changeCount, 1)
    }

    func testChangingAllDayVisibilityPersistsAndNotifies() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController
        ) {
            changeCount += 1
        }

        model.showAllDayEvents = false

        XCTAssertFalse(settingsStore.settings.showAllDayEvents)
        XCTAssertEqual(changeCount, 1)
    }

    func testInitializesWithLaunchAtLoginState() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let loginItemManager = FakeLoginItemManager(isEnabled: true)

        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            loginItemManager: loginItemManager,
            onChange: {}
        )

        XCTAssertTrue(model.launchAtLogin)
        XCTAssertNil(model.loginItemError)
    }

    func testEnablingLaunchAtLoginUpdatesLoginItemStateWithoutNotifyingSettingsChange() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let loginItemManager = FakeLoginItemManager(isEnabled: false)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            loginItemManager: loginItemManager
        ) {
            changeCount += 1
        }

        model.launchAtLogin = true

        XCTAssertTrue(model.launchAtLogin)
        XCTAssertTrue(loginItemManager.isEnabled)
        XCTAssertEqual(loginItemManager.requestedStates, [true])
        XCTAssertNil(model.loginItemError)
        XCTAssertEqual(changeCount, 0)
    }

    func testDisablingLaunchAtLoginUpdatesLoginItemStateWithoutNotifyingSettingsChange() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let loginItemManager = FakeLoginItemManager(isEnabled: true)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            loginItemManager: loginItemManager
        ) {
            changeCount += 1
        }

        model.launchAtLogin = false

        XCTAssertFalse(model.launchAtLogin)
        XCTAssertFalse(loginItemManager.isEnabled)
        XCTAssertEqual(loginItemManager.requestedStates, [false])
        XCTAssertNil(model.loginItemError)
        XCTAssertEqual(changeCount, 0)
    }

    func testFailedLaunchAtLoginChangeRestoresLoginItemStateAndShowsError() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let loginItemManager = FakeLoginItemManager(isEnabled: false)
        loginItemManager.error = FakeLoginItemError.updateFailed
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            loginItemManager: loginItemManager,
            onChange: {}
        )

        model.launchAtLogin = true

        XCTAssertFalse(model.launchAtLogin)
        XCTAssertFalse(loginItemManager.isEnabled)
        XCTAssertEqual(loginItemManager.requestedStates, [true])
        XCTAssertEqual(model.loginItemError, "Could not update launch at login.")
    }

    func testRefreshingLaunchAtLoginSyncsExternalStateWithoutUpdatingLoginItem() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let loginItemManager = FakeLoginItemManager(isEnabled: false)
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            loginItemManager: loginItemManager,
            onChange: {}
        )

        loginItemManager.isEnabled = true
        model.refreshLaunchAtLoginState()

        XCTAssertTrue(model.launchAtLogin)
        XCTAssertEqual(loginItemManager.requestedStates, [])
    }

    func testSuccessfulShortcutRecordingRegistersPersistsAndUpdatesState() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var requestedShortcuts: [GlobalShortcut] = []
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            onShortcutChangeRequested: { shortcut in
                requestedShortcuts.append(shortcut)
                return .success
            }
        ) {
            changeCount += 1
        }

        model.recordShortcut(from: keyEvent(characters: "p", modifierFlags: [.option, .command], keyCode: 35))

        let expectedShortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])
        XCTAssertEqual(requestedShortcuts, [expectedShortcut])
        XCTAssertEqual(model.globalShortcut, expectedShortcut)
        XCTAssertEqual(settingsStore.settings.globalShortcut, expectedShortcut)
        XCTAssertNil(model.shortcutError)
        XCTAssertEqual(changeCount, 1)
    }

    func testFailedShortcutRecordingLeavesPreviousShortcutUnchangedAndShowsError() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            onShortcutChangeRequested: { _ in .failure(-9878) }
        ) {
            changeCount += 1
        }

        model.recordShortcut(from: keyEvent(characters: "p", modifierFlags: [.option, .command], keyCode: 35))

        XCTAssertEqual(model.globalShortcut, .defaultValue)
        XCTAssertEqual(settingsStore.settings.globalShortcut, .defaultValue)
        XCTAssertEqual(model.shortcutError, "Shortcut is already in use.")
        XCTAssertEqual(changeCount, 0)
    }

    func testResetShortcutRestoresDefaultAfterSuccessfulRegistration() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let customShortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])
        settingsStore.updateGlobalShortcut(customShortcut)
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        var requestedShortcuts: [GlobalShortcut] = []
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            onShortcutChangeRequested: { shortcut in
                requestedShortcuts.append(shortcut)
                return .success
            },
            onChange: {}
        )

        model.resetShortcutToDefault()

        XCTAssertEqual(requestedShortcuts, [.defaultValue])
        XCTAssertEqual(model.globalShortcut, .defaultValue)
        XCTAssertEqual(settingsStore.settings.globalShortcut, .defaultValue)
    }

    func testRequestCalendarAccessUpdatesPermissionState() async {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .notDetermined, requestResult: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let calendarProvider = FakeCalendarEventProvider(calendars: [
            CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", color: .systemBlue)
        ])
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            calendarProvider: calendarProvider
        ) {
            changeCount += 1
        }

        model.requestCalendarAccess()
        await waitForAsyncModelUpdate {
            model.accessState == .fullAccess && !model.isRequestingAccess
        }

        XCTAssertEqual(model.accessState, .fullAccess)
        XCTAssertFalse(model.isRequestingAccess)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(changeCount, 1)

        await waitForAsyncModelUpdate {
            model.availableCalendars.count == 1
        }

        XCTAssertEqual(calendarProvider.availableCalendarsCallCount, 1)
    }

    func testPrivacySettingsActionInvokesURLOpener() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let provider = FakePermissionProvider(state: .denied)
        var openedURLs: [URL] = []
        let permissionController = CalendarPermissionController(permissionProvider: provider) { url in
            openedURLs.append(url)
        }
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            onChange: {}
        )

        model.performAccessAction()

        XCTAssertEqual(openedURLs, [CalendarPermissionController.privacySettingsURL])
    }

    #if DEBUG
    func testDebugDateIconOverrideUpdatesDebugSettingsWithoutPersistingSettings() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let initialSettings = settingsStore.settings
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let debugSettings = DateIconDebugSettings()
        var debugChangeCount = 0
        var persistedSettingsChangeCount = 0
        debugSettings.onChange = {
            debugChangeCount += 1
        }
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            dateIconDebugSettings: debugSettings
        ) {
            persistedSettingsChangeCount += 1
        }

        model.debugDateIconOverrideEnabled = true

        XCTAssertTrue(debugSettings.isOverrideEnabled)
        XCTAssertEqual(debugChangeCount, 1)
        XCTAssertEqual(persistedSettingsChangeCount, 0)
        XCTAssertEqual(settingsStore.settings, initialSettings)
    }

    func testDebugDateIconDayClampsAndUpdatesDebugSettingsWithoutPersistingSettings() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let initialSettings = settingsStore.settings
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let debugSettings = DateIconDebugSettings(day: 6)
        var debugChangeCount = 0
        debugSettings.onChange = {
            debugChangeCount += 1
        }
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            dateIconDebugSettings: debugSettings,
            onChange: {}
        )

        model.debugDateIconDay = 99

        XCTAssertEqual(model.debugDateIconDay, 31)
        XCTAssertEqual(debugSettings.day, 31)
        XCTAssertEqual(debugChangeCount, 1)
        XCTAssertEqual(settingsStore.settings, initialSettings)
    }

    func testDebugDateIconFontWeightUpdatesDebugSettingsWithoutPersistingSettings() {
        let settingsStore = SettingsStore(userDefaults: makeDefaults())
        let initialSettings = settingsStore.settings
        let provider = FakePermissionProvider(state: .fullAccess)
        let permissionController = CalendarPermissionController(permissionProvider: provider)
        let debugSettings = DateIconDebugSettings()
        var debugChangeCount = 0
        debugSettings.onChange = {
            debugChangeCount += 1
        }
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController,
            dateIconDebugSettings: debugSettings,
            onChange: {}
        )

        model.debugDateIconFontWeight = .semibold

        XCTAssertEqual(debugSettings.fontWeight, .semibold)
        XCTAssertEqual(debugChangeCount, 1)
        XCTAssertEqual(settingsStore.settings, initialSettings)
    }
    #endif

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PerchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func keyEvent(
        characters: String,
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent {
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
            keyCode: keyCode
        )!
    }

    private func waitForAsyncModelUpdate(
        until condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<20 where !condition() {
            await Task.yield()
        }
    }
}

final class FakePermissionProvider: CalendarPermissionProviding {
    var state: CalendarAccessState
    var requestResult: CalendarAccessState
    private(set) var requestCount = 0

    init(state: CalendarAccessState, requestResult: CalendarAccessState? = nil) {
        self.state = state
        self.requestResult = requestResult ?? state
    }

    func authorizationState() -> CalendarAccessState {
        state
    }

    func requestFullAccess() async -> CalendarAccessState {
        requestCount += 1
        state = requestResult
        return requestResult
    }
}

private final class FakeLoginItemManager: LoginItemManaging {
    var isEnabled: Bool
    var requestedStates: [Bool] = []
    var error: Error?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        requestedStates.append(isEnabled)

        if let error {
            throw error
        }

        self.isEnabled = isEnabled
    }
}

private enum FakeLoginItemError: Error {
    case updateFailed
}

private final class FakeCalendarEventProvider: CalendarEventProviding {
    let calendars: [CalendarInfo]
    private(set) var availableCalendarsCallCount = 0

    init(calendars: [CalendarInfo] = []) {
        self.calendars = calendars
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        availableCalendarsCallCount += 1
        return calendars
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>?
    ) async throws -> [CalendarEvent] {
        []
    }
}
