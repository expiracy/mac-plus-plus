import Foundation

/// What the editor holds while you set up an action: what starts it (any of several triggers, each
/// with one value or several: keys, mouse buttons, apps opening, letters typed, times), then what it
/// does, step by step, then where and when it works. "An app is in front" is passthrough, and stands
/// alone: it makes a passthrough app, which needs no steps (it sends the app its keys). Changing the
/// triggers never loses the steps, the apps or the conditions; `result` is what it all makes now.
public struct EntryDraft: Equatable, Sendable {
    /// What sets it off, as the editor's Trigger menu offers it.
    public enum When: String, CaseIterable, Sendable {
        case keys, doubleTap, hold, sequence, mouseButton, appOpens, appInFront, typed, time

        public var title: String {
            switch self {
            case .keys: "I press keys"
            case .mouseButton: "I click a mouse button"
            case .appOpens: "An app opens"
            case .appInFront: "An app is in front"
            case .typed: "I type some letters"
            case .time: "It's a set time"
            case .doubleTap: TriggerStart.Kind.doubleTap.title
            case .hold: TriggerStart.Kind.hold.title
            case .sequence: TriggerStart.Kind.sequence.title
            }
        }

        public var symbol: String {
            switch self {
            case .appInFront: "arrow.right.to.line"
            case .doubleTap: TriggerStart.Kind.doubleTap.symbol
            case .hold: TriggerStart.Kind.hold.symbol
            case .sequence: TriggerStart.Kind.sequence.symbol
            case .keys: TriggerStart.Kind.keys.symbol
            case .mouseButton: TriggerStart.Kind.mouseButton.symbol
            case .appOpens: TriggerStart.Kind.appOpens.symbol
            case .typed: TriggerStart.Kind.typed.symbol
            case .time: TriggerStart.Kind.time.symbol
            }
        }
    }

    /// One step being set up: its kind, and whatever that kind needs (keys, an app, text or seconds).
    public struct Step: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var kind: TriggerAction.Kind
        public var keys: KeyCombo?
        public var app: AppRef?
        /// The link or file, the Shortcut's name, the text to type, or the script.
        public var text = ""
        public var seconds = 1.0
        public var language = Script.Language.shell
        public var place = WindowPlace.leftHalf
        public var preset: PresetRef?

        public init(_ kind: TriggerAction.Kind) {
            id = UUID()
            self.kind = kind
        }

        public init(_ action: TriggerAction) {
            self.init(action.kind)
            switch action {
            case let .sendKeys(keys): self.keys = keys
            case let .openApp(app): self.app = app
            case let .open(target), let .runShortcut(target), let .typeText(target): text = target
            case let .wait(seconds): self.seconds = seconds
            case .passThrough: break
            case let .runScript(script): text = script.source; language = script.language
            case let .moveWindow(place): self.place = place
            case let .applyPreset(preset): self.preset = preset
            }
        }

        /// The step as the trigger runs it, or nil while it still needs something.
        public var action: TriggerAction? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            switch kind {
            case .sendKeys: return keys.map { .sendKeys($0) }
            case .openApp: return app.map { .openApp($0) }
            case .open: return trimmed.isEmpty ? nil : .open(trimmed)
            case .runShortcut: return trimmed.isEmpty ? nil : .runShortcut(text)
            case .typeText: return text.isEmpty ? nil : .typeText(text)
            case .wait: return .wait(min(max(seconds, 0.1), TriggerAction.longestWait))
            case .passThrough: return .passThrough
            case .runScript:
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .runScript(Script(language, text))
            case .moveWindow: return .moveWindow(place)
            case .applyPreset: return preset.flatMap { $0.id.isEmpty ? nil : .applyPreset($0) }
            }
        }

        /// What the step still needs, as the bar says it.
        public var missing: String? {
            guard action == nil else { return nil }
            switch kind {
            case .sendKeys: return "Record the keys to press"
            case .openApp: return "Choose the app to open"
            case .open: return "Enter a link or file"
            case .runShortcut: return "Choose a Shortcut"
            case .typeText: return "Type the text to type"
            case .runScript: return "Write the script"
            case .applyPreset: return "Choose a preset"
            case .wait, .passThrough, .moveWindow: return nil
            }
        }

        /// "Open Notes", "Press ⌘←": the step in a few words, for the name.
        public var phrase: String {
            switch kind {
            case .sendKeys: return keys.map { "Press \($0.displayName)" } ?? "Press keys"
            case .openApp: return app.map { "Open \($0.name)" } ?? "Open an app"
            case .open:
                let target = text.trimmingCharacters(in: .whitespaces)
                if target.isEmpty { return "Open a link or file" }
                if target.contains("://") { return "Open " + (URL(string: target)?.host ?? target) }
                let last = (target as NSString).lastPathComponent
                return "Open " + (last.isEmpty ? target : last)
            case .runShortcut: return text.isEmpty ? "Run a Shortcut" : text
            case .typeText: return text.isEmpty ? "Type text" : "Type “\(text.prefix(24))”"
            case .wait: return "Wait \(seconds.formatted()) s"
            case .passThrough: return "Pass keys to the app"
            case .runScript:
                let line = Script(language, text).firstLine
                return line.isEmpty ? "Run a script" : "Run “\(line.prefix(24))”"
            case .moveWindow: return "Move the window to the \(place.title.lowercased())"
            case .applyPreset: return preset.map { $0.name.isEmpty ? "Arrange windows" : "Arrange windows as “\($0.name)”" } ?? "Arrange windows"
            }
        }
    }

    /// What the draft was opened on, so saving replaces it.
    public enum Origin: Equatable, Sendable {
        case new
        case trigger(UUID)
        case profile(UUID)
    }

    public enum Result: Equatable, Sendable {
        case trigger(Trigger)
        case profile(PassthroughProfile)
    }

    public var origin: Origin = .new
    /// The kinds of trigger chosen, in the order they were; any of them starts the action.
    public private(set) var whens: [When] = []
    /// Your own name; empty follows `suggestedName`.
    public var customName = ""
    public var isEnabled = true
    /// The keys that set it off: one, or several (say, each shortcut a session should get).
    public var keys: [KeyCombo] = []
    /// Modifiers that start it when tapped twice.
    public var doubleTaps: [ModifierKey] = []
    /// Keys that start it when held down a moment.
    public var holdKeys: [KeyCombo] = []
    /// Keys in a row that start it; the editor sets up the first (`sequence`), the rest are kept.
    public var sequences: [[KeyCombo]] = []
    public var mouseButtons: [Int] = []
    public var openingApps: [AppRef] = []
    /// Letters to type, several separated by spaces or commas (";sig ;s").
    public var letters = ""
    /// Minutes since midnight.
    public var times: [Int] = []
    public var steps: [Step] = []
    /// A trigger works only in `apps` (a passthrough app always does).
    public var onlyInApps = false
    public var apps: [AppRef] = []
    public var conditions = ConditionSet()
    public var systemShortcuts = SystemShortcutGroup.defaultSet
    public var captureAllKeys = false
    public var modifierLayout = ModifierLayout.asIs
    private var triggerExtra = JSONFields()
    private var profileExtra = JSONFields()
    /// The ID a new entry gets, fixed for the draft so the save replaces nothing else.
    private var newID = UUID()

    public init() {}

    /// A new action starting with these triggers and steps.
    public init(whens: [When], steps: [TriggerAction.Kind] = []) {
        whens.forEach { add($0) }
        self.steps = steps.map(Step.init)
    }

    public init(trigger: Trigger) {
        origin = .trigger(trigger.id)
        isEnabled = trigger.isEnabled
        keys = trigger.keys
        var typed: [String] = []
        for start in trigger.starts {
            let kind: When
            switch start {
            case .keys: kind = .keys
            case let .mouseButton(number): kind = .mouseButton; mouseButtons.append(number)
            case let .appOpens(app): kind = .appOpens; openingApps.append(app)
            case let .typed(text): kind = .typed; typed.append(text)
            case let .time(minutes): kind = .time; times.append(minutes)
            case let .doubleTap(key): kind = .doubleTap; doubleTaps.append(key)
            case let .hold(combo): kind = .hold; holdKeys.append(combo)
            case let .sequence(combos): kind = .sequence; sequences.append(combos)
            }
            if !whens.contains(kind) { whens.append(kind) }
        }
        letters = typed.joined(separator: " ")
        steps = trigger.steps.map(Step.init)
        apps = trigger.apps
        onlyInApps = !trigger.apps.isEmpty
        conditions = trigger.conditions
        triggerExtra = trigger.extra
        if trigger.name != suggestedName { customName = trigger.name }
    }

    public init(profile: PassthroughProfile) {
        origin = .profile(profile.id)
        whens = [.appInFront]
        isEnabled = profile.isEnabled
        apps = profile.apps
        onlyInApps = true
        conditions = profile.conditions
        systemShortcuts = profile.systemShortcuts
        captureAllKeys = profile.captureAllKeys
        modifierLayout = profile.modifierLayout
        profileExtra = profile.extra
        if profile.name != suggestedName { customName = profile.name }
    }

    /// The first trigger chosen, or nil before any is.
    public var when: When? { whens.first }

    /// A whole app passes through: the draft is a passthrough entry rather than a trigger.
    public var isPassthroughApp: Bool { whens == [.appInFront] }

    /// Adds a kind of trigger, with a first value where it needs one (the back button, 9:00). "An
    /// app is in front" stands alone, so adding it takes the others away, and adding another takes it.
    public mutating func add(_ when: When) {
        guard !whens.contains(when) else { return }
        if when == .appInFront { whens = [] } else { whens.removeAll { $0 == .appInFront } }
        whens.append(when)
        if when == .mouseButton && mouseButtons.isEmpty { mouseButtons = [4] }
        if when == .time && times.isEmpty { times = [9 * 60] }
        if when == .doubleTap && doubleTaps.isEmpty { doubleTaps = [.option] }
    }

    /// The keys in a row being set up: the first of `sequences`.
    public var sequence: [KeyCombo] {
        get { sequences.first ?? [] }
        set { if sequences.isEmpty { sequences = [newValue] } else { sequences[0] = newValue } }
    }

    public mutating func remove(_ when: When) {
        whens.removeAll { $0 == when }
    }

    /// Adds the kind when it's not there, takes it away when it is.
    public mutating func toggle(_ when: When) {
        if whens.contains(when) { remove(when) } else { add(when) }
    }

    public var name: String {
        let own = customName.trimmingCharacters(in: .whitespaces)
        return own.isEmpty ? suggestedName : own
    }

    /// A name that says what it does, used until you give your own.
    public var suggestedName: String {
        if isPassthroughApp { return apps.first?.name ?? "Passthrough app" }
        if steps.map(\.kind) == [.passThrough] {
            switch keys.count {
            case 0: return "Pass keys to the app"
            case 1: return "Pass \(keys[0].displayName) to the app"
            case 2: return "Pass \(keys[0].displayName) and \(keys[1].displayName) to the app"
            default: return "Pass \(keys.count) shortcuts to the app"
            }
        }
        let opened = steps.compactMap { $0.kind == .openApp ? $0.app?.name : nil }
        if steps.count > 1, opened.count == steps.count {
            return "Open " + ListFormatter.localizedString(byJoining: opened)
        }
        switch steps.count {
        case 0: return "New action"
        case 1: return steps[0].phrase
        default: return "\(steps[0].phrase), then \(steps.count - 1) more"
        }
    }

    /// Why it can't be saved yet, as the Save button's neighbour says it; nil when it can.
    public var missing: String? {
        guard !whens.isEmpty else { return "Choose a trigger to start" }
        if isPassthroughApp { return apps.isEmpty ? "Add an app to save" : nil }
        for when in whens {
            switch when {
            case .keys: if keys.isEmpty { return "Record the keys to save" }
            case .mouseButton: if mouseButtons.isEmpty { return "Choose a mouse button" }
            case .appOpens: if openingApps.isEmpty { return "Choose the app" }
            case .typed: if typedLetters == nil { return "Type at least two letters, no spaces" }
            case .time: if times.isEmpty { return "Choose a time" }
            case .doubleTap: if doubleTaps.isEmpty { return "Choose a modifier to double-tap" }
            case .hold: if holdKeys.isEmpty { return "Record the keys to hold" }
            case .sequence: if sequence.count < 2 { return "Record two or more keys in a row" }
            case .appInFront: break
            }
        }
        guard !steps.isEmpty else { return "Add a step to save" }
        if steps.contains(where: { $0.kind == .passThrough }) {
            if whens != [.keys] { return "Only keys can be sent to the app" }
            if steps.count > 1 { return "Sending keys to the app is a step on its own" }
        }
        for (index, step) in steps.enumerated() {
            if let missing = step.missing {
                guard steps.count > 1 else { return missing }
                return "Step \(index + 1): " + missing.prefix(1).lowercased() + missing.dropFirst()
            }
        }
        return nil
    }

    /// The letters typed, each at least two long; nil when there are none, or one is too short.
    private var typedLetters: [String]? {
        let parts = letters.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        return parts.isEmpty || parts.contains { $0.count < 2 } ? nil : parts
    }

    /// Every trigger, as the action keeps them; nil while one still needs something.
    private var starts: [TriggerStart]? {
        var starts: [TriggerStart] = []
        for when in whens {
            switch when {
            case .keys: starts.append(.keys)
            case .mouseButton: starts += mouseButtons.map { .mouseButton($0) }
            case .appOpens: starts += openingApps.map { .appOpens($0) }
            case .typed: guard let typed = typedLetters else { return nil }; starts += typed.map { .typed($0) }
            case .time: starts += times.map { .time($0) }
            case .doubleTap: starts += doubleTaps.map { .doubleTap($0) }
            case .hold: starts += holdKeys.map { .hold($0) }
            case .sequence: starts += sequences.filter { $0.count > 1 }.map { .sequence($0) }
            case .appInFront: return nil
            }
        }
        return starts.isEmpty ? nil : starts
    }

    private var triggerID: UUID {
        if case let .trigger(id) = origin { return id }
        return newID
    }

    private var profileID: UUID {
        if case let .profile(id) = origin { return id }
        return newID
    }

    public var trigger: Trigger? {
        guard let starts, !steps.isEmpty else { return nil }
        let actions = steps.compactMap(\.action)
        guard actions.count == steps.count else { return nil }
        return Trigger(id: triggerID, name: name, isEnabled: isEnabled, keys: whens.contains(.keys) ? keys : [],
                       steps: actions, apps: onlyInApps ? apps : [], conditions: conditions, starts: starts,
                       extra: triggerExtra)
    }

    public var profile: PassthroughProfile? {
        guard isPassthroughApp, !apps.isEmpty else { return nil }
        return PassthroughProfile(id: profileID, name: name, isEnabled: isEnabled, apps: apps, conditions: conditions,
                                  systemShortcuts: systemShortcuts, captureAllKeys: captureAllKeys,
                                  modifierLayout: modifierLayout, extra: profileExtra)
    }

    /// The action in a sentence, as far as it's set up: "When I press Hyper W or click button 4,
    /// open Notes, then open Safari." Nil before any trigger is chosen.
    public var sentence: String? {
        guard !whens.isEmpty else { return nil }
        if isPassthroughApp {
            let names = apps.map(\.name)
            return names.isEmpty ? "While an app you choose is in front, it gets your Mac's shortcuts."
                : "While \(Self.joined(names, "or")) is in front, it gets your Mac's shortcuts."
        }
        let when = Self.joined(whens.map(triggerPhrase), "or")
        let does: String
        switch steps.count {
        case 0: does = "…"
        case 1: does = Self.lower(steps[0].phrase)
        default: does = steps.dropLast().map { Self.lower($0.phrase) }.joined(separator: ", ")
            + ", then " + Self.lower(steps[steps.count - 1].phrase)
        }
        return "When \(when), \(does)" + (does.hasSuffix("…") ? "" : ".")
    }

    private func triggerPhrase(_ when: When) -> String {
        switch when {
        case .keys: return "I press " + (keys.isEmpty ? "keys" : Self.joined(keys.map(\.displayName), "or"))
        case .mouseButton:
            let names = mouseButtons.map { $0 == 3 ? "the middle button" : "button \($0)" }
            return "I click " + (names.isEmpty ? "a mouse button" : Self.joined(names, "or"))
        case .appOpens: return (openingApps.isEmpty ? "an app" : Self.joined(openingApps.map(\.name), "or")) + " opens"
        case .typed: return "I type " + (typedLetters.map { Self.joined($0, "or") } ?? "some letters")
        case .time: return "it's " + (times.isEmpty ? "a set time" : Self.joined(times.map(ConfigFile.clock), "or"))
        case .doubleTap:
            return "I double-tap " + (doubleTaps.isEmpty ? "a modifier" : Self.joined(doubleTaps.map(\.symbol), "or"))
        case .hold: return "I hold " + (holdKeys.isEmpty ? "keys" : Self.joined(holdKeys.map(\.displayName), "or"))
        case .sequence:
            return "I press " + (sequence.count < 2 ? "keys in a row" : sequence.map(\.displayName).joined(separator: " then "))
        case .appInFront: return "an app is in front"
        }
    }

    private static func lower(_ text: String) -> String { text.prefix(1).lowercased() + text.dropFirst() }

    /// "a, b or c".
    private static func joined(_ words: [String], _ last: String) -> String {
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " \(last) " + words[words.count - 1]
    }

    public var result: Result? {
        guard missing == nil else { return nil }
        if let profile { return .profile(profile) }
        return trigger.map { .trigger($0) }
    }
}
