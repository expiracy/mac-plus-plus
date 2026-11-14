import Foundation
import MacsSettings

/// MacsPane's `config.json` as text: written with its schema linked and short lists on one line, and
/// read with every problem named by its line, so a person, a script or an AI agent can edit it and
/// check the edit.
///
/// Reading never throws a setting away to make a point: a file that isn't JSON is an error and is not
/// applied, but anything else is applied less the parts it names. An **error** is a part left out (keys
/// that name nothing, a shortcut whose preset doesn't exist); a **warning** is a field MacsPane doesn't
/// know, most often a misspelling, which is ignored.
public enum MacsPaneConfigFile {
    public static let schemaName = "config.schema.json"

    public struct Issue: Equatable, Sendable {
        public var line: Int?
        public var message: String
        public var isWarning: Bool

        public init(line: Int?, message: String, isWarning: Bool = false) {
            self.line = line
            self.message = message
            self.isWarning = isWarning
        }
    }

    public struct Reading: Sendable {
        /// Nil when the file isn't JSON (or isn't an object): nothing in it can be applied.
        public var config: MacsPaneConfig?
        public var issues: [Issue]
        public var errors: [Issue] { issues.filter { !$0.isWarning } }
    }

    public static func read(_ data: Data) -> Reading {
        let root: JSONNode
        do {
            root = try JSONNode.parse(data)
        } catch let error as JSONParseError {
            return Reading(config: nil, issues: [Issue(line: error.line, message: error.message)])
        } catch {
            return Reading(config: nil, issues: [Issue(line: nil, message: "This isn't JSON.")])
        }
        guard root.object != nil,
              let config = try? JSONDecoder().decode(MacsPaneConfig.self, from: data) else {
            return Reading(config: nil, issues: [Issue(line: root.line, message: "The file should be one object in {braces}.")])
        }
        var check = Checker(config: config)
        check.top(root)
        return Reading(config: config.migrated(), issues: check.issues)
    }

    /// The file as MacsPane writes it: `$schema` first, then the settings, keys sorted.
    public static func write(_ config: MacsPaneConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(config), let node = try? JSONNode.parse(data),
              case let .object(members) = node.value else { return "{}\n" }
        return JSONValue.object([("$schema", .string("./\(schemaName)"))] + members).written()
    }
}

// MARK: - Checking

private struct Checker {
    let config: MacsPaneConfig
    var issues: [MacsPaneConfigFile.Issue] = []

    private var layoutIDs: Set<String> { Set(config.windows.layoutCatalog.map(\.id)) }

    mutating func top(_ root: JSONNode) {
        for member in root.object ?? [] {
            let node = member.node
            switch member.key {
            case "$schema", "schemaVersion", "dwellMs", "setupCompleted": break
            case "snap":
                known(node, ["enabled", "regions", "showFullScreenPreview", "dragActivationDistance",
                             "titleBarBandHeight", "zoneSet"], in: "snap")
            case "windows": windows(node)
            case "presets": list(node, "presets") { this, item, _ in this.preset(item) }
            case "shortcuts": list(node, "shortcuts") { this, item, _ in this.shortcut(item) }
            default: unknown(member.key, node, in: nil)
            }
        }
    }

    private mutating func windows(_ node: JSONNode) {
        known(node, ["enabled", "layouts", "dragBarLayoutIDs", "drawGrid", "deletedBuiltIns", "layoutOrder"], in: "windows")
        if let layouts = node["layouts"] {
            list(layouts, "windows.layouts") { this, item, _ in
                this.known(item, ["id", "name", "boxes", "boxLayers"], in: "a layout")
                guard let boxes = item["boxes"]?.array, !boxes.isEmpty else {
                    this.error(item, "A layout needs at least one box in “boxes”; this one is left out.")
                    return
                }
                for box in boxes { this.region(box) }
            }
        }
        for id in node["dragBarLayoutIDs"]?.array ?? [] {
            guard let text = id.string else { error(id, "Layout ids are text in quotes."); continue }
            if !layoutIDs.contains(text) {
                error(id, "“\(text)” isn't a layout, so the notch leaves it out. Layouts: \(layoutIDs.sorted().joined(separator: ", ")).")
            }
        }
    }

    private mutating func preset(_ item: JSONNode) {
        known(item, ["id", "name", "slots", "cols", "rows", "profileID", "layoutID"], in: "a preset")
        guard let slots = item["slots"] else { return }
        list(slots, "slots") { this, slot, _ in
            this.known(slot, ["id", "region", "binding", "launchIfClosed", "isRemoved", "layer"], in: "a slot")
            if let region = slot["region"] { this.region(region) }
            if let binding = slot["binding"] {
                this.known(binding, ["kind", "bundleID"], in: "a binding")
                let kind = binding["kind"]?.string
                if let kind, !["app", "mostRecent", "empty"].contains(kind) {
                    this.error(binding, "“\(kind)” isn't a binding kind. Use app, mostRecent or empty.")
                } else if kind == "app", (binding["bundleID"]?.string ?? "").isEmpty {
                    this.error(binding, "An app binding needs its “bundleID”, like \"com.apple.Safari\"; without one the box takes the most recent window.")
                }
            }
        }
    }

    /// A box: a zone's name ("leftHalf"), { "kind": "preset", "zone": … } or { "kind": "custom", "rect": … }.
    private mutating func region(_ node: JSONNode) {
        if let zone = node.string {
            if WindowSnapZone(rawValue: zone) == nil { badZone(zone, node) }
            return
        }
        known(node, ["kind", "zone", "rect"], in: "a region")
        switch node["kind"]?.string {
        case "preset":
            if let zone = node["zone"]?.string, WindowSnapZone(rawValue: zone) == nil { badZone(zone, node) }
        case "custom":
            if let rect = node["rect"] { known(rect, ["x", "y", "width", "height"], in: "a rect") }
            else { error(node, "A custom region needs a “rect”: { \"x\": 0, \"y\": 0, \"width\": 0.5, \"height\": 1 }.") }
        default:
            error(node, "A region is a zone's name, like \"leftHalf\", or { \"kind\": \"custom\", \"rect\": { … } }.")
        }
    }

    private mutating func badZone(_ zone: String, _ node: JSONNode) {
        error(node, "“\(zone)” isn't a zone; the box fills the screen instead. Zones: "
              + WindowSnapZone.allCases.map(\.rawValue).joined(separator: ", ") + ".")
    }

    private mutating func shortcut(_ item: JSONNode) {
        known(item, ["keys", "shortcut", "action", "isEnabled"], in: "a shortcut")
        guard let keysNode = item["keys"] ?? item["shortcut"] else {
            error(item, "A shortcut needs “keys”, like \"ctrl+opt+left\"; this one is left out.")
            return
        }
        let shortcut: KeyShortcut
        if let text = keysNode.string {
            guard let keys = KeyShortcut(text: text) else {
                error(keysNode, "“\(text)” isn't keys MacsPane knows; this shortcut is left out. Write them like ctrl+opt+left or hyper+1.")
                return
            }
            shortcut = keys
        } else if let keys = decode(KeyShortcut.self, keysNode) {
            shortcut = keys
        } else {
            error(keysNode, "Keys are text in quotes, like \"ctrl+opt+left\"; this shortcut is left out.")
            return
        }
        guard let actionNode = item["action"], let action = decode(ShortcutAction.self, actionNode) else {
            error(item["action"] ?? item, "A shortcut's “action” is { \"kind\": \"layoutBox\", \"layoutID\": \"halves\", \"box\": 0 } or { \"kind\": \"preset\", \"id\": \"work\" }; this one is left out.")
            return
        }
        guard shortcut.isUsable else {
            error(keysNode, "“\(shortcut.text)” needs ctrl, opt or cmd (or an F-key), or it would take over typing; it's ignored.")
            return
        }
        switch action {
        case let .preset(id):
            if !config.presets.contains(where: { $0.id == id }) {
                error(actionNode, "There's no preset with the id “\(id)”, so these keys do nothing.")
            }
        case let .layoutBox(layoutID, box):
            guard let layout = config.windows.layoutCatalog.first(where: { $0.id == layoutID }) else {
                error(actionNode, "There's no layout with the id “\(layoutID)”, so these keys do nothing. Layouts: \(layoutIDs.sorted().joined(separator: ", ")).")
                return
            }
            if !layout.boxes.indices.contains(box) {
                error(actionNode, "“\(layoutID)” has \(layout.boxes.count) box\(layout.boxes.count == 1 ? "" : "es"), numbered from 0, so box \(box) does nothing.")
            }
        }
    }

    // MARK: Helpers

    private mutating func list(_ node: JSONNode, _ name: String,
                               _ each: (inout Checker, JSONNode, Int) -> Void) {
        guard let items = node.array else { error(node, "“\(name)” should be a list in [brackets]."); return }
        for (index, item) in items.enumerated() {
            guard item.object != nil else {
                error(item, "Each entry in “\(name)” should be an object in {braces}; this one is left out.")
                continue
            }
            each(&self, item, index)
        }
    }

    private mutating func known(_ node: JSONNode, _ fields: Set<String>, in what: String) {
        for member in node.object ?? [] where !fields.contains(member.key) {
            unknown(member.key, member.node, in: what)
        }
    }

    private mutating func unknown(_ key: String, _ node: JSONNode, in what: String?) {
        issues.append(.init(line: node.line,
                            message: "“\(key)” isn't a field MacsPane knows\(what.map { " in \($0)" } ?? ""); it's ignored. Check the spelling against config.schema.json.",
                            isWarning: true))
    }

    private mutating func error(_ node: JSONNode, _ message: String) {
        issues.append(.init(line: node.line, message: message))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ node: JSONNode) -> T? {
        try? JSONDecoder().decode(type, from: Data(node.value.written().utf8))
    }
}
