#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// MacsBored's page of mac++'s dropdown, Actions, drawn by the same view as MacsPane's: beside its
/// name, the switch for all of it; under its name, what it is doing; then one list of your actions,
/// each row with what it's called, what starts it, a pencil, a bin and its switch, and + Add on the
/// list's title for a new one. Passthrough apps are actions too ("An app is in front"). Accessibility
/// and Open at login belong to the whole app (the dropdown's banner and Settings).
@MainActor
enum MacsBoredMenu {
    static let brand = MenuPageBrand(name: "MacsBored", logo: { AnyView(MacsBoredLogo(size: $0)) },
                                     symbol: "bolt", feature: "Actions")

    static func content(_ model: MacsBoredModel) -> MenuPageContent {
        var content = MenuPageContent()
        // The main switch, beside the name: all of it.
        content.primary = .toggle("Actions", symbol: "bolt", isOn: model.config.isEnabled, primary: true) {
            [weak model] in
            guard let model else { return }
            model.setEnabled(!model.config.isEnabled)
        }
        content.liveFact = statusLine(model)
        content.renaming = model.renamingPack.map { "pack-\($0)" }
        content.warnings = warnings(model)
        content.groups = [actions(model)]
        return content
    }

    /// How many actions are on, after what passthrough is doing when it's doing something.
    private static func statusLine(_ model: MacsBoredModel) -> String {
        if !model.config.isEnabled { return "Off · macOS keeps all its keys" }
        // What can run: an action in a pack that's off isn't on.
        let on = model.config.runningTriggers.filter(\.isEnabled).count + model.config.runningProfiles.filter(\.isEnabled).count
        let count = on == 0 ? "No actions on" : on == 1 ? "1 action on" : "\(on) actions on"
        let app = model.context.appName ?? "the app"
        if model.plan.isActive { return "Sending keys to \(app) · " + count.lowercased() }
        if model.isPaused { return "Paused in \(app) · " + count.lowercased() }
        return count
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

    // MARK: - The list

    /// The packs, each a card holding its actions, then every action in none, then every passthrough
    /// app in none, with + Add on the title: a new action (the editor, on a blank one) or a new pack,
    /// named in place.
    private static func actions(_ model: MacsBoredModel) -> MenuGroup {
        let config = model.config
        let packs = config.packs.map { packRow($0, model) }
        let loose = config.triggers.filter(\.packs.isEmpty).map { triggerRow($0, model) }
            + config.profiles.filter(\.packs.isEmpty).map { profileRow($0, model) }
        let add = MenuEntry.submenu("New", symbol: "plus", key: "new", items: [
            .command("New action", symbol: "bolt", key: "new-action", keepsOpen: true) { [weak model] in
                model?.newEntry(EntryDraft())
            },
            .command("New pack", symbol: "shippingbox", key: "new-pack", keepsOpen: true) { [weak model] in
                model?.startNewPack()
            },
        ])
        var group = MenuGroup(title: "Actions", rows: packs + loose, add: add,
                              empty: "None yet. Add one: when something happens, do a few things.",
                              visibleRows: 6.5)
        group.dropOut = { [weak model] in model?.move(dragged: $0, toPack: nil) }
        return group
    }

    /// A pack: its actions on a card under its name, the app it works in, its switch, its pencil (its
    /// page) and its bin (its actions stay, on their own).
    private static func packRow(_ pack: ActionPack, _ model: MacsBoredModel) -> MenuEntry {
        let config = model.config
        var row = MenuEntry.toggle(pack.name, symbol: "shippingbox", isOn: pack.isEnabled, key: "pack-\(pack.name)",
                                   secondary: ("pencil", "Edit \(pack.name)", { [weak model] in model?.editPack(pack.name) }),
                                   trash: ("Delete \(pack.name), keeping its actions", { [weak model] in model?.deletePack(pack.name) }),
                                   rename: { [weak model] in model?.finishNamingPack(pack.name, to: $0) }) {
            [weak model] in model?.togglePack(pack.name)
        }
        row.keepsOpen = true
        // An action in several packs shows in each.
        let rows = config.triggers.filter { $0.packs.contains(pack.name) }.map { triggerRow($0, model, in: pack.name) }
            + config.profiles.filter { $0.packs.contains(pack.name) }.map { profileRow($0, model, in: pack.name) }
        row.pack = MenuPack(rows: rows, detail: nil,
                            empty: "Empty. Drag actions here, or choose this pack in an action's editor.",
                            drop: { [weak model] in model?.move(dragged: $0, toPack: pack.name) })
        return row
    }

    /// `pack`: the pack whose card it's on, nil for none. An action in several packs has a row on
    /// each card, each its own key, and dragged, it leaves the pack it was dragged from.
    private static func profileRow(_ profile: PassthroughProfile, _ model: MacsBoredModel, in pack: String? = nil) -> MenuEntry {
        let key = MacsBoredModel.dragID(.profile(profile.id), from: pack)
        var row = MenuEntry.toggle(profile.name, symbol: EntryDraft.When.appInFront.symbol, isOn: profile.isEnabled,
                                   key: key,
                                   secondary: ("pencil", "Edit", { [weak model] in model?.editProfile(profile.id) }),
                                   trash: ("Delete \(profile.name)", { [weak model] in model?.deleteProfile(profile.id) })) {
            [weak model] in model?.toggleProfile(profile.id)
        }
        // No picture: what starts an action can be several things.
        row.leading = .none
        row.trailing = profileLabel(profile)
        var does: [String] = []
        if profile.captureAllKeys { does.append("Send it every key") } else if !profile.systemShortcuts.isEmpty { does.append("Send it your Mac's shortcuts") }
        if profile.modifierLayout != .asIs { does.append(profile.modifierLayout.title) }
        row.peek = [.init("When", profile.apps.map { "\(AppIcons.name($0)) is in front" }),
                    .init("Do", does.isEmpty ? ["Nothing yet"] : does)]
        row.keepsOpen = true   // the pencil opens the editor page
        row.dragID = key
        row.countsAs = MacsBoredModel.dragID(.profile(profile.id), from: nil)
        return row
    }

    private static func triggerRow(_ trigger: Trigger, _ model: MacsBoredModel, in pack: String? = nil) -> MenuEntry {
        let key = MacsBoredModel.dragID(.trigger(trigger.id), from: pack)
        var row = MenuEntry.toggle(trigger.name, symbol: trigger.starts.first?.kind.symbol ?? TriggerStart.Kind.keys.symbol, isOn: trigger.isEnabled,
                                   key: key,
                                   secondary: ("pencil", "Edit", { [weak model] in model?.editTrigger(trigger.id) }),
                                   trash: ("Delete \(trigger.name)", { [weak model] in model?.deleteTrigger(trigger.id) })) {
            [weak model] in model?.toggleTrigger(trigger.id)
        }
        // No picture: what starts an action can be several things. Its label, and the bubble from
        // it, say what they are.
        row.leading = .none
        row.trailing = startLabel(trigger)
        row.trailingLabel = "Starts with"
        row.peek = [.init("When", startLabels(trigger)), .init("Do", trigger.steps.map(stepLabel), numbered: trigger.steps.count > 1)]
        row.keepsOpen = true   // the pencil opens the editor page
        row.dragID = key
        row.countsAs = MacsBoredModel.dragID(.trigger(trigger.id), from: nil)
        return row
    }

    /// What an app-in-front entry does, in a word or two: one that only remaps keys says how ("⌥ is
    /// Windows"); one that sends the app shortcuts is "In front".
    static func profileLabel(_ profile: PassthroughProfile) -> String {
        guard profile.systemShortcuts.isEmpty, !profile.captureAllKeys, profile.modifierLayout != .asIs else { return "In front" }
        return profile.modifierLayout.title.components(separatedBy: ", ").first ?? "In front"
    }

    /// What sets it off, in a word or two: "⌃⌥N", "Button 4", "Zoom opens", ";sig", "9:00", and how
    /// many more triggers it has ("Hyper W +2").
    static func startLabel(_ trigger: Trigger) -> String {
        let labels = startLabels(trigger)
        guard let first = labels.first else { return "No trigger" }
        return labels.count == 1 ? first : "\(first) +\(labels.count - 1)"
    }

    /// Each thing that starts it, in a word or two.
    static func startLabels(_ trigger: Trigger) -> [String] {
        var labels: [String] = []
        for start in trigger.starts {
            switch start {
            case .keys: labels += trigger.keys.isEmpty ? ["No keys"] : trigger.keys.map(\.displayName)
            case let .mouseButton(number): labels.append(TriggerStart.buttonName(number))
            case let .appOpens(app): labels.append("\(AppIcons.name(app)) opens")
            case let .typed(letters): labels.append(letters)
            case let .time(minutes): labels.append(clock(minutes))
            case let .doubleTap(key): labels.append("\(key.symbol)\(key.symbol)")
            case let .hold(keys): labels.append("Hold \(keys.displayName)")
            case let .sequence(keys): labels.append(keys.map(\.displayName).joined(separator: " "))
            }
        }
        return labels
    }

    /// A step in a few words: "Open Notes", "Press ⌘[", "Wait 0.5 s".
    static func stepLabel(_ step: TriggerAction) -> String {
        switch step {
        case let .sendKeys(keys): "Press \(keys.displayName)"
        case let .openApp(app): "Open \(AppIcons.name(app))"
        case let .open(target):
            target.contains("://") ? "Open " + (URL(string: target)?.host ?? target)
                : "Open " + ((target as NSString).lastPathComponent.isEmpty ? target : (target as NSString).lastPathComponent)
        case let .runShortcut(name): "Run “\(name)”"
        case let .typeText(text): "Type “\(text.count > 20 ? text.prefix(20) + "…" : text)”"
        case let .wait(seconds): "Wait \(seconds.formatted()) s"
        case .passThrough: "Send the keys to the app"
        case let .runScript(script): script.firstLine.isEmpty ? "Run a script" : "Run “\(script.firstLine.prefix(20))”"
        case let .moveWindow(place): "Window to \(place.title.lowercased())"
        case let .applyPreset(preset): "Arrange “\(presetName(preset))”"
        case let .chooseMenuItem(path): path.titles.last.map { "Choose “\($0)”" } ?? "Choose a menu item"
        }
    }

    /// A preset's name as the Windows tool has it now; the file keeps only its ID.
    static func presetName(_ preset: PresetRef) -> String {
        ActionRunner.presets().first { $0.id == preset.id }?.name ?? preset.name
    }

    /// The time as the Mac's clock writes it.
    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
