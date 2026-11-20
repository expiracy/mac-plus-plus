import Foundation

/// One keyboard event as the event tap sees it.
public struct KeyEvent: Equatable, Sendable {
    public enum Phase: Sendable { case down, up, flagsChanged }

    public var phase: Phase
    public var keyCode: UInt16
    public var modifiers: KeyCombo.Modifiers
    public var isRepeat: Bool
    /// When it happened, in seconds on any steady clock: for double taps and keys in a row.
    public var time: Double

    public init(phase: Phase, keyCode: UInt16, modifiers: KeyCombo.Modifiers, isRepeat: Bool = false, time: Double = 0) {
        self.phase = phase
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.time = time
    }
}

/// What the tap does with an event.
public enum KeyDecision: Equatable, Sendable {
    /// Let it go on unchanged.
    case pass
    /// Let it go on with another key code or modifiers.
    case modify(keyCode: UInt16, modifiers: KeyCombo.Modifiers)
    /// Take it from the system and post it to this app alone.
    case forward(pid: Int32, keyCode: UInt16, modifiers: KeyCombo.Modifiers)
    /// Take it and run the trigger.
    case runTrigger(UUID)
    /// Let it go on, and run the trigger too (a modifier double-tapped: macOS still sees it).
    case runAlongside(UUID)
    /// Take it, and ask again in `KeyRouter.holdDelay` (`holdElapsed`) whether it is still held.
    case beginHold(keyCode: UInt16)
    /// Keys held for an action but let go too soon: press them after all, down and up.
    case replay(keyCode: UInt16, modifiers: KeyCombo.Modifiers)
    /// Take it and pause or resume passthrough.
    case togglePause
    /// Take it and do nothing.
    case swallow
}

/// Decides, event by event, what the keyboard does: the Hyper key, the pause keys, your triggers,
/// then passthrough. It remembers only what spans events: whether Hyper is held, and where each
/// held key's key-up belongs.
public struct KeyRouter: Sendable {
    public struct Setup: Sendable {
        public var plan: PassthroughPlan
        public var triggers: [Trigger]
        public var context: AppContext
        public var pauseKeys: KeyCombo?
        public var hyperKeyEnabled: Bool

        public init(plan: PassthroughPlan, triggers: [Trigger], context: AppContext, pauseKeys: KeyCombo?,
                    hyperKeyEnabled: Bool) {
            self.plan = plan
            self.triggers = triggers
            self.context = context
            self.pauseKeys = pauseKeys
            self.hyperKeyEnabled = hyperKeyEnabled
        }
    }

    /// Caps Lock (remapped to F18) is down, so every key gets ⌃⌥⇧⌘.
    private var hyperHeld = false
    /// Keys whose key-down went to a passthrough app: their key-up goes there too, even if another
    /// app has come to the front meanwhile, so the session never sees a key stuck down.
    private var forwardedUps: [UInt16: (pid: Int32, layout: ModifierLayout)] = [:]
    /// Keys whose key-down ran a trigger or the pause: their key-up (and repeats) go nowhere.
    private var takenUps: Set<UInt16> = []
    /// Keys being held for an action: which, the action, and whether it has run yet.
    private var holding: (keyCode: UInt16, modifiers: KeyCombo.Modifiers, trigger: UUID, ran: Bool)?
    /// A modifier tapped once on its own, and when it was let go; nil until it is let go.
    private var tapped: (key: ModifierKey, pressedAt: Double, releasedAt: Double?)?
    /// Keys in a row under way: the triggers still possible, how many keys are in, and the last's time.
    private var row: (triggers: [UUID], count: Int, at: Double)?

    /// How long keys are held before the action they start runs.
    public static let holdDelay = 0.4
    /// The longest between the taps of a double tap, and a tap's own length.
    public static let doubleTapGap = 0.35
    /// The longest between keys in a row.
    public static let sequenceGap = 1.5

    public init() {}

    public mutating func route(_ event: KeyEvent, _ setup: Setup) -> KeyDecision {
        if !setup.hyperKeyEnabled { hyperHeld = false }
        if setup.hyperKeyEnabled, event.keyCode == KeyCombo.Code.f18, event.phase != .flagsChanged {
            hyperHeld = event.phase == .down
            return .swallow
        }
        let held = hyperHeld && event.phase != .flagsChanged ? event.modifiers.union(.hyper) : event.modifiers

        if event.phase == .flagsChanged {
            if let trigger = doubleTap(event, setup) { return .runAlongside(trigger) }
        } else if event.phase == .down, !event.isRepeat {
            tapped = nil   // a modifier tapped with a key is a shortcut, not a tap
        }

        switch event.phase {
        case .up:
            if let held = holding, held.keyCode == event.keyCode {
                holding = nil
                return held.ran ? .swallow : .replay(keyCode: held.keyCode, modifiers: held.modifiers)
            }
            if let owner = forwardedUps.removeValue(forKey: event.keyCode) {
                let (code, modifiers) = Self.remap(event.keyCode, held, phase: .up, layout: owner.layout)
                return .forward(pid: owner.pid, keyCode: code, modifiers: modifiers)
            }
            if takenUps.remove(event.keyCode) != nil { return .swallow }
        case .down:
            let keys = KeyCombo(keyCode: event.keyCode, modifiers: held)
            if let holding, holding.keyCode == event.keyCode, event.isRepeat { return .swallow }
            if !event.isRepeat { holding = nil }   // another key while holding: neither is a hold
            if let decision = continueRow(keys, event, setup) { return decision }
            if keys == setup.pauseKeys {
                takenUps.insert(event.keyCode)
                return event.isRepeat ? .swallow : .togglePause
            }
            if let trigger = setup.triggers.first(where: {
                $0.fires(on: keys, context: setup.context, passthroughActive: setup.plan.isActive)
            }) {
                if trigger.passesKeysThrough {
                    // Its own keys, straight to the app in front, ahead of macOS and other apps.
                    guard let pid = setup.context.processID else { return .pass }
                    forwardedUps[event.keyCode] = (pid, .asIs)
                    return .forward(pid: pid, keyCode: event.keyCode, modifiers: held)
                }
                takenUps.insert(event.keyCode)
                return event.isRepeat ? .swallow : .runTrigger(trigger.id)
            }
            if !event.isRepeat, let trigger = setup.triggers.first(where: {
                $0.fires(onHolding: keys, context: setup.context, passthroughActive: setup.plan.isActive)
            }) {
                holding = (event.keyCode, held, trigger.id, false)
                return .beginHold(keyCode: event.keyCode)
            }
            if !event.isRepeat, let decision = startRow(keys, event, setup) { return decision }
        case .flagsChanged:
            break
        }
        return passthrough(event, modifiers: held, plan: setup.plan)
    }

    /// The keys held since `beginHold` still are: the action to run now, once.
    public mutating func holdElapsed(keyCode: UInt16) -> UUID? {
        guard let held = holding, held.keyCode == keyCode, !held.ran else { return nil }
        holding?.ran = true
        return held.trigger
    }

    /// A modifier pressed on its own soon after it was tapped once: the trigger it starts. Any other
    /// change of modifiers starts again.
    private mutating func doubleTap(_ event: KeyEvent, _ setup: Setup) -> UUID? {
        let now = event.time
        guard let key = ModifierKey(event.modifiers) else {
            if event.modifiers.isEmpty, let tap = tapped, tap.releasedAt == nil, now - tap.pressedAt <= Self.doubleTapGap {
                tapped?.releasedAt = now   // let go of, quickly: one tap
                startRow(tapping: tap.key, at: now, setup)
            } else {
                tapped = nil
            }
            return nil
        }
        if let tap = tapped, tap.key == key, let released = tap.releasedAt, now - released <= Self.doubleTapGap {
            tapped = nil
            return setup.triggers.first {
                $0.fires(onDoubleTap: key, context: setup.context, passthroughActive: setup.plan.isActive)
            }?.id
        }
        tapped = (key, now, nil)
        return nil
    }

    /// The first keys of a row: taken, and remembered, when some trigger's row starts with them.
    private mutating func startRow(_ keys: KeyCombo, _ event: KeyEvent, _ setup: Setup) -> KeyDecision? {
        let starting = setup.triggers.filter { trigger in
            trigger.sequences.contains { $0.first == keys }
                && trigger.worksHere(setup.context, passthroughActive: setup.plan.isActive)
        }
        guard !starting.isEmpty else { return nil }
        row = (starting.map(\.id), 1, event.time)
        takenUps.insert(event.keyCode)
        return .swallow
    }

    /// A modifier tapped on its own: a row starts, when some trigger's row starts with that tap. The
    /// tap itself has gone through as usual; nothing is taken until the next key.
    private mutating func startRow(tapping key: ModifierKey, at time: Double, _ setup: Setup) {
        let starting = setup.triggers.filter { trigger in
            trigger.sequences.contains { $0.first?.tappedModifier == key }
                && trigger.worksHere(setup.context, passthroughActive: setup.plan.isActive)
        }
        if !starting.isEmpty { row = (starting.map(\.id), 1, time) }
    }

    /// The next keys of a row under way: taken while some row still fits, its action run when one is
    /// complete. Other keys, or keys too late, end the row and go on as usual.
    private mutating func continueRow(_ keys: KeyCombo, _ event: KeyEvent, _ setup: Setup) -> KeyDecision? {
        guard let current = row, !event.isRepeat else { return nil }
        row = nil
        guard event.time - current.at <= Self.sequenceGap else { return nil }
        let index = current.count
        let fitting = setup.triggers.filter { trigger in
            current.triggers.contains(trigger.id)
                && trigger.sequences.contains { $0.count > index && $0[index] == keys }
        }
        guard !fitting.isEmpty else { return nil }
        takenUps.insert(event.keyCode)
        if let done = fitting.first(where: { $0.sequences.contains { $0.count == index + 1 && $0[index] == keys } }) {
            return .runTrigger(done.id)
        }
        row = (fitting.map(\.id), index + 1, event.time)
        return .swallow
    }

    /// The front app's passthrough: its modifier layout, and, when it captures every key, the key
    /// itself posted straight to it. Modifier keys alone always travel the ordinary way, so the
    /// system's idea of what is held stays right.
    private mutating func passthrough(_ event: KeyEvent, modifiers: KeyCombo.Modifiers,
                                      plan: PassthroughPlan) -> KeyDecision {
        let layout = plan.isActive ? plan.modifierLayout : .asIs
        let (code, mapped) = Self.remap(event.keyCode, modifiers, phase: event.phase, layout: layout)
        if plan.isActive, plan.captureAllKeys, event.phase != .flagsChanged, let pid = plan.processID {
            if event.phase == .down { forwardedUps[event.keyCode] = (pid, layout) }
            return .forward(pid: pid, keyCode: code, modifiers: mapped)
        }
        return code == event.keyCode && mapped == event.modifiers ? .pass : .modify(keyCode: code, modifiers: mapped)
    }

    /// The key and modifiers as `layout` has them reach the app.
    static func remap(_ keyCode: UInt16, _ modifiers: KeyCombo.Modifiers, phase: KeyEvent.Phase,
                      layout: ModifierLayout) -> (UInt16, KeyCombo.Modifiers) {
        guard let (a, b) = layout.swapped else { return (keyCode, modifiers) }
        var swapped = modifiers.subtracting([a, b])
        if modifiers.contains(a) { swapped.insert(b) }
        if modifiers.contains(b) { swapped.insert(a) }
        guard phase == .flagsChanged, let (left, right) = keys(a), let (otherLeft, otherRight) = keys(b) else {
            return (keyCode, swapped)
        }
        // The modifier key itself, going down or up, reads as the other one, on the same side.
        let keys = [left: otherLeft, otherLeft: left, right: otherRight, otherRight: right]
        return (keys[keyCode] ?? keyCode, swapped)
    }

    /// A swappable modifier's left and right keys.
    private static func keys(_ modifier: KeyCombo.Modifiers) -> (UInt16, UInt16)? {
        switch modifier {
        case .command: (KeyCombo.Code.leftCommand, KeyCombo.Code.rightCommand)
        case .control: (KeyCombo.Code.leftControl, KeyCombo.Code.rightControl)
        case .option: (KeyCombo.Code.leftOption, KeyCombo.Code.rightOption)
        default: nil
        }
    }
}
