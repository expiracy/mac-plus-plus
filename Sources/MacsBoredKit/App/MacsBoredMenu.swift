#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// MacsBored's page of mac++'s dropdown, drawn by the same view as MacsPane's: the main switch beside
/// the name; a "Now" box saying what the app in front gets and the one thing to do about it; any
/// warning with its fix; the general switches; then the passthrough apps and your triggers, each with
/// a pencil, a bin and its switch, and a New row under each list. Accessibility and Open at login
/// belong to the whole app (the dropdown's banner and Settings).
@MainActor
enum MacsBoredMenu {
    static let brand = MenuPageBrand(name: "MacsBored", logo: { AnyView(MacsBoredLogo(size: $0)) })

    static func content(_ model: MacsBoredModel) -> MenuPageContent {
        var content = MenuPageContent()
        let config = model.config
        content.primary = .toggle("Pass shortcuts to remote apps", symbol: "command", isOn: config.passthroughEnabled,
                                  primary: true) { [weak model] in
            guard let model else { return }
            model.setPassthroughEnabled(!model.config.passthroughEnabled)
        }
        content.liveFact = statusLine(model)
        content.live = [now(model)]
        content.warnings = warnings(model)
        content.toggles = toggles(model)
        content.groups = [profileGroup(model), triggerGroup(model)]
        return content
    }

    private static func statusLine(_ model: MacsBoredModel) -> String {
        let app = model.context.appName ?? "the app"
        if !model.config.passthroughEnabled { return "Off · macOS keeps all its shortcuts" }
        if model.plan.isActive { return "Passing \(model.systemShortcutsOff) shortcuts to \(app)" }
        if model.isPaused { return "Paused in \(app)" }
        return "On · waiting for a passthrough app"
    }

    // MARK: - Now

    private static func now(_ model: MacsBoredModel) -> MenuEntry {
        let context = model.context
        let appName = context.appName ?? "This app"
        var entry: MenuEntry
        if model.plan.isActive {
            let count = model.systemShortcutsOff
            entry = .live(appName, symbol: "command", fact: count == 1 ? "1 macOS shortcut goes to it" : "\(count) macOS shortcuts go to it",
                          actionTitle: "Pause", accent: true, key: "now") { [weak model] in model?.togglePause() }
        } else if model.isPaused {
            entry = .live(appName, symbol: "pause.circle", fact: "Paused: macOS has its shortcuts back",
                          actionTitle: "Resume", key: "now") { [weak model] in model?.togglePause() }
        } else if let profile = model.config.profiles.first(where: { $0.isEnabled && $0.covers(bundleID: context.bundleID) }) {
            entry = .live(appName, symbol: "hourglass", fact: model.config.passthroughEnabled ? "Waiting for its conditions" : "Passthrough is switched off",
                          actionTitle: "Edit", key: "now") { [weak model] in model?.editProfile(profile.id) }
        } else if let bundleID = context.bundleID, bundleID != Bundle.main.bundleIdentifier, let name = context.appName {
            entry = .live(name, symbol: "macwindow", fact: "macOS keeps its shortcuts here",
                          actionTitle: "Add", key: "now") { [weak model] in
                model?.newProfile(for: AppRef(bundleID: bundleID, name: name))
            }
        } else {
            entry = .live("Nothing to pass through", symbol: "command", fact: "Bring a remote desktop to the front", key: "now")
        }
        if let bundleID = context.bundleID, let icon = AppIcons.icon(bundleID: bundleID) { entry.leading = .appIcon(icon) }
        return entry
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

    // MARK: - General

    private static func toggles(_ model: MacsBoredModel) -> [MenuEntry] {
        let config = model.config
        var pause = MenuEntry.toggle("Pause shortcut", symbol: "pause.circle", isOn: config.pauseKeys != nil) {
            [weak model] in
            guard let model else { return }
            model.setPauseKeys(model.config.pauseKeys == nil ? MacsBoredConfig.defaultPauseKeys : nil)
        }
        pause.trailing = (config.pauseKeys ?? MacsBoredConfig.defaultPauseKeys).displayName
        var hyper = MenuEntry.toggle("Caps Lock as Hyper", symbol: "capslock", isOn: config.hyperKeyEnabled) {
            [weak model] in
            guard let model else { return }
            model.setHyperKey(!model.config.hyperKeyEnabled)
        }
        hyper.trailing = "⌃⌥⇧⌘"
        var file = MenuEntry.command("Settings file", symbol: "doc.text", key: "settings-file") { [weak model] in
            model?.revealConfigFile()
        }
        file.trailing = "config.json"
        return [
            pause,
            hyper,
            file,
        ]
    }

    // MARK: - Lists

    private static func profileGroup(_ model: MacsBoredModel) -> MenuGroup {
        let rows = model.config.profiles.map { profile in
            var row = MenuEntry.toggle(profile.name, symbol: "macwindow", isOn: profile.isEnabled,
                                             key: "profile-\(profile.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editProfile(profile.id) }),
                                             trash: ("Delete \(profile.name)", { [weak model] in model?.deleteProfile(profile.id) })) {
                [weak model] in model?.toggleProfile(profile.id)
            }
            if let icon = profile.apps.first.flatMap({ AppIcons.icon(bundleID: $0.bundleID) }) { row.leading = .appIcon(icon) }
            return row
        }
        let new = MenuEntry.command("New passthrough app", symbol: "plus", key: "profile-new") { [weak model] in
            model?.newEntry(.passthrough)
        }
        return MenuGroup(title: "Passthrough apps", rows: rows, actions: [new],
                         empty: "None yet. A passthrough app, such as Windows App, Citrix Viewer or a virtual machine, gets macOS's shortcuts.")
    }

    private static func triggerGroup(_ model: MacsBoredModel) -> MenuGroup {
        let rows = model.config.triggers.map { trigger in
            var row = MenuEntry.toggle(trigger.name, symbol: trigger.action.kind.symbol, isOn: trigger.isEnabled,
                                             key: "trigger-\(trigger.id)",
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editTrigger(trigger.id) }),
                                             trash: ("Delete \(trigger.name)", { [weak model] in model?.deleteTrigger(trigger.id) })) {
                [weak model] in model?.toggleTrigger(trigger.id)
            }
            row.trailing = trigger.keys.isEmpty ? "No keys"
                : trigger.keys.count == 1 ? trigger.keys[0].displayName
                : "\(trigger.keys[0].displayName) +\(trigger.keys.count - 1)"
            return row
        }
        // A trigger is one of three kinds: its menu says which, as MacsPane's New preset says how.
        let new = MenuEntry.submenu("New trigger", symbol: "plus", key: "trigger-new", items: [
            .command("Remap keys", symbol: EntryDraft.Tab.remap.symbol, key: "trigger-new-remap") { [weak model] in
                model?.newEntry(.remap)
            },
            .command("Open an app, link or file", symbol: EntryDraft.Tab.open.symbol, key: "trigger-new-open") { [weak model] in
                model?.newEntry(.open)
            },
            .command("Run a Shortcut", symbol: EntryDraft.Tab.shortcut.symbol, key: "trigger-new-shortcut") { [weak model] in
                model?.newEntry(.shortcut)
            },
        ])
        return MenuGroup(title: "Triggers", rows: rows, actions: [new],
                         empty: "None yet. A trigger gives a key a job: remap keys, open something or run a Shortcut.")
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
