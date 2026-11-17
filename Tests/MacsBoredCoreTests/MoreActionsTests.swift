import XCTest
@testable import MacsBoredCore

/// Scripts and window steps, and the keys that start an action by being double-tapped, held, or
/// pressed in a row.
final class MoreActionsTests: XCTestCase {
    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }
    private func keys(_ text: String) -> KeyCombo { KeyCombo(text: text)! }

    private func roundTrip(_ trigger: Trigger, file: StaticString = #filePath, line: UInt = #line) throws -> Trigger {
        var config = MacsBoredConfig()
        config.triggers = [trigger]
        let written = ConfigFile.written(config)
        let again = try XCTUnwrap(read(written).config, written, file: file, line: line)
        return try XCTUnwrap(again.triggers.first, file: file, line: line)
    }

    private func issues(_ text: String) -> [ConfigFile.Issue] { read(text).issues.filter { !$0.isWarning } }

    // MARK: - Scripts

    func testAScriptAsTextIsAShellScript() throws {
        let config = try XCTUnwrap(read(#"{ "triggers": [{ "name": "Say", "keys": "hyper+S", "action": { "runScript": "say hi" } }] }"#).config)
        XCTAssertEqual(config.triggers.first?.steps, [.runScript(Script(.shell, "say hi"))])
    }

    func testAnAppleScriptNamesItsLanguage() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Mute", "keys": "hyper+M",
                         "action": { "runScript": { "appleScript": "set volume output muted true" } } }] }
        """).config)
        XCTAssertEqual(config.triggers.first?.steps, [.runScript(Script(.appleScript, "set volume output muted true"))])
    }

    func testScriptsWriteAndReadBack() throws {
        let trigger = Trigger(name: "Both", keys: [keys("hyper+B")],
                              steps: [.runScript(Script(.shell, "echo \"one\"\necho two")),
                                      .runScript(Script(.appleScript, "beep"))])
        XCTAssertEqual(try roundTrip(trigger).steps, trigger.steps)
    }

    func testAnEmptyScriptIsAMistake() {
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "E", "keys": "hyper+E", "action": { "runScript": " " } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "E", "keys": "hyper+E", "action": { "runScript": { "python": "x" } } }] }"#).isEmpty)
    }

    func testTheFirstVersionsShellCommandsComeAcross() throws {
        let reading = read("""
        { "profiles": [], "passthroughEnabled": true,
          "triggers": [{ "name": "Hi", "shortcut": { "keyCode": 4, "modifiers": 8 },
                         "action": { "runShell": { "_0": "say hi" } } }] }
        """)
        let config = try XCTUnwrap(reading.config)
        XCTAssertEqual(config.triggers.first?.steps, [.runScript(Script(.shell, "say hi"))])
    }

    // MARK: - Windows

    func testMovingTheWindowReadsAndWrites() throws {
        let config = try XCTUnwrap(read(#"{ "triggers": [{ "name": "Left", "keys": "hyper+left", "action": { "moveWindow": "leftHalf" } }] }"#).config)
        XCTAssertEqual(config.triggers.first?.steps, [.moveWindow(.leftHalf)])
        let trigger = Trigger(name: "Max", keys: [keys("hyper+up")], action: .moveWindow(.maximize))
        XCTAssertEqual(try roundTrip(trigger).steps, [.moveWindow(.maximize)])
    }

    func testAPlaceTheWindowCantGoIsAMistake() {
        let found = issues(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "action": { "moveWindow": "sideways" } }] }"#)
        XCTAssertTrue(found.contains { $0.message.contains("leftHalf") }, "\(found)")
    }

    func testAPresetIsKeptByItsID() throws {
        let config = try XCTUnwrap(read(#"{ "triggers": [{ "name": "Code", "keys": "hyper+C", "action": { "applyPreset": "p-123" } }] }"#).config)
        XCTAssertEqual(config.triggers.first?.steps, [.applyPreset(PresetRef(id: "p-123", name: "p-123"))])
        let trigger = Trigger(name: "Code", keys: [keys("hyper+C")], action: .applyPreset(PresetRef(id: "p-9", name: "Coding")))
        XCTAssertEqual(try roundTrip(trigger).steps, [.applyPreset(PresetRef(id: "p-9", name: "p-9"))])
    }

    // MARK: - Keys double-tapped, held, or in a row, in the file

    func testTheNewKeyTriggersReadAndWrite() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Lots", "doubleTap": "opt", "hold": "hyper+space", "sequence": ["ctrl+a", "b"],
                         "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        let trigger = try XCTUnwrap(config.triggers.first)
        XCTAssertEqual(trigger.starts, [.doubleTap(.option), .hold(keys("hyper+space")), .sequence([keys("ctrl+a"), keys("b")])])
        XCTAssertEqual(try roundTrip(trigger).starts, trigger.starts)
    }

    func testSeveralSequencesAreAListOfLists() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Two", "sequence": [["ctrl+a", "b"], ["ctrl+a", "c"]], "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        XCTAssertEqual(config.triggers.first?.starts, [.sequence([keys("ctrl+a"), keys("b")]), .sequence([keys("ctrl+a"), keys("c")])])
    }

    func testTheNewKeyTriggersRefuseWhatWouldTakeOverTyping() {
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "hold": "a", "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "sequence": ["a", "b"], "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "sequence": ["ctrl+a"], "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "doubleTap": "fn", "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
    }

    // MARK: - The router

    private func setup(_ triggers: [Trigger]) -> KeyRouter.Setup {
        KeyRouter.Setup(plan: .inactive, triggers: triggers, context: AppContext(), pauseKeys: nil, hyperKeyEnabled: false)
    }

    private func trigger(_ start: TriggerStart) -> Trigger {
        Trigger(name: "T", keys: [], steps: [.openApp(AppRef(bundleID: "com.apple.Notes", name: "Notes"))], starts: [start])
    }

    private func flags(_ modifiers: KeyCombo.Modifiers, at time: Double, key: UInt16 = 58) -> KeyEvent {
        KeyEvent(phase: .flagsChanged, keyCode: key, modifiers: modifiers, time: time)
    }

    private func down(_ combo: KeyCombo, at time: Double = 0, repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(phase: .down, keyCode: combo.keyCode, modifiers: combo.modifiers, isRepeat: isRepeat, time: time)
    }

    private func up(_ combo: KeyCombo, at time: Double = 0) -> KeyEvent {
        KeyEvent(phase: .up, keyCode: combo.keyCode, modifiers: combo.modifiers, time: time)
    }

    func testDoubleTappingAModifierRunsItAndLetsTheModifierThrough() {
        let t = trigger(.doubleTap(.option))
        var router = KeyRouter()
        XCTAssertEqual(router.route(flags(.option, at: 0), setup([t])), .pass)
        XCTAssertEqual(router.route(flags([], at: 0.1), setup([t])), .pass)
        XCTAssertEqual(router.route(flags(.option, at: 0.25), setup([t])), .runAlongside(t.id))
        XCTAssertEqual(router.route(flags([], at: 0.3), setup([t])), .pass)
    }

    func testSlowTapsOrAKeyBetweenAreNotADoubleTap() {
        let t = trigger(.doubleTap(.option))
        var slow = KeyRouter()
        _ = slow.route(flags(.option, at: 0), setup([t]))
        _ = slow.route(flags([], at: 0.1), setup([t]))
        XCTAssertEqual(slow.route(flags(.option, at: 1.0), setup([t])), .pass)

        var typed = KeyRouter()
        _ = typed.route(flags(.option, at: 0), setup([t]))
        _ = typed.route(down(KeyCombo(keyCode: 0, modifiers: .option), at: 0.05), setup([t]))
        _ = typed.route(flags([], at: 0.1), setup([t]))
        XCTAssertEqual(typed.route(flags(.option, at: 0.2), setup([t])), .pass)

        var otherKey = KeyRouter()
        _ = otherKey.route(flags(.option, at: 0), setup([t]))
        _ = otherKey.route(flags([], at: 0.1), setup([t]))
        XCTAssertEqual(otherKey.route(flags(.command, at: 0.2, key: 55), setup([t])), .pass)
    }

    func testHoldingKeysRunsOnceTheyHaveBeenHeldLongEnough() {
        let combo = keys("ctrl+space")
        let t = trigger(.hold(combo))
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(combo), setup([t])), .beginHold(keyCode: combo.keyCode))
        XCTAssertEqual(router.route(down(combo, repeat: true), setup([t])), .swallow)
        XCTAssertEqual(router.holdElapsed(keyCode: combo.keyCode), t.id)
        XCTAssertNil(router.holdElapsed(keyCode: combo.keyCode))
        XCTAssertEqual(router.route(up(combo), setup([t])), .swallow)
    }

    func testLettingGoTooSoonPressesTheKeysAfterAll() {
        let combo = keys("ctrl+space")
        let t = trigger(.hold(combo))
        var router = KeyRouter()
        _ = router.route(down(combo), setup([t]))
        XCTAssertEqual(router.route(up(combo), setup([t])), .replay(keyCode: combo.keyCode, modifiers: combo.modifiers))
        XCTAssertNil(router.holdElapsed(keyCode: combo.keyCode))
    }

    func testKeysInARowRunOnTheLastAndTheFirstGoesNowhere() {
        let first = keys("ctrl+a"), second = keys("b")
        let t = trigger(.sequence([first, second]))
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(first, at: 0), setup([t])), .swallow)
        XCTAssertEqual(router.route(up(first, at: 0.1), setup([t])), .swallow)
        XCTAssertEqual(router.route(down(second, at: 0.5), setup([t])), .runTrigger(t.id))
        XCTAssertEqual(router.route(up(second, at: 0.6), setup([t])), .swallow)
        // Done: b on its own types again.
        XCTAssertEqual(router.route(down(second, at: 1), setup([t])), .pass)
    }

    func testAnotherKeyOrTooLongAGapEndsTheRow() {
        let first = keys("ctrl+a"), second = keys("b"), other = keys("c")
        let t = trigger(.sequence([first, second]))
        var wrong = KeyRouter()
        _ = wrong.route(down(first, at: 0), setup([t]))
        XCTAssertEqual(wrong.route(down(other, at: 0.3), setup([t])), .pass)
        XCTAssertEqual(wrong.route(down(second, at: 0.5), setup([t])), .pass)

        var late = KeyRouter()
        _ = late.route(down(first, at: 0), setup([t]))
        XCTAssertEqual(late.route(down(second, at: KeyRouter.sequenceGap + 0.5), setup([t])), .pass)
    }

    func testAPlainTriggerOnTheSameKeysStillWins() {
        let combo = keys("ctrl+space")
        let plain = Trigger(name: "P", keys: [combo], action: .openApp(AppRef(bundleID: "a", name: "a")))
        let held = trigger(.hold(combo))
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(combo), setup([plain, held])), .runTrigger(plain.id))
    }

    // MARK: - The editor's draft

    func testTheDraftBuildsTheNewKeyTriggers() throws {
        var draft = EntryDraft(whens: [.doubleTap, .hold, .sequence], steps: [.moveWindow])
        XCTAssertEqual(draft.missing, "Record the keys to hold")
        draft.holdKeys = [keys("hyper+space")]
        XCTAssertEqual(draft.missing, "Record two or more keys in a row")
        draft.sequence = [keys("ctrl+a"), keys("b")]
        let trigger = try XCTUnwrap(draft.trigger)
        XCTAssertEqual(trigger.starts, [.doubleTap(.option), .hold(keys("hyper+space")), .sequence([keys("ctrl+a"), keys("b")])])
        XCTAssertEqual(trigger.steps, [.moveWindow(.leftHalf)])
        XCTAssertEqual(EntryDraft(trigger: trigger).trigger?.starts, trigger.starts)
    }

    func testAScriptStepNeedsItsScript() {
        var step = EntryDraft.Step(.runScript)
        XCTAssertEqual(step.missing, "Write the script")
        step.text = "say hi"
        step.language = .appleScript
        XCTAssertEqual(step.action, .runScript(Script(.appleScript, "say hi")))
        XCTAssertEqual(EntryDraft.Step(.runScript(Script(.appleScript, "beep"))).language, .appleScript)
    }

    func testTheSentenceSaysTheNewTriggers() {
        var draft = EntryDraft(whens: [.doubleTap, .sequence], steps: [.moveWindow])
        draft.sequence = [keys("ctrl+a"), keys("b")]
        XCTAssertEqual(draft.sentence, "When I double-tap ⌥ or I press ⌃A then B, move the window to the left half.")
    }
}
