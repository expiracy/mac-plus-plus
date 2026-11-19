import XCTest
@testable import MacsBoredCore

/// Packs: actions grouped under a name, switched on and off together, and limited to apps together.
final class ActionPackTests: XCTestCase {
    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }
    private func keys(_ text: String) -> KeyCombo { KeyCombo(text: text)! }
    private let excel = AppRef(bundleID: "com.microsoft.Excel", name: "Microsoft Excel")
    private let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")

    private func roundTrip(_ config: MacsBoredConfig) throws -> MacsBoredConfig {
        let written = ConfigFile.written(config)
        return try XCTUnwrap(read(written).config, written)
    }

    private func trigger(_ name: String, pack: String? = nil, packs: [String] = [], apps: [AppRef] = []) -> Trigger {
        var trigger = Trigger(name: name, keys: [keys("hyper+\(name.prefix(1))")], action: .openApp(notes), apps: apps)
        trigger.packs = pack.map { [$0] } ?? packs
        return trigger
    }

    // MARK: - The file

    func testPacksAndTheActionsInThemReadAndWrite() throws {
        let config = try XCTUnwrap(read("""
        { "packs": [{ "name": "Excel", "apps": ["com.microsoft.Excel"] }, { "name": "Remote", "enabled": false }],
          "passthrough": [{ "name": "Windows App", "apps": ["com.microsoft.rdc.macos"], "pack": "Remote" }],
          "triggers": [{ "name": "Fit", "keys": "hyper+F", "pack": "Excel", "action": { "openApp": "com.apple.Notes" } },
                       { "name": "Loose", "keys": "hyper+L", "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        XCTAssertEqual(config.packs.map(\.name), ["Excel", "Remote"])
        XCTAssertEqual(config.packs[0].apps.map(\.bundleID), ["com.microsoft.Excel"])
        XCTAssertEqual(config.packs.map(\.isEnabled), [true, false])
        XCTAssertEqual(config.triggers.map(\.packs), [["Excel"], []])
        XCTAssertEqual(config.profiles.first?.packs, ["Remote"])

        let again = try roundTrip(config)
        XCTAssertEqual(again.packs, config.packs)
        XCTAssertEqual(again.triggers.map(\.packs), [["Excel"], []])
        XCTAssertEqual(again.profiles.first?.packs, ["Remote"])
        XCTAssertTrue(again.extra.members.isEmpty && again.triggers.allSatisfy { $0.extra.members.isEmpty })
    }

    func testAPackNamedOnlyOnAnActionStillExists() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Fit", "keys": "hyper+F", "pack": "Excel", "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        XCTAssertEqual(config.packs, [ActionPack(name: "Excel")])
        XCTAssertTrue(config.packs[0].isEnabled)
        XCTAssertTrue(config.packs[0].apps.isEmpty)
    }

    func testAnActionCanBeInSeveralPacks() throws {
        let config = try XCTUnwrap(read("""
        { "packs": [{ "name": "Excel" }],
          "triggers": [{ "name": "Fit", "keys": "hyper+F", "pack": ["Excel", "Remote", "excel"], "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        XCTAssertEqual(config.triggers[0].packs, ["Excel", "Remote"], "a name twice, in any case, is one")
        XCTAssertEqual(config.packs.map(\.name), ["Excel", "Remote"])

        let written = ConfigFile.written(config)
        XCTAssertTrue(written.contains(#""pack" : ["#) || written.contains(#""pack": ["#), written)
        XCTAssertEqual(try roundTrip(config).triggers[0].packs, ["Excel", "Remote"])
    }

    func testAPackIsANameOrAListOfNames() {
        let reading = read(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "pack": ["Excel", 3], "action": { "openApp": "com.apple.Notes" } }] }"#)
        XCTAssertFalse(reading.issues.filter { !$0.isWarning }.isEmpty)
    }

    func testAnEmptyPackIsKept() throws {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Later")]
        XCTAssertEqual(try roundTrip(config).packs, [ActionPack(name: "Later")])
    }

    func testTwoPacksWithOneNameIsAMistake() {
        let reading = read(#"{ "packs": [{ "name": "Excel" }, { "name": "excel" }], "triggers": [] }"#)
        XCTAssertFalse(reading.issues.filter { !$0.isWarning }.isEmpty)
    }

    // MARK: - As they run

    func testAnActionInAPackThatsOffDoesntRun() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Excel", isEnabled: false)]
        config.triggers = [trigger("Fit", pack: "Excel"), trigger("Loose")]
        XCTAssertEqual(config.runningTriggers.map(\.isEnabled), [false, true])
    }

    func testAPacksAppsLimitItsActionsUnlessTheyNameTheirOwn() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Excel", apps: [excel])]
        config.triggers = [trigger("Fit", pack: "Excel"), trigger("Own", pack: "Excel", apps: [notes]), trigger("Loose")]
        XCTAssertEqual(config.runningTriggers.map { $0.apps.map(\.bundleID) },
                       [["com.microsoft.Excel"], ["com.apple.Notes"], []])
    }

    func testAnActionInSeveralPacksRunsWhileAnyIsOnInTheirApps() {
        var config = MacsBoredConfig()
        let remote = AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")
        config.packs = [ActionPack(name: "Excel", apps: [excel]), ActionPack(name: "Remote", apps: [remote]),
                        ActionPack(name: "Anywhere")]
        config.triggers = [trigger("Both", packs: ["Excel", "Remote"]), trigger("Wide", packs: ["Excel", "Anywhere"])]
        XCTAssertEqual(config.runningTriggers.map(\.isEnabled), [true, true])
        XCTAssertEqual(config.runningTriggers.map { $0.apps.map(\.bundleID) },
                       [["com.microsoft.Excel", "com.microsoft.rdc.macos"], []])

        config.packs[1].isEnabled = false   // Remote off: Both works on in Excel
        XCTAssertEqual(config.runningTriggers[0].isEnabled, true)
        XCTAssertEqual(config.runningTriggers[0].apps.map(\.bundleID), ["com.microsoft.Excel"])

        config.packs[0].isEnabled = false   // both off: off
        XCTAssertEqual(config.runningTriggers[0].isEnabled, false)
    }

    func testAPassthroughAppInAPackThatsOffIsOff() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Remote", isEnabled: false)]
        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        profile.packs = ["Remote"]
        config.profiles = [profile]
        XCTAssertEqual(config.runningProfiles.map(\.isEnabled), [false])
        config.packs.append(ActionPack(name: "Work"))
        config.profiles[0].packs.append("Work")
        XCTAssertEqual(config.runningProfiles.map(\.isEnabled), [true], "one of its packs is on")
    }

    // MARK: - The editor

    func testTheDraftKeepsItsPack() throws {
        let fit = trigger("Fit", pack: "Excel")
        var draft = EntryDraft(trigger: fit)
        XCTAssertEqual(draft.packs, ["Excel"])
        XCTAssertEqual(draft.trigger?.packs, ["Excel"])
        draft.packs.append("Remote")
        XCTAssertEqual(draft.trigger?.packs, ["Excel", "Remote"])
        draft.packs = []
        XCTAssertEqual(draft.trigger?.packs, [])

        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        profile.packs = ["Remote"]
        XCTAssertEqual(EntryDraft(profile: profile).profile?.packs, ["Remote"])
    }

    // MARK: - Moving in and out

    func testAnActionMovesIntoAPackAndOut() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Excel")]
        let fit = trigger("Fit")
        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        config.packs.append(ActionPack(name: "Remote"))
        config.triggers = [fit]
        config.profiles = [profile]

        config.move(.trigger(fit.id), from: nil, to: "Excel")
        config.move(.profile(profile.id), from: nil, to: "Excel")
        XCTAssertEqual(config.triggers[0].packs, ["Excel"])
        XCTAssertEqual(config.profiles[0].packs, ["Excel"])

        config.move(.trigger(fit.id), from: nil, to: "Remote")   // from the loose list: added
        XCTAssertEqual(config.triggers[0].packs, ["Excel", "Remote"])
        config.move(.trigger(fit.id), from: "Remote", to: "Excel")   // already there: just leaves Remote
        XCTAssertEqual(config.triggers[0].packs, ["Excel"])

        config.move(.trigger(fit.id), from: "Excel", to: nil)
        XCTAssertEqual(config.triggers[0].packs, [])

        config.move(.trigger(fit.id), from: nil, to: "Nowhere")   // no such pack: nothing moves
        XCTAssertEqual(config.triggers[0].packs, [])
    }
}
