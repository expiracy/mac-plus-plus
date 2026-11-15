#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// MacsBored's page of mac++'s dropdown, drawn by the same view as MacsPane's. MacsBored does two
/// things: beside its name, the switch for all of it; under its name, what each is doing; then its
/// a section for each thing it makes (passthrough, key remaps, quick opens, Shortcuts to run), each
/// row with a pencil, a bin and its switch, and a + on each title to make a new one. Accessibility and Open at login
/// belong to the whole app (the dropdown's banner and Settings).
@MainActor
enum MacsBoredMenu {
    static let brand = MenuPageBrand(name: "MacsBored", logo: { AnyView(MacsBoredLogo(size: $0)) })

    static func content(_ model: MacsBoredModel) -> MenuPageContent {
        var content = MenuPageContent()
        // The main switch, beside the name: all of MacsBored.
        content.primary = .toggle("MacsBored", symbol: "command", isOn: model.config.isEnabled, primary: true) {
            [weak model] in
            guard let model else { return }
            model.setEnabled(!model.config.isEnabled)
        }
        content.liveFact = statusLine(model)
        content.warnings = warnings(model)
        content.groups = groups(model)
        return content
    }

    /// Both halves at a glance: what passthrough is doing, then how many triggers are on.
    private static func statusLine(_ model: MacsBoredModel) -> String {
        let app = model.context.appName ?? "the app"
        let passthrough: String
        if !model.config.isEnabled { return "Off · macOS keeps all its keys" }
        if model.plan.isActive { passthrough = "Passing shortcuts to \(app)" }
        else if model.isPaused { passthrough = "Passthrough paused in \(app)" }
        else { passthrough = "Passthrough on" }
        let on = model.config.triggers.filter(\.isEnabled).count
        return passthrough + " · " + (on == 0 ? "no triggers on" : on == 1 ? "1 trigger on" : "\(on) triggers on")
    }

    // MARK: - Warnings

    private static func warnings(_ model: MacsBoredModel) -> [MenuEntry] {
        var warnings: [MenuEntry] = []
        if let issue = model.fileErrors.first {
            let line = issue.line.map { "config.json line \($0) isn't valid" } ?? "config.json isn't valid"
            var row = MenuEntry.warning(line, actionTitle: "Show") { [weak model] in model?.openConfigFile() }
            row.trailing = issue.message
            warnings.append(row)
        }
        // Accessibility itself is the dropdown's banner, for the whole app.
        if model.isAuthorized && !model.tapRunning {
            warnings.append(.warning("Keyboard tap isn't running", actionTitle: "Relaunch") { Relaunch.now() })
        }
        if !model.hotKeySwitchAvailable {
            warnings.append(.warning("macOS's own shortcuts can't be switched here"))
        }
        if model.config.hyperKeyEnabled && model.hyperBlocked {
            warnings.append(.warning("Hyper is off: another tool remaps keys"))
        }
        return warnings
    }

    // MARK: - Lists

    /// A section for each thing MacsBored makes, each with its own +: passthrough (whole apps,
    /// and triggers that pass only some keys), key remaps, quick opens, and Shortcuts to run.
    private static func groups(_ model: MacsBoredModel) -> [MenuGroup] {
        let triggers = model.config.triggers
        func rows(_ kinds: Set<TriggerAction.Kind>) -> [MenuEntry] {
            triggers.filter { kinds.contains($0.action.kind) }.map { triggerRow($0, model) }
        }
        return [
            group("Passthrough", rows: model.config.profiles.map { profileRow($0, model) } + rows([.passThrough]),
                  new: "New passthrough app", tab: .passthrough, model),
            group("Key remaps", rows: rows([.sendKeys]), new: "New key remap", tab: .remap, model),
            group("Quick opens", rows: rows([.openApp, .open]), new: "New quick open", tab: .open, model),
            group("Shortcuts to run", rows: rows([.runShortcut]), new: "New Shortcut to run", tab: .shortcut, model),
        ]
    }

    private static func group(_ title: String, rows: [MenuEntry], new: String, tab: EntryDraft.Tab,
                              _ model: MacsBoredModel) -> MenuGroup {
        // Opens the editor page in the dropdown.
        let add = MenuEntry.command(new, symbol: "plus", key: "new-\(tab.rawValue)", keepsOpen: true) { [weak model] in
            model?.newEntry(tab)
        }
        return MenuGroup(title: title, rows: rows, add: add, empty: "None yet.")
    }

    private static func profileRow(_ profile: PassthroughProfile, _ model: MacsBoredModel) -> MenuEntry {
        var row = MenuEntry.toggle(profile.name, symbol: "macwindow", isOn: profile.isEnabled,
                                   key: "profile-\(profile.id)",
                                   secondary: ("pencil", "Edit", { [weak model] in model?.editProfile(profile.id) }),
                                   trash: ("Delete \(profile.name)", { [weak model] in model?.deleteProfile(profile.id) })) {
            [weak model] in model?.toggleProfile(profile.id)
        }
        if let icon = profile.apps.first.flatMap({ AppIcons.icon(bundleID: $0.bundleID) }) { row.leading = .appIcon(icon) }
        row.keepsOpen = true   // the pencil opens the editor page
        return row
    }

    private static func triggerRow(_ trigger: Trigger, _ model: MacsBoredModel) -> MenuEntry {
        var row = MenuEntry.toggle(trigger.name, symbol: trigger.action.kind.symbol, isOn: trigger.isEnabled,
                                   key: "trigger-\(trigger.id)",
                                   secondary: ("pencil", "Edit", { [weak model] in model?.editTrigger(trigger.id) }),
                                   trash: ("Delete \(trigger.name)", { [weak model] in model?.deleteTrigger(trigger.id) })) {
            [weak model] in model?.toggleTrigger(trigger.id)
        }
        // A quick open shows the app it opens.
        if case let .openApp(app) = trigger.action, let icon = AppIcons.icon(bundleID: app.bundleID) {
            row.leading = .appIcon(icon)
        }
        row.trailing = trigger.keys.isEmpty ? "No keys"
            : trigger.keys.count == 1 ? trigger.keys[0].displayName
            : "\(trigger.keys[0].displayName) +\(trigger.keys.count - 1)"
        row.keepsOpen = true   // the pencil opens the editor page
        return row
    }
}

/// Starts a fresh copy of the app and quits this one, for when macOS won't start the keyboard tap.
enum Relaunch {
    static func now() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Picks an app from /Applications.
@MainActor
enum AppChooser {
    static func choose(_ picked: @escaping (AppRef) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        picked(AppRef(bundleID: id, name: name))
    }
}
#endif
