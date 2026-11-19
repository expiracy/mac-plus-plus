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
    /// Run a shell script or an AppleScript, and wait for it to finish before the next step.
    case runScript(Script)
    /// Move the window you're in to a part of its screen.
    case moveWindow(WindowPlace)
    /// Arrange windows as one of the Windows tool's presets does.
    case applyPreset(PresetRef)
    /// Choose an item from the app in front's menus, as clicking it would: Format › Column ›
    /// AutoFit Selection.
    case chooseMenuItem(MenuPath)

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
        case .runScript: .runScript
        case .moveWindow: .moveWindow
        case .applyPreset: .applyPreset
        case .chooseMenuItem: .chooseMenuItem
        }
    }

    /// The action's kind alone, as the editor's tiles and the config file name it.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case sendKeys, openApp, runShortcut, passThrough, open, typeText, wait, runScript, moveWindow, applyPreset,
             chooseMenuItem
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
            case .runScript: "Run a script"
            case .moveWindow: "Move the window"
            case .applyPreset: "Arrange windows"
            case .chooseMenuItem: "Choose a menu item"
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
            case .runScript: "Runs a script"
            case .moveWindow: "Moves the window"
            case .applyPreset: "Arranges windows"
            case .chooseMenuItem: "Chooses a menu item"
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
            case .runScript: "terminal"
            case .moveWindow: "rectangle.lefthalf.inset.filled"
            case .applyPreset: "rectangle.3.group"
            case .chooseMenuItem: "filemenu.and.selection"
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
            case .runScript: .runScript(Script(.shell, ""))
            case .moveWindow: .moveWindow(.leftHalf)
            case .applyPreset: .applyPreset(PresetRef(id: "", name: ""))
            case .chooseMenuItem: .chooseMenuItem(MenuPath([]))
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
        case let .runScript(script): script.source.isEmpty ? "Runs a script" : "Runs “\(script.firstLine)”"
        case let .moveWindow(place): "Moves the window to \(place.title.lowercased())"
        case let .applyPreset(preset): preset.name.isEmpty ? "Arranges windows" : "Arranges windows as “\(preset.name)”"
        case let .chooseMenuItem(path): path.titles.isEmpty ? "Chooses a menu item" : "Chooses " + path.text
        }
    }
}

/// A menu item by the titles that lead to it, from the menu bar down: ["Format", "Column",
/// "AutoFit Selection"].
public struct MenuPath: Hashable, Sendable {
    public var titles: [String]

    public init(_ titles: [String]) {
        self.titles = titles
    }

    /// From "Format > Column > AutoFit Selection" (› works too).
    public init(text: String) {
        titles = text.split(whereSeparator: { $0 == ">" || $0 == "›" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// "Format › Column › AutoFit Selection".
    public var text: String { titles.joined(separator: " › ") }

    /// A menu and an item in it at least, each named.
    public var isComplete: Bool {
        titles.count >= 2 && titles.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whether `wanted` names the menu title `actual`: whatever the case, and with or without the
    /// dots of an item that opens a window ("Paste Special…", "Paste Special...", "Paste Special").
    public static func matches(_ wanted: String, _ actual: String) -> Bool {
        let a = plain(wanted), b = plain(actual)
        return !a.isEmpty && a == b
    }

    private static func plain(_ title: String) -> String {
        var text = title.replacingOccurrences(of: "...", with: "…").trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("…") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        return text.lowercased()
    }
}

/// A script a step runs: a shell script (zsh) or an AppleScript.
public struct Script: Hashable, Sendable {
    public enum Language: String, CaseIterable, Sendable {
        case shell, appleScript

        public var title: String {
            switch self {
            case .shell: "Shell"
            case .appleScript: "AppleScript"
            }
        }
    }

    public var language: Language
    public var source: String

    public init(_ language: Language, _ source: String) {
        self.language = language
        self.source = source
    }

    /// Its first line that says anything, for one-line summaries.
    public var firstLine: String {
        source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }
}

/// Where a step moves the window you're in: a part of the screen it's on, as the Windows tool's
/// snap zones name them.
public enum WindowPlace: String, CaseIterable, Sendable {
    case maximize
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds

    public var title: String {
        switch self {
        case .maximize: "Whole screen"
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeftQuarter: "Top-left quarter"
        case .topRightQuarter: "Top-right quarter"
        case .bottomLeftQuarter: "Bottom-left quarter"
        case .bottomRightQuarter: "Bottom-right quarter"
        case .leftThird: "Left third"
        case .centerThird: "Middle third"
        case .rightThird: "Right third"
        case .leftTwoThirds: "Left two-thirds"
        case .rightTwoThirds: "Right two-thirds"
        }
    }
}

/// One of the Windows tool's presets: its ID, which the file keeps, and its name as last seen.
public struct PresetRef: Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A modifier key on its own, for actions started by tapping it twice.
public enum ModifierKey: String, CaseIterable, Sendable {
    case command = "cmd", option = "opt", control = "ctrl", shift

    public var modifiers: KeyCombo.Modifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }

    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    /// The key whose modifiers are exactly these, if one is.
    public init?(_ modifiers: KeyCombo.Modifiers) {
        guard let key = Self.allCases.first(where: { $0.modifiers == modifiers }) else { return nil }
        self = key
    }

    /// The key a word names on its own, as the config file writes it ("opt", "option", "alt", "⌥").
    public init?(word: String) {
        let names: [String: ModifierKey] = ["cmd": .command, "command": .command, "⌘": .command,
                                            "opt": .option, "option": .option, "alt": .option, "⌥": .option,
                                            "ctrl": .control, "control": .control, "⌃": .control,
                                            "shift": .shift, "⇧": .shift]
        guard let key = names[word.trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }
        self = key
    }

    /// Its keys' codes, left then right.
    public var keyCodes: [UInt16] {
        switch self {
        case .command: [55, 54]
        case .option: [58, 61]
        case .control: [59, 62]
        case .shift: [56, 60]
        }
    }
}

extension KeyCombo {
    /// A modifier tapped on its own, which can start keys in a row (⌥, then H, O, I): its left key,
    /// with no modifiers.
    public static func tap(_ key: ModifierKey) -> KeyCombo { KeyCombo(keyCode: key.keyCodes[0], modifiers: []) }

    /// The modifier these keys tap on its own, if that's what they are.
    public var tappedModifier: ModifierKey? {
        modifiers.isEmpty ? ModifierKey.allCases.first { $0.keyCodes.contains(keyCode) } : nil
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
    /// Tapping this modifier twice, quickly, on its own.
    case doubleTap(ModifierKey)
    /// Holding these keys down a moment (`KeyRouter.holdDelay`); let go sooner, they're pressed as usual.
    case hold(KeyCombo)
    /// Pressing these keys one after another, each soon after the last (`KeyRouter.sequenceGap`).
    case sequence([KeyCombo])

    public var kind: Kind {
        switch self {
        case .keys: .keys
        case .mouseButton: .mouseButton
        case .appOpens: .appOpens
        case .typed: .typed
        case .time: .time
        case .doubleTap: .doubleTap
        case .hold: .hold
        case .sequence: .sequence
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case keys, mouseButton, appOpens, typed, time, doubleTap, hold, sequence

        /// As the editor's Trigger menu says it, after "When".
        public var title: String {
            switch self {
            case .keys: "I press keys"
            case .mouseButton: "I click a mouse button"
            case .appOpens: "An app opens"
            case .typed: "I type some letters"
            case .time: "It's a set time"
            case .doubleTap: "I double-tap a modifier"
            case .hold: "I hold keys down"
            case .sequence: "I press keys in a row"
            }
        }

        public var symbol: String {
            switch self {
            case .keys: "keyboard"
            case .mouseButton: "computermouse"
            case .appOpens: "macwindow"
            case .typed: "character.cursor.ibeam"
            case .time: "clock"
            case .doubleTap: "hand.tap"
            case .hold: "stopwatch"
            case .sequence: "list.number"
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
    /// The packs it's in, by name; none for none.
    public var packs: [String] = []
    /// Shows a notification each time it runs, with its name and what it did.
    public var notifies = false
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

    /// The notification it shows when it runs: its name, and its steps in a line.
    public var notice: (title: String, body: String) { (name, steps.map(\.summary).joined(separator: " · ")) }

    /// Its keys go straight to the app in front, and that is all it does.
    public var passesKeysThrough: Bool { steps == [.passThrough] }

    /// Whether pressing `keys` runs this trigger now.
    public func fires(on pressed: KeyCombo, context: AppContext, passthroughActive: Bool) -> Bool {
        starts.contains(.keys) && keys.contains(pressed) && worksHere(context, passthroughActive: passthroughActive)
    }

    /// Whether tapping `key` twice runs this trigger now.
    public func fires(onDoubleTap key: ModifierKey, context: AppContext, passthroughActive: Bool) -> Bool {
        starts.contains(.doubleTap(key)) && worksHere(context, passthroughActive: passthroughActive)
    }

    /// Whether holding `keys` down runs this trigger now.
    public func fires(onHolding keys: KeyCombo, context: AppContext, passthroughActive: Bool) -> Bool {
        starts.contains(.hold(keys)) && worksHere(context, passthroughActive: passthroughActive)
    }

    /// The keys-in-a-row this trigger starts with.
    public var sequences: [[KeyCombo]] {
        starts.compactMap { if case let .sequence(keys) = $0, keys.count > 1 { keys } else { nil } }
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
