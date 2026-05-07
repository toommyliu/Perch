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
        XCTAssertEqual(model.globalShortcut, shortcut)
        XCTAssertEqual(model.accessState, .writeOnly)
        XCTAssertEqual(model.accessActionTitle, "Open Privacy Settings...")
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
        var changeCount = 0
        let model = SettingsViewModel(
            settingsStore: settingsStore,
            permissionController: permissionController
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
