import Foundation
import MacsSettings

/// Keys as text, the way the config file holds them (`MacsSettings.KeyText`, shared with MacsPane):
/// "ctrl+opt+cmd+P", "hyper+N", "cmd+space", or the menu's "⌃⌥⌘P".
extension KeyCombo {
    /// The keys `text` names, or nil when it names none (an unknown word, no key, two keys).
    public init?(text: String) {
        guard let (code, bits) = KeyText.parse(text) else { return nil }
        self.init(keyCode: code, modifiers: Modifiers(rawValue: bits))
    }

    /// The keys as the config file writes them. A key with no name here is written by its number ("key105").
    public var text: String { KeyText.write(keyCode: keyCode, modifiers: modifiers.rawValue) }
}
