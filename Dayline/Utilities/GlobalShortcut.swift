import AppKit
import Carbon
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GlobalShortcut: Codable, Equatable {
    let keyEquivalent: String
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    static let defaultValue = GlobalShortcut(
        keyEquivalent: "k",
        keyCode: UInt16(kVK_ANSI_K),
        modifiers: [.control, .command]
    )

    private static let meaningfulMenuModifierFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    private static let allowedShortcutModifiers: ShortcutModifiers = [.control, .option, .shift, .command]

    var menuModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if modifiers.contains(.command) {
            flags.insert(.command)
        }

        if modifiers.contains(.control) {
            flags.insert(.control)
        }

        if modifiers.contains(.option) {
            flags.insert(.option)
        }

        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }

        return flags
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0

        if modifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }

        if modifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }

        if modifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }

        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }

    var displayTitle: String {
        var title = ""

        if modifiers.contains(.control) {
            title += "⌃"
        }

        if modifiers.contains(.option) {
            title += "⌥"
        }

        if modifiers.contains(.shift) {
            title += "⇧"
        }

        if modifiers.contains(.command) {
            title += "⌘"
        }

        return title + keyEquivalent.uppercased()
    }

    var isValid: Bool {
        Self.isPrintableKeyEquivalent(keyEquivalent)
            && modifiers.isSubset(of: Self.allowedShortcutModifiers)
            && modifiers.intersection([.command, .control, .option]).isEmpty == false
    }

    func matchesMenuEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        let isExpectedKey = event.keyCode == keyCode
            || event.charactersIgnoringModifiers?.lowercased() == keyEquivalent.lowercased()
        guard isExpectedKey else {
            return false
        }

        return event.modifierFlags.intersection(Self.meaningfulMenuModifierFlags) == menuModifierFlags
    }

    static func candidate(from event: NSEvent) -> GlobalShortcut? {
        guard event.type == .keyDown,
              let keyEquivalent = normalizedKeyEquivalent(from: event),
              let modifiers = ShortcutModifiers(eventModifierFlags: event.modifierFlags),
              modifiers.intersection([.command, .control, .option]).isEmpty == false
        else {
            return nil
        }

        return GlobalShortcut(
            keyEquivalent: keyEquivalent,
            keyCode: event.keyCode,
            modifiers: modifiers
        )
    }

    private static func normalizedKeyEquivalent(from event: NSEvent) -> String? {
        guard event.specialKey == nil,
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              isPrintableKeyEquivalent(characters)
        else {
            return nil
        }

        return characters
    }

    private static func isPrintableKeyEquivalent(_ keyEquivalent: String) -> Bool {
        guard keyEquivalent.count == 1,
              let scalar = keyEquivalent.unicodeScalars.first
        else {
            return false
        }

        return !CharacterSet.controlCharacters.contains(scalar)
            && !CharacterSet.newlines.contains(scalar)
            && !CharacterSet.whitespaces.contains(scalar)
    }
}

private extension ShortcutModifiers {
    init?(eventModifierFlags: NSEvent.ModifierFlags) {
        let flags = eventModifierFlags.intersection([.command, .control, .option, .shift])
        var modifiers: ShortcutModifiers = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }

        if flags.contains(.control) {
            modifiers.insert(.control)
        }

        if flags.contains(.option) {
            modifiers.insert(.option)
        }

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }

        guard !modifiers.isEmpty else {
            return nil
        }

        self = modifiers
    }
}
