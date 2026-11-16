import Foundation

/// What a trigger does when its keys are pressed.
public enum TriggerAction: Hashable, Sendable {
    /// Press other keys instead (a remap): ⌘← for Home, say, only in one app.
    case sendKeys(KeyCombo)
    case openApp(AppRef)
    /// Run one of Apple's Shortcuts, by its name in the Shortcuts app.
    case runShortcut(String)
    /// Send the keys themselves straight to the app in front, ahead of macOS and other apps'
    /// global shortcuts: one shortcut for a remote session without a whole passthrough entry.
    case passThrough
    /// A web link, or a file or folder path ("~/…" works).
    case open(String)
    /// Type this text into the app in front, as if from the keyboard.
    case typeText(String)
    /// Wait this many seconds before the next step, up to `longestWait`.
    case wait(Double)

    /// The longest a wait can be: an hour.
    public static let longestWait: Double = 3600

    public var kind: Kind {
        switch self {
        case .sendKeys: .sendKeys
        case .openApp: .openApp
        case .runShortcut: .runShortcut
        case .passThrough: .passThrough
        case .open: .open
        case .typeText: .typeText
        case .wait: .wait
        }
    }

    /// The action's kind alone, as the editor's tiles and the config file name it.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case sendKeys, openApp, runShortcut, passThrough, open, typeText, wait
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .sendKeys: "Send other keys"
            case .openApp: "Open an app"
            case .runShortcut: "Run a Shortcut"
            case .passThrough: "Pass keys to the app"
            case .open: "Open a link or file"
            case .typeText: "Type text"
            case .wait: "Wait"
            }
        }

        /// How the "New trigger…" menu says it, after "A trigger that…".
        public var menuTitle: String {
            switch self {
            case .sendKeys: "Sends other keys"
            case .openApp: "Opens an app"
            case .runShortcut: "Runs a Shortcut"
            case .passThrough: "Passes keys to the app"
            case .open: "Opens a link or file"
            case .typeText: "Types text"
            case .wait: "Waits"
            }
        }

        public var symbol: String {
            switch self {
            case .sendKeys: "arrow.left.arrow.right"
            case .openApp: "square.grid.2x2"
            case .runShortcut: "square.stack.3d.up"
            case .passThrough: "arrow.right.to.line"
            case .open: "link"
            case .typeText: "character.cursor.ibeam"
            case .wait: "hourglass"
            }
        }

        /// The action this kind starts as, when picked in the editor.
        public var blank: TriggerAction {
            switch self {
            case .sendKeys: .sendKeys(KeyCombo(keyCode: 123, modifiers: .command))
            case .openApp: .openApp(AppRef(bundleID: "", name: ""))
            case .runShortcut: .runShortcut("")
            case .passThrough: .passThrough
            case .open: .open("")
            case .typeText: .typeText("")
            case .wait: .wait(1)
            }
        }
    }

    /// One line for the menu: what happens.
    public var summary: String {
        switch self {
        case let .sendKeys(keys): "Sends \(keys.displayName)"
        case let .openApp(app): app.name.isEmpty ? "Opens an app" : "Opens \(app.name)"
        case let .runShortcut(name): name.isEmpty ? "Runs a Shortcut" : "Runs “\(name)”"
        case .passThrough: "Passes the keys to the app"
        case let .open(target): target.isEmpty ? "Opens a link" : "Opens \(target)"
        case let .typeText(text): text.isEmpty ? "Types text" : "Types “\(text)”"
        case let .wait(seconds): "Waits \(seconds.formatted()) s"
        }
    }
}

/// What starts an action.
public enum TriggerStart: Hashable, Sendable {
    /// Pressing any of the trigger's `keys`.
    case keys
    /// A mouse button other than the left and right: 3 is the middle, 4 and 5 the side buttons.
    case mouseButton(Int)
    /// This app opening.
    case appOpens(AppRef)
    /// Typing these letters, anywhere you type: they're taken out again as it runs.
    case typed(String)
    /// The clock reaching this time each day, in minutes since midnight.
    case time(Int)

    public var kind: Kind {
        switch self {
        case .keys: .keys
        case .mouseButton: .mouseButton
        case .appOpens: .appOpens
        case .typed: .typed
        case .time: .time
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case keys, mouseButton, appOpens, typed, time

        /// As the editor's Trigger menu says it, after "When".
        public var title: String {
            switch self {
            case .keys: "I press keys"
            case .mouseButton: "I click a mouse button"
            case .appOpens: "An app opens"
            case .typed: "I type some letters"
            case .time: "It's a set time"
            }
        }

        public var symbol: String {
            switch self {
            case .keys: "keyboard"
            case .mouseButton: "computermouse"
            case .appOpens: "macwindow"
            case .typed: "character.cursor.ibeam"
            case .time: "clock"
            }
        }
    }

    /// "Button 4", "Middle button".
    public static func buttonName(_ number: Int) -> String { number == 3 ? "Middle button" : "Button \(number)" }
}

/// A shortcut of your own: its keys (one or several), what they do, and where. With no apps it works everywhere except
/// inside a passthrough app (whose keys belong to the session); name a passthrough app to have it
/// work there too.
public struct Trigger: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Any of these keys sets it off; none leaves it waiting for keys.
    public var keys: [KeyCombo]
    /// What it does, in order.
    public var steps: [TriggerAction]
    /// What sets it off: any of these. `.keys` stands for `keys` (one or several), so it's there once.
    public var starts: [TriggerStart]
    /// Only in these apps; empty for everywhere.
    public var apps: [AppRef]
    public var conditions: ConditionSet
    /// Fields in the config file MacsBored doesn't know, written back as they were.
    public var extra: JSONFields

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, keys: [KeyCombo],
                steps: [TriggerAction], apps: [AppRef] = [], conditions: ConditionSet = ConditionSet(),
                starts: [TriggerStart] = [.keys], extra: JSONFields = JSONFields()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.keys = keys
        self.steps = steps
        self.starts = starts
        self.apps = apps
        self.conditions = conditions
        self.extra = extra
    }

    /// A trigger that does one thing.
    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, keys: [KeyCombo],
                action: TriggerAction, apps: [AppRef] = [], conditions: ConditionSet = ConditionSet(),
                extra: JSONFields = JSONFields()) {
        self.init(id: id, name: name, isEnabled: isEnabled, keys: keys, steps: [action], apps: apps,
                  conditions: conditions, extra: extra)
    }

    /// Its keys go straight to the app in front, and that is all it does.
    public var passesKeysThrough: Bool { steps == [.passThrough] }

    /// Whether pressing `keys` runs this trigger now.
    public func fires(on pressed: KeyCombo, context: AppContext, passthroughActive: Bool) -> Bool {
        starts.contains(.keys) && keys.contains(pressed) && worksHere(context, passthroughActive: passthroughActive)
    }

    /// Whether clicking mouse button `number` runs this trigger now.
    public func fires(onMouseButton number: Int, context: AppContext, passthroughActive: Bool) -> Bool {
        starts.contains(.mouseButton(number)) && worksHere(context, passthroughActive: passthroughActive)
    }

    /// Whether the app `bundleID` opening runs this trigger.
    public func fires(onOpening bundleID: String, context: AppContext) -> Bool {
        guard isEnabled, starts.contains(where: { if case let .appOpens(app) = $0 { app.bundleID == bundleID } else { false } })
        else { return false }
        return conditions.isSatisfied(by: context)
    }

    /// Whether the clock moving on from minute `from` to minute `to` passes this trigger's time.
    public func fires(from: Int, to: Int, context: AppContext) -> Bool {
        guard isEnabled, from != to else { return false }
        let passed = starts.contains { start in
            guard case let .time(minute) = start else { return false }
            return from < to ? (minute > from && minute <= to) : (minute > from || minute <= to)
        }
        return passed && conditions.isSatisfied(by: context)
    }

    /// Switched on, in an app it works in, with its conditions met. With no apps it works everywhere
    /// except inside a passthrough app.
    func worksHere(_ context: AppContext, passthroughActive: Bool) -> Bool {
        guard isEnabled else { return false }
        if apps.isEmpty {
            if passthroughActive { return false }
        } else if !apps.contains(where: { $0.bundleID == context.bundleID }) {
            return false
        }
        return conditions.isSatisfied(by: context)
    }
}

/// The last few letters typed, for triggers set off by typing. Anything that isn't typing (a
/// shortcut, a click, another app) starts it again.
public struct TypedLetters: Sendable {
    private var recent = ""

    public init() {}

    /// Adds what a key typed; returns the trigger whose letters have just been typed, and those
    /// letters, if any.
    public mutating func add(_ text: String, triggers: [Trigger], context: AppContext) -> (trigger: Trigger, letters: String)? {
        recent = String((recent + text).suffix(40))
        for trigger in triggers where trigger.worksHere(context, passthroughActive: false) {
            for case let .typed(letters) in trigger.starts where !letters.isEmpty && recent.hasSuffix(letters) {
                recent = ""
                return (trigger, letters)
            }
        }
        return nil
    }

    /// Whether any of these triggers starts by typing, so typing needs watching at all.
    public static func watches(_ triggers: [Trigger]) -> Bool {
        triggers.contains { $0.starts.contains { if case .typed = $0 { true } else { false } } }
    }

    public mutating func reset() { recent = "" }
}
