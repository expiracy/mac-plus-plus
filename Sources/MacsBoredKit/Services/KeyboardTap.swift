#if canImport(AppKit)
import AppKit
import MacsBoredCore

/// The keyboard event tap: every key-down, key-up and modifier change passes through `KeyRouter`
/// before the system acts on it. It also sees mouse buttons, for actions started by the middle or
/// side buttons, and watches what is typed, for actions started by typing a few letters. It runs on its own thread with its own run loop, so a slow main
/// thread (an app slow to answer Accessibility) never delays a key; the main thread only hands it a
/// fresh `KeyRouter.Setup` when something changes, and hears back about triggers and the pause.
///
/// It sits at the HID level, ahead of other apps' global shortcuts, and needs Accessibility.
final class KeyboardTap {
    /// Marks events this app posts itself, so the tap lets them by.
    static let ownEventTag: Int64 = 0x4D4B_4244   // "MKBD"

    /// Runs on the main thread when a decision needs the app (a trigger, the pause).
    var onDecision: (KeyDecision) -> Void = { _ in }

    private let lock = NSLock()
    private var _setup = KeyRouter.Setup(plan: .inactive, triggers: [], context: AppContext(),
                                         pauseKeys: nil, hyperKeyEnabled: false)
    private var router = KeyRouter()   // tap thread only
    private var typed = TypedLetters()   // tap thread only
    /// Mouse buttons whose click ran an action: their release goes nowhere too.
    private var takenButtons: Set<Int> = []   // tap thread only
    private var port: CFMachPort?
    private var thread: Thread?
    private(set) var isRunning = false

    var setup: KeyRouter.Setup {
        get { lock.lock(); defer { lock.unlock() }; return _setup }
        set { lock.lock(); _setup = newValue; lock.unlock() }
    }

    /// Starts the tap; false when macOS refuses it (no Accessibility yet).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
                                           userInfo: me)
                ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                     eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
                                     userInfo: me)
        else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "MacsBored keyboard tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off when it is slow once; put it straight back.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        case .leftMouseDown, .rightMouseDown:
            typed.reset()   // a click moves the caret: what was typed before no longer counts
            return Unmanaged.passUnretained(event)
        case .otherMouseDown, .otherMouseUp:
            return mouseButton(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventTag {
            return Unmanaged.passUnretained(event)
        }
        let phase: KeyEvent.Phase = type == .keyDown ? .down : type == .keyUp ? .up : .flagsChanged
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let key = KeyEvent(phase: phase, keyCode: keyCode, modifiers: FlagBits.modifiers(event.flags.rawValue),
                           isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                           time: Double(event.timestamp) / 1_000_000_000)
        let setup = self.setup
        let decision = router.route(key, setup)
        let swapped = setup.plan.isActive ? setup.plan.modifierLayout.swapped : nil

        if type == .keyDown {
            if decision == .pass, let typed = typedTrigger(event, key, setup) {
                // The last letter goes nowhere; the ones before it are taken back out.
                Self.pressDelete(times: typed.letters.count - 1)
                let id = typed.trigger.id
                DispatchQueue.main.async { [weak self] in self?.onDecision(.runTrigger(id)) }
                return nil
            }
            if decision != .pass { typed.reset() }
        }

        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case let .modify(code, modifiers):
            Self.rewrite(event, keyCode: code, modifiers: modifiers, swapped: swapped)
            return Unmanaged.passUnretained(event)
        case let .forward(pid, code, modifiers):
            guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
            Self.rewrite(copy, keyCode: code, modifiers: modifiers, swapped: swapped)
            copy.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
            copy.postToPid(pid_t(pid))
            return nil
        case .runTrigger, .togglePause:
            DispatchQueue.main.async { [weak self] in self?.onDecision(decision) }
            return nil
        case let .runAlongside(id):
            DispatchQueue.main.async { [weak self] in self?.onDecision(.runTrigger(id)) }
            return Unmanaged.passUnretained(event)
        case let .beginHold(code):
            // Ask again once the keys have been held long enough, on this thread, where the router lives.
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + KeyRouter.holdDelay, 0, 0, 0) {
                [weak self] _ in
                guard let self, let id = self.router.holdElapsed(keyCode: code) else { return }
                DispatchQueue.main.async { [weak self] in self?.onDecision(.runTrigger(id)) }
            }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
            return nil
        case let .replay(code, modifiers):
            // Let go too soon for the hold: the keys as an ordinary press after all.
            Self.press(keyCode: code, modifiers: modifiers, swapped: swapped)
            return nil
        case .swallow:
            return nil
        }
    }

    /// Keys pressed and let go, marked as this app's own so the tap lets them by.
    private static func press(keyCode: UInt16, modifiers: KeyCombo.Modifiers, swapped: (KeyCombo.Modifiers, KeyCombo.Modifiers)?) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = CGEventFlags(rawValue: FlagBits.rewrite(0, to: modifiers, swapping: swapped))
            event.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// A middle or side button's click runs the action it starts, and its release goes with it.
    private func mouseButton(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
        if type == .otherMouseUp {
            return takenButtons.remove(number) != nil ? nil : Unmanaged.passUnretained(event)
        }
        typed.reset()
        let setup = self.setup
        guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventTag,
              let trigger = setup.triggers.first(where: {
                  $0.fires(onMouseButton: number, context: setup.context, passthroughActive: setup.plan.isActive)
              }) else { return Unmanaged.passUnretained(event) }
        takenButtons.insert(number)
        DispatchQueue.main.async { [weak self] in self?.onDecision(.runTrigger(trigger.id)) }
        return nil
    }

    /// The action whose letters this key finishes typing, if any. A shortcut (⌘ or ⌃ held), or a key
    /// that types nothing (an arrow, ⌫, return), starts the letters again.
    private func typedTrigger(_ event: CGEvent, _ key: KeyEvent, _ setup: KeyRouter.Setup) -> (trigger: Trigger, letters: String)? {
        guard TypedLetters.watches(setup.triggers) else { return nil }
        guard key.modifiers.isDisjoint(with: [.command, .control]) else { typed.reset(); return nil }
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            typed.reset()
            return nil
        }
        return typed.add(text, triggers: setup.triggers, context: setup.context)
    }

    /// ⌫, pressed and let go, `times` times.
    private static func pressDelete(times: Int) {
        guard times > 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<times {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: down) else { continue }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private static func rewrite(_ event: CGEvent, keyCode: UInt16, modifiers: KeyCombo.Modifiers,
                                swapped: (KeyCombo.Modifiers, KeyCombo.Modifiers)?) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = CGEventFlags(rawValue: FlagBits.rewrite(event.flags.rawValue, to: modifiers,
                                                              swapping: swapped))
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
#endif
