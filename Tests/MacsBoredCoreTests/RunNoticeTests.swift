import XCTest
@testable import MacsBoredCore

/// An action can say when it runs: a notification with its name and what it did.
final class RunNoticeTests: XCTestCase {
    private func read(_ text: String) -> ConfigFile.Reading { ConfigFile.read(Data(text.utf8)) }
    private func keys(_ text: String) -> KeyCombo { KeyCombo(text: text)! }
    private let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")

    func testNotifyReadsAndWrites() throws {
        let config = try XCTUnwrap(read("""
        { "triggers": [{ "name": "Loud", "keys": "hyper+L", "notify": true, "action": { "openApp": "com.apple.Notes" } },
                       { "name": "Quiet", "keys": "hyper+Q", "action": { "openApp": "com.apple.Notes" } }] }
        """).config)
        XCTAssertEqual(config.triggers.map(\.notifies), [true, false])

        let written = ConfigFile.written(config)
        let again = try XCTUnwrap(read(written).config)
        XCTAssertEqual(again.triggers.map(\.notifies), [true, false])
        XCTAssertTrue(again.triggers.allSatisfy { $0.extra.members.isEmpty })
        XCTAssertEqual(written.components(separatedBy: "\"notify\"").count - 1, 1, "only the one that notifies says so")
    }

    func testNotifyIsTrueOrFalse() {
        let issues = read(#"{ "triggers": [{ "name": "X", "keys": "hyper+X", "notify": "yes", "action": { "openApp": "com.apple.Notes" } }] }"#)
            .issues.filter { !$0.isWarning }
        XCTAssertFalse(issues.isEmpty)
    }

    func testTheNoticeNamesTheActionAndWhatItDid() {
        var trigger = Trigger(name: "Start work", keys: [keys("hyper+W")],
                              steps: [.openApp(notes), .wait(0.5), .sendKeys(keys("cmd+left"))])
        trigger.notifies = true
        XCTAssertEqual(trigger.notice.title, "Start work")
        XCTAssertEqual(trigger.notice.body, "Opens Notes · Waits 0.5 s · Sends ⌘←")
    }

    func testTheDraftKeepsNotify() throws {
        var draft = EntryDraft(whens: [.keys], steps: [.openApp])
        draft.keys = [keys("hyper+N")]
        draft.steps[0].app = notes
        XCTAssertEqual(draft.trigger?.notifies, false)
        draft.notifies = true
        let trigger = try XCTUnwrap(draft.trigger)
        XCTAssertTrue(trigger.notifies)
        XCTAssertTrue(EntryDraft(trigger: trigger).notifies)
    }
}
