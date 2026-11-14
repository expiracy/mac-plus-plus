import Testing
import Foundation
@testable import MacsPaneCore

// MacsPane's config.json as a person, a script or an AI agent edits it: keys as text, a schema beside
// it, a check that names the line, and the running app picking an edit up.

private func read(_ json: String) -> MacsPaneConfigFile.Reading { MacsPaneConfigFile.read(Data(json.utf8)) }

@Test func keysAreWrittenAndReadAsText() throws {
    let shortcut = AssignedShortcut(shortcut: KeyShortcut(keyCode: 123, modifiers: [.control, .option]),
                                    action: .layoutBox(layoutID: "halves", box: 0))
    let json = String(decoding: try JSONEncoder().encode(shortcut), as: UTF8.self)
    #expect(json.contains(#""keys":"ctrl+opt+left""#))
    #expect(!json.contains("keyCode"))
    #expect(KeyShortcut(text: "ctrl+opt+left") == KeyShortcut(keyCode: 123, modifiers: [.control, .option]))
    #expect(KeyShortcut(text: "⌃⌥C")?.keyName == "C")
    #expect(KeyShortcut(text: "ctrl+banana") == nil)
}

@Test func aFileFromBeforeTextKeysStillReads() throws {
    let json = #"{ "shortcuts": [ { "shortcut": { "keyCode": 124, "modifiers": 3 }, "action": { "kind": "layoutBox", "layoutID": "halves", "box": 1 } } ] }"#
    let config = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    #expect(config.shortcuts.first?.shortcut == KeyShortcut(keyCode: 124, modifiers: [.control, .option]))
}

@Test func theFileLinksItsSchemaAndLeavesOutTheUnusedRegionList() throws {
    let text = MacsPaneConfigFile.write(.default)
    #expect(text.hasPrefix("{\n  \"$schema\": \"./config.schema.json\""))
    #expect(!text.contains("\"regions\""))
    #expect(read(text).config == .default)
    #expect(read(text).issues.isEmpty)
}

@Test func aHandWrittenFileWithReadableIDsWorks() {
    let reading = read("""
    {
      "presets": [
        { "id": "work", "name": "Work",
          "slots": [ { "region": "leftHalf", "binding": { "kind": "app", "bundleID": "com.apple.Safari" } } ] }
      ],
      "shortcuts": [ { "keys": "ctrl+opt+W", "action": { "kind": "preset", "id": "work" } } ]
    }
    """)
    #expect(reading.issues.isEmpty)
    #expect(reading.config?.activeShortcuts.count == 1)
    #expect(reading.config?.presets.first?.slots.first?.region == .preset(.leftHalf))
}

@Test func aSyntaxMistakeIsAnErrorOnItsLine() {
    let reading = read("{\n  \"dwellMs\": 300,\n  \"setupCompleted\": tru\n}")
    #expect(reading.config == nil)
    #expect(reading.errors.first?.line == 3)
}

@Test func aMisspelledFieldIsNamedWithItsLine() {
    let reading = read("{\n  \"dwelMs\": 300\n}")
    #expect(reading.config != nil)
    #expect(reading.issues.count == 1)
    #expect(reading.issues.first?.line == 2)
    #expect(reading.issues.first?.message.contains("dwelMs") == true)
}

@Test func whatWouldBeLeftOutIsAnError() {
    let reading = read("""
    {
      "shortcuts": [
        { "keys": "ctrl+banana", "action": { "kind": "preset", "id": "work" } },
        { "keys": "ctrl+opt+P", "action": { "kind": "preset", "id": "nowhere" } },
        { "keys": "P", "action": { "kind": "layoutBox", "layoutID": "halves", "box": 0 } },
        { "keys": "ctrl+opt+left", "action": { "kind": "layoutBox", "layoutID": "halves", "box": 5 } }
      ],
      "windows": { "dragBarLayoutIDs": ["halves", "sideways"] }
    }
    """)
    #expect(reading.config != nil)                 // the rest still applies
    #expect(reading.errors.map(\.line) == [3, 4, 5, 6, 8])
}

@Test func checkExitsOneOnAnErrorAndNamesThePath() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("macspane-check-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{ \"dwellMs\": }".utf8).write(to: url)
    let bad = try #require(MacsPaneConfigCommand.run(["check"], defaultURL: url))
    #expect(bad.status == 1)
    #expect(bad.output.hasPrefix(url.path + ":1: error:"))
    try Data(MacsPaneConfigFile.write(.default).utf8).write(to: url)
    #expect(MacsPaneConfigCommand.run(["check"], defaultURL: url)?.status == 0)
    #expect(MacsPaneConfigCommand.run(["path"], defaultURL: url)?.output == url.path)
    #expect(MacsPaneConfigCommand.run(["schema"], defaultURL: url)?.output == MacsPaneSchema.text)
    #expect(MacsPaneConfigCommand.run(["nonsense"], defaultURL: url) == nil)
}

@Test func theSchemaIsJSONAndNamesEveryFieldTheFileHas() throws {
    let schema = try #require(try JSONSerialization.jsonObject(with: Data(MacsPaneSchema.text.utf8)) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let written = try #require(try JSONSerialization.jsonObject(with: Data(MacsPaneConfigFile.write(.default).utf8)) as? [String: Any])
    #expect(Set(written.keys).isSubset(of: Set(properties.keys)))
}

@Test func theStorePicksUpAnEditAndNeverOverwritesABrokenFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macspane-store-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("config.json")
    let store = MacsPaneConfigStore(url: url)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.schema.json").path))

    try Data(#"{ "dwellMs": 600 }"#.utf8).write(to: url)
    #expect(store.reload())
    #expect(store.config.dwellMs == 600)

    let broken = Data(#"{ "dwellMs": 1500, }"#.utf8)
    try broken.write(to: url)
    store.reload()
    #expect(store.config.dwellMs == 600)           // the last good settings keep running
    #expect(!store.errors.isEmpty)
    store.update { $0.setupCompleted = true }
    #expect(try Data(contentsOf: url) == broken)   // the edit in progress is left alone
}
