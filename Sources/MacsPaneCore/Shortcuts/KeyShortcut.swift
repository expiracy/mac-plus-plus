import Foundation
import MacsSettings

/// A key combination pressed anywhere to run a MacsPane action: a key, by its hardware key code, and
/// the modifiers held with it. `character` is what the key typed when it was recorded, on the
/// keyboard layout of the day, kept only to write the shortcut out ("⌃⌥1").
public struct KeyShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: Modifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    /// The same keys are the same shortcut, whatever they typed when recorded.
    public static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    /// Whether it can be taken from every app: it needs ⌘, ⌃ or ⌥, or a function key, so it never
    /// eats what you type.
    public var isUsable: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(keyCode)
    }

    /// The shortcut as macOS menus write it: ⌃⌥⇧⌘, then the key.
    public var displayName: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// The key alone: its symbol or name for keys that type nothing, else what it typed.
    public var keyName: String {
        if let name = Self.specialKeyNames[keyCode] { return name }
        if let character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return character.uppercased()
        }
        if let name = KeyText.usLetters[keyCode] { return name }
        return "Key \(keyCode)"
    }

    /// Keys that type nothing visible, by key code (the US-layout hardware codes macOS uses on
    /// every layout).
    static let specialKeyNames = KeyText.symbolNames

    static let functionKeys = KeyText.functionKeys
}

/// Keys as text, as the settings file holds them: "ctrl+opt+left", "hyper+N", "F13", or the menu's
/// "⌃⌥←" (`MacsSettings.KeyText`, the same words MacsBored's file uses).
extension KeyShortcut {
    /// The keys `text` names, or nil when it names none.
    public init?(text: String) {
        guard let (code, bits) = KeyText.parse(text) else { return nil }
        self.init(keyCode: code, modifiers: Modifiers(rawValue: bits))
    }

    public var text: String { KeyText.write(keyCode: keyCode, modifiers: modifiers.rawValue) }
}

extension KeyShortcut: Codable {
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, character }

    /// Written as text ("ctrl+opt+left"). Read as text, or as the key code and modifier bits files
    /// held before. Keys that name nothing throw, so the list holding them drops them alone.
    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard let keys = KeyShortcut(text: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "“\(text)” isn't keys"))
            }
            self = keys
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        self.modifiers = (try? c.decodeIfPresent(Modifiers.self, forKey: .modifiers)) ?? []
        self.character = try? c.decodeIfPresent(String.self, forKey: .character)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}
