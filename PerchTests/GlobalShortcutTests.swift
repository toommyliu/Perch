import AppKit
import Carbon
import XCTest
@testable import Perch

final class GlobalShortcutTests: XCTestCase {
    func testControlCommandKMatchesDefaultShortcut() {
        XCTAssertTrue(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.command, .control])))
    }

    func testCommandKDoesNotMatchDefaultShortcut() {
        XCTAssertFalse(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.command])))
    }

    func testControlKDoesNotMatchDefaultShortcut() {
        XCTAssertFalse(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.control])))
    }

    func testControlCommandShiftKDoesNotMatchDefaultShortcut() {
        XCTAssertFalse(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.command, .control, .shift])))
    }

    func testControlCommandOptionKDoesNotMatchDefaultShortcut() {
        XCTAssertFalse(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.command, .control, .option])))
    }

    func testControlCommandKWithCapsLockMatchesDefaultShortcut() {
        XCTAssertTrue(GlobalShortcut.defaultValue.matchesMenuEvent(keyEvent(modifierFlags: [.command, .control, .capsLock])))
    }

    func testCandidateRejectsModifierOnlyAndShiftOnlyShortcuts() {
        XCTAssertNil(GlobalShortcut.candidate(from: keyEvent(characters: "", modifierFlags: [.command], keyCode: UInt16(kVK_Command))))
        XCTAssertNil(GlobalShortcut.candidate(from: keyEvent(characters: "k", modifierFlags: [.shift], keyCode: UInt16(kVK_ANSI_K))))
    }

    func testCandidateCreatesCustomPrintableShortcut() {
        let shortcut = GlobalShortcut.candidate(from: keyEvent(characters: "p", modifierFlags: [.option, .command], keyCode: 35))

        XCTAssertEqual(shortcut?.keyEquivalent, "p")
        XCTAssertEqual(shortcut?.keyCode, 35)
        XCTAssertEqual(shortcut?.modifiers, [.option, .command])
    }

    func testCustomShortcutMatchesByKeyCodeOrKeyEquivalentAndExactModifiers() {
        let shortcut = GlobalShortcut(
            keyEquivalent: "p",
            keyCode: 35,
            modifiers: [.option, .command]
        )

        XCTAssertTrue(shortcut.matchesMenuEvent(keyEvent(characters: "p", modifierFlags: [.option, .command], keyCode: 0)))
        XCTAssertTrue(shortcut.matchesMenuEvent(keyEvent(characters: "x", modifierFlags: [.option, .command], keyCode: 35)))
        XCTAssertFalse(shortcut.matchesMenuEvent(keyEvent(characters: "p", modifierFlags: [.option, .command, .shift], keyCode: 35)))
    }

    func testDisplayTitleUsesStableModifierOrder() {
        let shortcut = GlobalShortcut(
            keyEquivalent: "p",
            keyCode: 35,
            modifiers: [.command, .shift, .option, .control]
        )

        XCTAssertEqual(shortcut.displayTitle, "⌃⌥⇧⌘P")
    }

    private func keyEvent(
        characters: String = GlobalShortcut.defaultValue.keyEquivalent,
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16 = GlobalShortcut.defaultValue.keyCode
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
}
