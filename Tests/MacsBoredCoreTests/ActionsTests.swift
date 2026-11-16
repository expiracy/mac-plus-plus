import XCTest
@testable import MacsBoredCore

/// Actions: something that starts them (keys, a mouse button, an app opening, letters typed, a time),
/// then a few steps in order.
final class ActionsTests: XCTestCase {
    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }

    private let notes = AppRef(bundleID: "com.apple.Notes", name: "com.apple.Notes")
    private let mail = AppRef(bundleID: "com.apple.mail", name: "com.apple.mail")

    // MARK: - Steps

    func testSeveralStepsReadInOrder() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Start work", "keys": "hyper+W",
                         "steps": [{ "openApp": "com.apple.Notes" }, { "wait": 0.5 }, { "openApp": "com.apple.mail" },
                                   { "typeText": "Morning" }] }] }
        """).config)
        XCTAssertEqual(config.triggers.first?.steps, [.openApp(notes), .wait(0.5), .openApp(mail), .typeText("Morning")])
    }

    func testOneStepIsStillWrittenAsAnAction() {
        var config = MacsBoredConfig()
        config.triggers = [Trigger(name: "Notes", keys: [KeyCombo(text: "ctrl+opt+N")!], action: .openApp(notes))]
        let written = ConfigFile.written(config)
        XCTAssertTrue(written.contains(#""action": { "openApp": "com.apple.Notes" }"#), written)
        XCTAssertFalse(written.contains("steps"), written)
    }

    func testSeveralStepsAreWrittenAsSteps() throws {
        var config = MacsBoredConfig()
        config.triggers = [Trigger(name: "Start work", keys: [KeyCombo(text: "hyper+W")!],
                                   steps: [.openApp(notes), .wait(1), .openApp(mail)])]
        let written = ConfigFile.written(config)
        XCTAssertFalse(written.contains(#""action""#), written)
        let again = try XCTUnwrap(read(written).config)
        XCTAssertEqual(again.triggers.first?.steps, [.openApp(notes), .wait(1), .openApp(mail)])
    }

    func testAnActionNeedsAtLeastOneStep() {
        let issues = read(#"{ "triggers": [{ "name": "Empty", "keys": "hyper+E", "steps": [] }] }"#).issues
        XCTAssertTrue(issues.contains { !$0.isWarning && $0.message.contains("step") }, "\(issues)")
    }

    func testActionAndStepsTogetherIsAMistake() {
        let issues = read("""
        { "triggers": [{ "name": "Both", "keys": "hyper+E", "action": { "openApp": "com.apple.Notes" },
                         "steps": [{ "openApp": "com.apple.mail" }] }] }
        """).issues
        XCTAssertTrue(issues.contains { !$0.isWarning }, "\(issues)")
    }

    func testAWaitIsAPositiveNumberOfSeconds() {
        let issues = read(#"{ "triggers": [{ "name": "W", "keys": "hyper+E", "steps": [{ "wait": -1 }] }] }"#).issues
        XCTAssertTrue(issues.contains { !$0.isWarning && $0.message.contains("seconds") }, "\(issues)")
    }

    func testAWaitCanBeAnyLengthUpToAnHour() throws {
        let config = try XCTUnwrap(read(#"{ "triggers": [{ "name": "W", "keys": "hyper+E", "steps": [{ "wait": 0.3 }, { "wait": 90 }, { "wait": 3600 }] }] }"#).config)
        XCTAssertEqual(config.triggers.first?.steps, [.wait(0.3), .wait(90), .wait(3600)])
        let issues = read(#"{ "triggers": [{ "name": "W", "keys": "hyper+E", "steps": [{ "wait": 3601 }] }] }"#).issues
        XCTAssertTrue(issues.contains { !$0.isWarning && $0.message.contains("seconds") }, "\(issues)")
    }

    func testADraftWaitKeepsItsLengthWithinAnHour() {
        var step = EntryDraft.Step(.wait)
        step.seconds = 45
        XCTAssertEqual(step.action, .wait(45))
        step.seconds = 5000
        XCTAssertEqual(step.action, .wait(3600))
        step.seconds = 0
        XCTAssertEqual(step.action, .wait(0.1))
    }

    // MARK: - What starts it

    private let zoom = AppRef(bundleID: "us.zoom.xos", name: "us.zoom.xos")

    func testEachKindOfStartReadsAndIsWrittenBack() throws {
        let text = """
        { "triggers": [
          { "name": "Back", "mouseButton": 4, "action": { "sendKeys": "cmd+[" } },
          { "name": "Meeting", "appOpens": "us.zoom.xos", "action": { "runShortcut": "Meeting mode" } },
          { "name": "Sign-off", "typed": ";sig", "action": { "typeText": "Best, J" } },
          { "name": "Morning", "at": "09:00", "action": { "openApp": "com.apple.mail" } },
          { "name": "Notes", "keys": "ctrl+opt+N", "action": { "openApp": "com.apple.Notes" } }
        ] }
        """
        let reading = read(text)
        XCTAssertEqual(reading.issues, [])
        let triggers = try XCTUnwrap(reading.config).triggers
        XCTAssertEqual(triggers.map(\.starts), [[.mouseButton(4)], [.appOpens(zoom)], [.typed(";sig")], [.time(540)], [.keys]])
        let again = try XCTUnwrap(read(ConfigFile.written(try XCTUnwrap(reading.config))).config)
        XCTAssertEqual(again.triggers.map(\.starts), triggers.map(\.starts))
        XCTAssertFalse(ConfigFile.written(again).contains(#""name": "Back",\n      "keys""#))
    }

    func testSeveralThingsCanStartOneAction() throws {
        let text = """
        { "triggers": [{ "name": "Start work", "keys": ["hyper+W", "F13"], "mouseButton": [4, 5], "typed": [";w", ";work"],
                         "at": "09:00", "appOpens": ["com.apple.Notes"], "action": { "openApp": "com.apple.mail" } }] }
        """
        let reading = read(text)
        XCTAssertEqual(reading.issues, [])
        let trigger = try XCTUnwrap(reading.config?.triggers.first)
        XCTAssertEqual(trigger.keys, [KeyCombo(text: "hyper+W")!, KeyCombo(text: "F13")!])
        XCTAssertEqual(trigger.starts, [.keys, .mouseButton(4), .mouseButton(5), .appOpens(notes), .typed(";w"), .typed(";work"), .time(540)])
        let written = ConfigFile.written(try XCTUnwrap(reading.config))
        XCTAssertTrue(written.contains(#""mouseButton": [4, 5]"#), written)
        XCTAssertTrue(written.contains(#""at": "09:00""#), written)
        XCTAssertEqual(try XCTUnwrap(read(written).config).triggers.first?.starts, trigger.starts)
    }

    func testAnyOfItsTriggersRunsAnAction() {
        let keys = KeyCombo(text: "hyper+W")!
        let trigger = Trigger(name: "Start work", keys: [keys], steps: [.openApp(mail)],
                              starts: [.keys, .mouseButton(5), .appOpens(zoom), .time(540)])
        XCTAssertTrue(trigger.fires(on: keys, context: AppContext(), passthroughActive: false))
        XCTAssertTrue(trigger.fires(onMouseButton: 5, context: AppContext(), passthroughActive: false))
        XCTAssertFalse(trigger.fires(onMouseButton: 4, context: AppContext(), passthroughActive: false))
        XCTAssertTrue(trigger.fires(onOpening: "us.zoom.xos", context: AppContext()))
        XCTAssertTrue(trigger.fires(from: 539, to: 540, context: AppContext()))
    }

    func testLeftAndRightClicksAreNotTriggers() {
        let issues = read(#"{ "triggers": [{ "name": "Click", "mouseButton": 1, "action": { "wait": 1 } }] }"#).issues
        XCTAssertTrue(issues.contains { !$0.isWarning && $0.message.contains("mouseButton") }, "\(issues)")
    }

    func testTypedLettersNeedAtLeastTwo() {
        let issues = read(#"{ "triggers": [{ "name": "T", "typed": "x", "action": { "wait": 1 } }] }"#).issues
        XCTAssertTrue(issues.contains { !$0.isWarning && $0.message.contains("typed") }, "\(issues)")
    }

    func testKeysFireOnlyAKeysTrigger() {
        let keys = KeyCombo(text: "hyper+B")!
        var trigger = Trigger(name: "Back", keys: [keys], action: .sendKeys(KeyCombo(text: "cmd+[")!))
        XCTAssertTrue(trigger.fires(on: keys, context: AppContext(), passthroughActive: false))
        trigger.starts = [.mouseButton(4)]
        XCTAssertFalse(trigger.fires(on: keys, context: AppContext(), passthroughActive: false))
    }

    func testAMouseButtonFiresItsTriggerWhereItWorks() {
        let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
        let trigger = Trigger(name: "Back", keys: [], steps: [.sendKeys(KeyCombo(text: "cmd+[")!)], apps: [safari],
                              starts: [.mouseButton(4)])
        XCTAssertTrue(trigger.fires(onMouseButton: 4, context: AppContext(bundleID: "com.apple.Safari"), passthroughActive: false))
        XCTAssertFalse(trigger.fires(onMouseButton: 5, context: AppContext(bundleID: "com.apple.Safari"), passthroughActive: false))
        XCTAssertFalse(trigger.fires(onMouseButton: 4, context: AppContext(bundleID: "com.apple.Notes"), passthroughActive: false))
    }

    func testAnAppOpeningFiresItsTrigger() {
        let trigger = Trigger(name: "Meeting", keys: [], steps: [.runShortcut("Meeting mode")], starts: [.appOpens(zoom)])
        XCTAssertTrue(trigger.fires(onOpening: "us.zoom.xos", context: AppContext()))
        XCTAssertFalse(trigger.fires(onOpening: "com.apple.Notes", context: AppContext()))
        var off = trigger
        off.isEnabled = false
        XCTAssertFalse(off.fires(onOpening: "us.zoom.xos", context: AppContext()))
    }

    func testATimeFiresOnceAsTheClockReachesIt() {
        let trigger = Trigger(name: "Morning", keys: [], steps: [.openApp(mail)], starts: [.time(540)])
        XCTAssertTrue(trigger.fires(from: 539, to: 540, context: AppContext()))
        XCTAssertFalse(trigger.fires(from: 540, to: 540, context: AppContext()), "not again in the same minute")
        XCTAssertFalse(trigger.fires(from: 541, to: 542, context: AppContext()))
        XCTAssertTrue(trigger.fires(from: 530, to: 545, context: AppContext()), "a Mac asleep through it catches up on waking")
        let midnight = Trigger(name: "Midnight", keys: [], steps: [.openApp(mail)], starts: [.time(0)])
        XCTAssertTrue(midnight.fires(from: 1439, to: 0, context: AppContext()))
    }

    // MARK: - Typed letters

    func testTypedLettersFireTheirTriggerOnTheLastLetter() {
        let sig = Trigger(name: "Sign-off", keys: [], steps: [.typeText("Best, J")], starts: [.typed(";sig")])
        var typed = TypedLetters()
        XCTAssertNil(typed.add(";", triggers: [sig], context: AppContext()))
        XCTAssertNil(typed.add("s", triggers: [sig], context: AppContext()))
        XCTAssertNil(typed.add("i", triggers: [sig], context: AppContext()))
        let fired = typed.add("g", triggers: [sig], context: AppContext())
        XCTAssertEqual(fired?.trigger.id, sig.id)
        XCTAssertEqual(fired?.letters, ";sig", "so it knows how many to take back out")
        XCTAssertNil(typed.add("g", triggers: [sig], context: AppContext()), "it starts again after firing")
    }

    func testTypedLettersStartAgainAfterABreak() {
        let sig = Trigger(name: "Sign-off", keys: [], steps: [.typeText("Best, J")], starts: [.typed(";sig")])
        var typed = TypedLetters()
        for letter in [";", "s"] { _ = typed.add(letter, triggers: [sig], context: AppContext()) }
        typed.reset()
        for letter in ["i"] { _ = typed.add(letter, triggers: [sig], context: AppContext()) }
        XCTAssertNil(typed.add("g", triggers: [sig], context: AppContext()))
    }
}
