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

    private func trigger(_ name: String, pack: String? = nil, apps: [AppRef] = []) -> Trigger {
        var trigger = Trigger(name: name, keys: [keys("hyper+\(name.prefix(1))")], action: .openApp(notes), apps: apps)
        trigger.pack = pack
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
        XCTAssertEqual(config.triggers.map(\.pack), ["Excel", nil])
        XCTAssertEqual(config.profiles.first?.pack, "Remote")

        let again = try roundTrip(config)
        XCTAssertEqual(again.packs, config.packs)
        XCTAssertEqual(again.triggers.map(\.pack), ["Excel", nil])
        XCTAssertEqual(again.profiles.first?.pack, "Remote")
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

    func testAPassthroughAppInAPackThatsOffIsOff() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Remote", isEnabled: false)]
        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        profile.pack = "Remote"
        config.profiles = [profile]
        XCTAssertEqual(config.runningProfiles.map(\.isEnabled), [false])
    }

    // MARK: - The editor

    func testTheDraftKeepsItsPack() throws {
        let fit = trigger("Fit", pack: "Excel")
        var draft = EntryDraft(trigger: fit)
        XCTAssertEqual(draft.pack, "Excel")
        XCTAssertEqual(draft.trigger?.pack, "Excel")
        draft.pack = nil
        XCTAssertNil(draft.trigger?.pack)

        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        profile.pack = "Remote"
        XCTAssertEqual(EntryDraft(profile: profile).profile?.pack, "Remote")
    }

    // MARK: - Moving in and out

    func testAnActionMovesIntoAPackAndOut() {
        var config = MacsBoredConfig()
        config.packs = [ActionPack(name: "Excel")]
        let fit = trigger("Fit")
        var profile = PassthroughProfile(name: "Windows App", apps: [AppRef(bundleID: "com.microsoft.rdc.macos", name: "Windows App")])
        profile.pack = nil
        config.triggers = [fit]
        config.profiles = [profile]

        config.move(.trigger(fit.id), toPack: "Excel")
        config.move(.profile(profile.id), toPack: "Excel")
        XCTAssertEqual(config.triggers[0].pack, "Excel")
        XCTAssertEqual(config.profiles[0].pack, "Excel")

        config.move(.trigger(fit.id), toPack: nil)
        XCTAssertNil(config.triggers[0].pack)

        config.move(.trigger(fit.id), toPack: "Nowhere")   // no such pack: nothing moves
        XCTAssertNil(config.triggers[0].pack)
    }
}
