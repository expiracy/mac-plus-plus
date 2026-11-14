import Foundation

/// Keys as text, the way both settings files hold them: modifiers then the key, joined by "+"
/// ("ctrl+opt+cmd+P", "hyper+N", "cmd+space", "ctrl+opt+left"). Reading also takes the menu's symbols
/// ("⌃⌥⌘P", "⌘Space") and longer words ("control", "option", "alt", "command"). Keys are named as on a
/// US keyboard, which is how macOS numbers them on every layout.
///
/// Modifiers are bits: control 1, option 2, shift 4, command 8, the same in MacsPane and MacsBored.
public enum KeyText {
    public static let control: UInt32 = 1 << 0
    public static let option: UInt32 = 1 << 1
    public static let shift: UInt32 = 1 << 2
    public static let command: UInt32 = 1 << 3
    /// All four held: Caps Lock as Hyper.
    public static let hyper: UInt32 = control | option | shift | command

    /// The key and modifiers `text` names, or nil when it names none (an unknown word, no key, two keys).
    public static func parse(_ text: String) -> (keyCode: UInt16, modifiers: UInt32)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        let keyPart: String
        if trimmed.count > 1, trimmed.contains("+") {
            var parts = trimmed.split(separator: "+", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            keyPart = parts.removeLast()
            for word in parts {
                guard let modifier = modifierWords[word.lowercased()] else { return nil }
                modifiers |= modifier
            }
        } else {
            var rest = Substring(trimmed)
            if rest.lowercased().hasPrefix("hyper ") {
                modifiers = hyper
                rest = rest.dropFirst(6)
            }
            while let first = rest.first, let modifier = modifierSymbols[first] {
                modifiers |= modifier
                rest = rest.dropFirst()
            }
            keyPart = rest.trimmingCharacters(in: .whitespaces)
        }
        guard let code = keyCode(named: keyPart) else { return nil }
        return (code, modifiers)
    }

    /// The keys as the settings files write them. A key with no name here is written by its number ("key105").
    public static func write(keyCode: UInt16, modifiers: UInt32) -> String {
        let key = textNames[keyCode] ?? "key\(keyCode)"
        if modifiers & hyper == hyper { return "hyper+" + key }
        let words: [(UInt32, String)] = [(control, "ctrl"), (option, "opt"), (shift, "shift"), (command, "cmd")]
        return (words.filter { modifiers & $0.0 != 0 }.map(\.1) + [key]).joined(separator: "+")
    }

    /// Keys that type nothing visible, as menus draw them, by key code (the US-layout hardware codes
    /// macOS uses on every layout).
    public static let symbolNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// What the letter and digit keys type on a US layout, for keys saved without what they typed.
    public static let usLetters: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
    ]

    /// The F-keys, which work as shortcuts without a modifier.
    public static let functionKeys = Set(symbolNames.filter { $0.value.hasPrefix("F") }.keys)

    private static let modifierWords: [String: UInt32] = [
        "ctrl": control, "control": control, "⌃": control,
        "opt": option, "option": option, "alt": option, "⌥": option,
        "shift": shift, "⇧": shift,
        "cmd": command, "command": command, "⌘": command,
        "hyper": hyper,
    ]

    private static let modifierSymbols: [Character: UInt32] = ["⌃": control, "⌥": option, "⇧": shift, "⌘": command]

    /// Each named key's one written name: letters and digits as typed, everything else a word.
    private static let textNames: [UInt16: String] = {
        var names = usLetters
        let words: [UInt16: String] = [
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape", 76: "enter", 117: "forwarddelete",
            123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        ]
        names.merge(words) { $1 }
        for (code, name) in symbolNames where name.hasPrefix("F") { names[code] = name }
        return names
    }()

    /// Every name a key goes by, lowercased: its written name, the menu's symbol and a few others.
    private static let namesToCodes: [String: UInt16] = {
        var codes: [String: UInt16] = [:]
        for (code, name) in textNames { codes[name.lowercased()] = code }
        for (code, name) in symbolNames { codes[name.lowercased()] = code }
        let aliases: [String: UInt16] = ["esc": 53, "backspace": 51, "ret": 36, "fwddelete": 117, "del": 117]
        codes.merge(aliases) { current, _ in current }
        return codes
    }()

    private static func keyCode(named name: String) -> UInt16? {
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        if let code = namesToCodes[lower] { return code }
        if lower.hasPrefix("key"), let code = UInt16(lower.dropFirst(3)), code < 128 { return code }
        return nil
    }
}
