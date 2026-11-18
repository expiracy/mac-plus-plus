import Foundation
import MacsSettings

/// A key pressed with modifiers: the key by its hardware key code, which is the same on every
/// keyboard layout, and the modifiers held with it. `character` is what the key typed when it was
/// recorded, kept only to write the combination out ("⌃⌥P").
public struct KeyCombo: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// All four at once: what the Hyper key holds.
        public static let hyper: Modifiers = [.control, .option, .shift, .command]
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: Modifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    /// The same keys are the same combination, whatever they typed when recorded.
    public static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    /// Whether it can be a trigger: it needs ⌘, ⌃ or ⌥, or a function key, so it never eats what you type.
    public var isUsableAsTrigger: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(keyCode)
    }

    /// The combination as macOS menus write it: ⌃⌥⇧⌘, then the key. All four read "Hyper".
    public var displayName: String {
        if let tap = tappedModifier { return tap.symbol }
        if modifiers == .hyper { return "Hyper " + keyName }
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// The key alone: its symbol or name for keys that type nothing, else what it typed.
    public var keyName: String {
        if let name = Self.specialKeyNames[keyCode] { return name }
        if let character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return character.uppercased()
        }
        if let name = Self.usLetters[keyCode] { return name }
        return "Key \(keyCode)"
    }

    /// Keys that type nothing visible, by key code (the US-layout hardware codes macOS uses on every layout).
    public static let specialKeyNames = KeyText.symbolNames

    /// What the letter and digit keys type on a US layout, for combinations saved without a character.
    static let usLetters = KeyText.usLetters

    public static let functionKeys = KeyText.functionKeys

    /// Key codes used by name elsewhere.
    public enum Code {
        public static let p: UInt16 = 35
        public static let space: UInt16 = 49
        public static let tab: UInt16 = 48
        public static let escape: UInt16 = 53
        public static let f18: UInt16 = 79
        public static let capsLock: UInt16 = 57
        public static let leftCommand: UInt16 = 55
        public static let rightCommand: UInt16 = 54
        public static let leftControl: UInt16 = 59
        public static let rightControl: UInt16 = 62
    }
}
