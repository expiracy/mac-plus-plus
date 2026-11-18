import XCTest
@testable import MacsBoredCore

/// Keys in a row that start with a modifier tapped on its own (⌥, then H, O, I), and the step that
/// chooses an item from the app's menus.
final class TapRowAndMenuItemTests: XCTestCase {
    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }
    private func keys(_ text: String) -> KeyCombo { KeyCombo(text: text)! }
    private func issues(_ text: String) -> [ConfigFile.Issue] { read(text).issues.filter { !$0.isWarning } }

    private func roundTrip(_ trigger: Trigger) throws -> Trigger {
        var config = MacsBoredConfig()
        config.triggers = [trigger]
        let written = ConfigFile.written(config)
        return try XCTUnwrap(read(written).config?.triggers.first, written)
    }

    private func setup(_ triggers: [Trigger]) -> KeyRouter.Setup {
        KeyRouter.Setup(plan: .inactive, triggers: triggers, context: AppContext(), pauseKeys: nil, hyperKeyEnabled: false)
    }

    private func trigger(_ start: TriggerStart) -> Trigger {
        Trigger(name: "T", keys: [], steps: [.openApp(AppRef(bundleID: "com.apple.Notes", name: "Notes"))], starts: [start])
    }

    private func flags(_ modifiers: KeyCombo.Modifiers, at time: Double, key: UInt16 = 58) -> KeyEvent {
        KeyEvent(phase: .flagsChanged, keyCode: key, modifiers: modifiers, time: time)
    }

    private func down(_ combo: KeyCombo, at time: Double) -> KeyEvent {
        KeyEvent(phase: .down, keyCode: combo.keyCode, modifiers: combo.modifiers, time: time)
    }

    private var hoi: [KeyCombo] { [.tap(.option), keys("h"), keys("o"), keys("i")] }

    // MARK: - A row that starts with a tap

    func testTappingOptionThenLettersRunsOnTheLast() {
        let t = trigger(.sequence(hoi))
        var router = KeyRouter()
        XCTAssertEqual(router.route(flags(.option, at: 0), setup([t])), .pass)
        XCTAssertEqual(router.route(flags([], at: 0.1), setup([t])), .pass)
        XCTAssertEqual(router.route(down(keys("h"), at: 0.4), setup([t])), .swallow)
        XCTAssertEqual(router.route(down(keys("o"), at: 0.7), setup([t])), .swallow)
        XCTAssertEqual(router.route(down(keys("i"), at: 1.0), setup([t])), .runTrigger(t.id))
        XCTAssertEqual(router.route(down(keys("h"), at: 1.5), setup([t])), .pass)
    }

    func testTheLettersWithoutTheTapAreTyped() {
        let t = trigger(.sequence(hoi))
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(keys("h"), at: 0), setup([t])), .pass)
        XCTAssertEqual(router.route(down(keys("o"), at: 0.2), setup([t])), .pass)
    }

    func testOptionHeldOrUsedWithAKeyIsNotATap() {
        let t = trigger(.sequence(hoi))
        var held = KeyRouter()
        _ = held.route(flags(.option, at: 0), setup([t]))
        _ = held.route(flags([], at: 1.0), setup([t]))
        XCTAssertEqual(held.route(down(keys("h"), at: 1.2), setup([t])), .pass)

        var chord = KeyRouter()
        _ = chord.route(flags(.option, at: 0), setup([t]))
        _ = chord.route(down(keys("opt+x"), at: 0.05), setup([t]))
        _ = chord.route(flags([], at: 0.1), setup([t]))
        XCTAssertEqual(chord.route(down(keys("h"), at: 0.3), setup([t])), .pass)
    }

    func testTheRightOptionKeyTapsToo() {
        let t = trigger(.sequence(hoi))
        var router = KeyRouter()
        _ = router.route(flags(.option, at: 0, key: 61), setup([t]))
        _ = router.route(flags([], at: 0.1, key: 61), setup([t]))
        XCTAssertEqual(router.route(down(keys("h"), at: 0.3), setup([t])), .swallow)
    }

    // MARK: - In the file, and in words

    func testATapFirstInARowReadsAndWrites() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "AutoFit", "sequence": ["opt", "h", "o", "i"], "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        let trigger = try XCTUnwrap(config.triggers.first)
        XCTAssertEqual(trigger.starts, [.sequence(hoi)])
        XCTAssertEqual(try roundTrip(trigger).starts, trigger.starts)
    }

    func testATapIsOnlyForTheStartOfARow() {
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "sequence": ["ctrl+a", "opt"], "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "keys": "opt", "action": { "openApp": "com.apple.Notes" } }] }"#).isEmpty)
    }

    func testATapReadsAsItsSymbol() {
        XCTAssertEqual(KeyCombo.tap(.option).displayName, "⌥")
        XCTAssertEqual(KeyCombo.tap(.command).tappedModifier, .command)
        XCTAssertNil(keys("opt+h").tappedModifier)
        var draft = EntryDraft(whens: [.sequence], steps: [.moveWindow])
        draft.sequence = hoi
        XCTAssertEqual(draft.sentence, "When I press ⌥ then H then O then I, move the window to the left half.")
    }

    // MARK: - Choosing a menu item

    private var autoFit: MenuPath { MenuPath(["Format", "Column", "AutoFit Selection"]) }

    func testAMenuItemReadsAsAListOrAPathAndWritesAsAList() throws {
        let listed = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Fit", "keys": "hyper+F", "action": { "chooseMenuItem": ["Format", "Column", "AutoFit Selection"] } }] }
        """).config)
        XCTAssertEqual(listed.triggers.first?.steps, [.chooseMenuItem(autoFit)])
        let path = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Fit", "keys": "hyper+F", "action": { "chooseMenuItem": "Format > Column > AutoFit Selection" } }] }
        """).config)
        XCTAssertEqual(path.triggers.first?.steps, [.chooseMenuItem(autoFit)])
        let trigger = Trigger(name: "Fit", keys: [keys("hyper+F")], action: .chooseMenuItem(autoFit))
        XCTAssertEqual(try roundTrip(trigger).steps, [.chooseMenuItem(autoFit)])
        var config = MacsBoredConfig()
        config.triggers = [trigger]
        let written = try JSONNode.parse(ConfigFile.written(config))
        XCTAssertEqual(written["triggers"]?.array?.first?["action"]?["chooseMenuItem"]?.array?.compactMap(\.string),
                       ["Format", "Column", "AutoFit Selection"])
    }

    func testAMenuItemNeedsAMenuAndAnItem() {
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "action": { "chooseMenuItem": ["Format"] } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "action": { "chooseMenuItem": "" } }] }"#).isEmpty)
        XCTAssertFalse(issues(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "action": { "chooseMenuItem": ["Format", " "] } }] }"#).isEmpty)
    }

    func testAMenuItemInWords() {
        XCTAssertEqual(TriggerAction.chooseMenuItem(autoFit).summary, "Chooses Format › Column › AutoFit Selection")
        var draft = EntryDraft(whens: [.sequence], steps: [.chooseMenuItem])
        draft.sequence = hoi
        XCTAssertEqual(draft.sentence, "When I press ⌥ then H then O then I, choose a menu item.")
        draft.steps[0].menuPath = autoFit
        XCTAssertEqual(draft.sentence, "When I press ⌥ then H then O then I, choose Format › Column › AutoFit Selection.")
    }

    func testTheDraftStepNeedsItsMenuItem() {
        var step = EntryDraft.Step(.chooseMenuItem)
        XCTAssertEqual(step.missing, "Choose the menu item")
        step.menuPath = MenuPath(["Format"])
        XCTAssertEqual(step.missing, "Choose the menu item")
        step.menuPath = autoFit
        XCTAssertEqual(step.action, .chooseMenuItem(autoFit))
        XCTAssertEqual(EntryDraft.Step(.chooseMenuItem(autoFit)).menuPath, autoFit)
    }

    func testAMenuTitleMatchesWhateverItsCaseOrDots() {
        XCTAssertTrue(MenuPath.matches("AutoFit Selection", "AutoFit Selection"))
        XCTAssertTrue(MenuPath.matches("autofit selection", "AutoFit Selection"))
        XCTAssertTrue(MenuPath.matches("Paste Special", "Paste Special…"))
        XCTAssertTrue(MenuPath.matches("Paste Special...", "Paste Special…"))
        XCTAssertFalse(MenuPath.matches("Column", "Columns"))
        XCTAssertFalse(MenuPath.matches("", ""))
    }
}
