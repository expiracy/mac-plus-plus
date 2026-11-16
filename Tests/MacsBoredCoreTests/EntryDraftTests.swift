import XCTest
@testable import MacsBoredCore

/// The editor's one draft: what starts it (any of several triggers), then what it does, step by
/// step. "An app is in front" makes a passthrough app, on its own; everything else makes a trigger.
final class EntryDraftTests: XCTestCase {
    private let windows = AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")
    private let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")
    private let mail = AppRef(bundleID: "com.apple.mail", name: "Mail")
    private let zoom = AppRef(bundleID: "us.zoom.xos", name: "zoom.us")
    private let keys = KeyCombo(text: "ctrl+opt+N")!

    private func step(_ kind: TriggerAction.Kind) -> EntryDraft.Step { EntryDraft.Step(kind) }

    func testANewDraftAsksForATriggerThenAStep() {
        var draft = EntryDraft()
        XCTAssertNil(draft.when)
        XCTAssertEqual(draft.missing, "Choose a trigger to start")
        draft.add(.keys)
        XCTAssertEqual(draft.missing, "Record the keys to save")
        draft.keys = [keys]
        XCTAssertEqual(draft.missing, "Add a step to save")
        var open = step(.openApp)
        draft.steps = [open]
        XCTAssertEqual(draft.missing, "Choose the app to open")
        open.app = notes
        draft.steps = [open]
        XCTAssertNil(draft.missing)
        XCTAssertEqual(draft.name, "Open Notes")
        guard case let .trigger(trigger)? = draft.result else { return XCTFail("a trigger") }
        XCTAssertEqual(trigger.starts, [.keys])
        XCTAssertEqual(trigger.keys, [keys])
        XCTAssertEqual(trigger.steps, [.openApp(notes)])
    }

    func testEachStepSaysWhatItStillNeeds() {
        var draft = EntryDraft()
        draft.add(.keys)
        draft.keys = [keys]
        let expected: [(TriggerAction.Kind, String)] = [
            (.sendKeys, "Record the keys to press"), (.openApp, "Choose the app to open"),
            (.open, "Enter a link or file"), (.runShortcut, "Choose a Shortcut"), (.typeText, "Type the text to type"),
        ]
        for (kind, missing) in expected {
            draft.steps = [step(.wait), step(kind)]
            XCTAssertEqual(draft.missing, "Step 2: " + missing.prefix(1).lowercased() + missing.dropFirst(), "\(kind)")
        }
        draft.steps = [step(.wait)]
        XCTAssertNil(draft.missing, "a wait starts at a second")
    }

    func testSeveralStepsKeepTheirOrderAndNameThemselves() {
        var draft = EntryDraft()
        draft.add(.keys)
        draft.keys = [keys]
        var first = step(.openApp); first.app = notes
        var second = step(.openApp); second.app = mail
        draft.steps = [first, second]
        XCTAssertEqual(draft.name, "Open Notes and Mail")
        var text = step(.typeText); text.text = "Morning"
        draft.steps = [first, step(.wait), text]
        XCTAssertEqual(draft.trigger?.steps, [.openApp(notes), .wait(1), .typeText("Morning")])
        XCTAssertEqual(draft.name, "Open Notes, then 2 more")
    }

    func testEachTriggerMakesItsStart() {
        var press = step(.sendKeys); press.keys = KeyCombo(text: "cmd+[")
        func only(_ when: EntryDraft.When) -> EntryDraft {
            var draft = EntryDraft()
            draft.steps = [press]
            draft.add(when)
            return draft
        }
        XCTAssertEqual(only(.mouseButton).trigger?.starts, [.mouseButton(4)], "the back button to begin with")
        var opens = only(.appOpens)
        XCTAssertEqual(opens.missing, "Choose the app")
        opens.openingApps = [zoom]
        XCTAssertEqual(opens.trigger?.starts, [.appOpens(zoom)])
        var typed = only(.typed)
        XCTAssertEqual(typed.missing, "Type at least two letters, no spaces")
        typed.letters = ";back"
        XCTAssertEqual(typed.trigger?.starts, [.typed(";back")])
        XCTAssertEqual(only(.time).trigger?.starts, [.time(9 * 60)])
        XCTAssertEqual(only(.time).trigger?.keys, [], "only keys keep keys")
    }

    func testSeveralTriggersStartOneAction() {
        var draft = EntryDraft(whens: [.keys, .mouseButton], steps: [.openApp])
        draft.keys = [KeyCombo(text: "hyper+W")!]
        draft.mouseButtons = [4, 5]
        draft.steps[0].app = notes
        draft.add(.typed)
        draft.letters = ";w, ;work"
        draft.add(.time)
        XCTAssertNil(draft.missing)
        XCTAssertEqual(draft.trigger?.starts, [.keys, .mouseButton(4), .mouseButton(5), .typed(";w"), .typed(";work"), .time(540)])
        draft.remove(.mouseButton)
        XCTAssertEqual(draft.whens, [.keys, .typed, .time])
    }

    func testAnAppInFrontStandsAlone() {
        var draft = EntryDraft(whens: [.keys, .time])
        draft.add(.appInFront)
        XCTAssertEqual(draft.whens, [.appInFront])
        draft.add(.mouseButton)
        XCTAssertEqual(draft.whens, [.mouseButton])
    }

    func testTheSentenceReadsTheActionBack() {
        var draft = EntryDraft()
        XCTAssertNil(draft.sentence)
        draft.add(.keys)
        XCTAssertEqual(draft.sentence, "When I press keys, …")
        draft.keys = [KeyCombo(text: "hyper+W")!]
        draft.add(.mouseButton)
        var first = step(.openApp); first.app = notes
        var second = step(.openApp); second.app = mail
        draft.steps = [first, step(.wait), second]
        XCTAssertEqual(draft.sentence, "When I press Hyper W or I click button 4, open Notes, wait 1 s, then open Mail.")
    }

    func testSendingKeysToTheAppNeedsKeysAndIsTheOnlyStep() {
        var draft = EntryDraft()
        draft.add(.keys)
        draft.keys = [KeyCombo(text: "cmd+space")!, KeyCombo(text: "cmd+tab")!]
        draft.steps = [step(.passThrough)]
        XCTAssertEqual(draft.name, "Pass ⌘Space and ⌘⇥ to the app")
        XCTAssertEqual(draft.trigger?.steps, [.passThrough])
        draft.steps.append(step(.wait))
        XCTAssertEqual(draft.missing, "Sending keys to the app is a step on its own")
        draft.steps = [step(.passThrough)]
        draft.add(.time)
        XCTAssertEqual(draft.missing, "Only keys can be sent to the app")
    }

    func testAnAppInFrontIsAPassthroughApp() {
        var draft = EntryDraft()
        draft.add(.appInFront)
        XCTAssertEqual(draft.missing, "Add an app to save")
        draft.apps = [windows]
        draft.captureAllKeys = true
        XCTAssertNil(draft.missing, "it needs no steps: it sends the app its keys")
        guard case let .profile(profile)? = draft.result else { return XCTFail("a passthrough app") }
        XCTAssertEqual(profile.name, "Windows App")
        XCTAssertEqual(profile.apps, [windows])
        XCTAssertTrue(profile.captureAllKeys)
        XCTAssertEqual(profile.systemShortcuts, SystemShortcutGroup.defaultSet)
    }

    func testYourOwnNameStays() {
        var draft = EntryDraft()
        draft.add(.keys)
        draft.customName = "Mine"
        draft.steps = [step(.runShortcut)]
        XCTAssertEqual(draft.name, "Mine")
        draft.customName = ""
        XCTAssertEqual(draft.name, "Run a Shortcut")
    }

    func testAppsOnlyLimitATriggerWhenAskedTo() {
        var draft = EntryDraft()
        draft.add(.keys)
        draft.keys = [keys]
        draft.steps = [step(.wait)]
        draft.apps = [windows]
        XCTAssertEqual(draft.trigger?.apps, [])
        draft.onlyInApps = true
        XCTAssertEqual(draft.trigger?.apps, [windows])
    }

    func testEditingATriggerKeepsEverythingAndItsID() {
        let trigger = Trigger(name: "Docs", isEnabled: false, keys: [], steps: [.open("~/Docs"), .wait(2)], apps: [notes],
                              starts: [.typed(";docs")])
        let draft = EntryDraft(trigger: trigger)
        XCTAssertEqual(draft.origin, .trigger(trigger.id))
        XCTAssertEqual(draft.when, .typed)
        XCTAssertEqual(draft.letters, ";docs")
        XCTAssertEqual(draft.steps.map(\.kind), [.open, .wait])
        XCTAssertEqual(draft.name, "Docs")
        XCTAssertTrue(draft.onlyInApps)
        XCTAssertEqual(draft.trigger, trigger)

        let named = EntryDraft(trigger: Trigger(name: "Open Notes", keys: [keys], action: .openApp(notes)))
        XCTAssertEqual(named.customName, "", "a name that was only the suggestion keeps following it")
    }

    func testEditingAPassthroughAppOpensOnAnAppInFront() {
        let profile = PassthroughProfile(name: "Work PC", apps: [windows], systemShortcuts: [.spotlight], modifierLayout: .swapCommandControl)
        let draft = EntryDraft(profile: profile)
        XCTAssertEqual(draft.when, .appInFront)
        XCTAssertEqual(draft.profile, profile)
    }

    func testSwitchingAPassthroughAppToATriggerKeepsItsAppsAndConditions() {
        var draft = EntryDraft(profile: PassthroughProfile(name: "Windows App", apps: [windows],
                                                           conditions: ConditionSet(conditions: [Condition(.fullScreen)])))
        draft.customName = ""
        draft.add(.keys)
        draft.keys = [keys]
        draft.steps = [step(.passThrough)]
        draft.onlyInApps = true
        let trigger = draft.trigger
        XCTAssertEqual(trigger?.apps, [windows])
        XCTAssertEqual(trigger?.conditions.conditions.map(\.kind), [.fullScreen])
        XCTAssertEqual(trigger?.name, "Pass ⌃⌥N to the app")
    }
}
