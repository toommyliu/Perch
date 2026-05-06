import Carbon
import XCTest
@testable import Perch

final class GlobalHotKeyControllerTests: XCTestCase {
    func testApplyShortcutRegistersNewShortcutAfterUnregisteringOldShortcut() {
        let registrar = FakeHotKeyRegistrar(statuses: [noErr, noErr])
        let shortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])
        let controller = GlobalHotKeyController(
            initialShortcut: .defaultValue,
            registrar: registrar,
            installHandler: false,
            onToggle: {}
        )

        let result = controller.applyShortcut(shortcut)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(registrar.registeredShortcuts, [.defaultValue, shortcut])
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    func testFailedApplyShortcutReregistersPreviousShortcutAndReportsFailure() {
        let conflictStatus: OSStatus = -9878
        let registrar = FakeHotKeyRegistrar(statuses: [noErr, conflictStatus, noErr])
        let shortcut = GlobalShortcut(keyEquivalent: "p", keyCode: 35, modifiers: [.option, .command])
        let controller = GlobalHotKeyController(
            initialShortcut: .defaultValue,
            registrar: registrar,
            installHandler: false,
            onToggle: {}
        )

        let result = controller.applyShortcut(shortcut)

        XCTAssertEqual(result, .failure(conflictStatus))
        XCTAssertEqual(registrar.registeredShortcuts, [.defaultValue, shortcut, .defaultValue])
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    func testSetEnabledUnregistersAndReregistersActiveShortcut() {
        let registrar = FakeHotKeyRegistrar(statuses: [noErr, noErr])
        let controller = GlobalHotKeyController(
            initialShortcut: .defaultValue,
            registrar: registrar,
            installHandler: false,
            onToggle: {}
        )

        controller.setEnabled(false)
        controller.setEnabled(true)

        XCTAssertEqual(registrar.registeredShortcuts, [.defaultValue, .defaultValue])
        XCTAssertEqual(registrar.unregisterCount, 1)
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering {
    private var statuses: [OSStatus]
    private var nextRefID = 1
    private(set) var registeredShortcuts: [GlobalShortcut] = []
    private(set) var unregisterCount = 0

    init(statuses: [OSStatus]) {
        self.statuses = statuses
    }

    func register(shortcut: GlobalShortcut, hotKeyID: EventHotKeyID) -> HotKeyRegistration {
        registeredShortcuts.append(shortcut)

        let status = statuses.isEmpty ? noErr : statuses.removeFirst()
        guard status == noErr else {
            return HotKeyRegistration(status: status, hotKeyRef: nil)
        }

        let ref = EventHotKeyRef(bitPattern: nextRefID)
        nextRefID += 1
        return HotKeyRegistration(status: status, hotKeyRef: ref)
    }

    func unregister(_ hotKeyRef: EventHotKeyRef) {
        unregisterCount += 1
    }
}
