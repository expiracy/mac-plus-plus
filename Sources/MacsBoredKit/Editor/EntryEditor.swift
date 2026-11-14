#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// The one editor, for everything MacsBored does, as a page of the dropdown. What it makes (remap keys,
/// open something, run a Shortcut, or pass keys through) is set by the + that opened it, or by the
/// entry being edited.
struct EntryEditor: View {
    @ObservedObject var state: EntryEditorState
    @ObservedObject var model: MacsBoredModel

    private var draft: EntryDraft {
        get { state.draft }
        nonmutating set { state.draft = newValue }
    }

    @State private var recordingKeys = false
    @State private var recordingSend = false
    @State private var keysProblem: String?
    @State private var typing = false
    @State private var typed = ""
    @State private var shortcutNames: [String] = []
    @Environment(\.stepAway) private var stepAway

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identity
            if [.remap, .open, .shortcut].contains(draft.tab) { whatItDoes }
            if draft.isPassthroughApp { passthroughApp } else { whereGroup }
            FormGroup(title: "When") {
                if draft.conditions.conditions.isEmpty {
                    FormRow(divider: false) {
                        Text(draft.isPassthroughApp ? "Whenever one of these apps is in front" : "Always")
                            .foregroundStyle(.secondary)
                    }
                }
                ConditionRows(conditions: $state.draft.conditions)
            }
        }
        .padding(12)
        .task {
            let names = await Task.detached { ActionRunner.shortcutNames() }.value
            shortcutNames = names
        }
    }

    // MARK: - Tabs

    // MARK: - Name and keys

    private var identity: some View {
        FormGroup {
            if draft.tab == .passthrough {
                FormRow(label: "Pass through", divider: false) {
                    Picker("Pass through", selection: $state.draft.passMode) {
                        Text("A whole app").tag(EntryDraft.PassMode.wholeApp)
                        Text("Only some keys").tag(EntryDraft.PassMode.someKeys)
                    }
                    .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                    Spacer()
                }
            }
            FormRow(label: "Name", divider: draft.tab == .passthrough) {
                TextField(draft.suggestedName, text: $state.draft.customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                if draft.isPassthroughApp {
                    Text(draft.isEnabled ? "On" : "Off").foregroundStyle(.secondary)
                    Toggle("On", isOn: $state.draft.isEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
            if !draft.isPassthroughApp {
                FormRow(label: draft.tab == .passthrough ? "Keys to pass" : "Keys", top: true) { keysControl }
            }
        }
    }

    /// The keys as removable chips, then a field to record more. Passing keys through usually wants
    /// several (⌘Space, ⌘⇥…), so there the field keeps listening until esc.
    private var keysControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typing {
                TextField("ctrl+opt+N, cmd+space", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .onSubmit(commitTyped)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(draft.keys, id: \.self) { keyChip($0) }
                    KeyRecorderField(keys: Binding(get: { nil }, set: { add($0) }),
                                     recording: $recordingKeys,
                                     placeholder: draft.keys.isEmpty ? "Click to record" : "Add keys…",
                                     width: draft.keys.isEmpty ? FormMetric.field : 120,
                                     keepsRecording: draft.tab == .passthrough,
                                     onRefused: { keysProblem = $0 },
                                     model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            keysHint
            Button(typing ? "Record instead" : "Type instead") {
                    keysProblem = nil
                    if typing {
                        commitTyped()
                        if keysProblem == nil { typing = false }
                    } else {
                        typed = draft.keys.map(\.text).joined(separator: ", ")
                        typing = true
                    }
                }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    /// One set of keys as keycaps, with a button that takes it out.
    private func keyChip(_ keys: KeyCombo) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
            Button { draft.keys.removeAll { $0 == keys } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(keys.displayName)")
            .accessibilityLabel("Remove \(keys.displayName)")
        }
        .padding(.leading, 4).padding(.trailing, 2)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func add(_ keys: KeyCombo?) {
        guard let keys else { return }
        keysProblem = nil
        if !draft.keys.contains(keys) { draft.keys.append(keys) }
    }

    /// Typed keys, as the settings file writes them; several are separated by commas.
    private func commitTyped() {
        var parsed: [KeyCombo] = []
        for part in typed.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            guard let keys = KeyCombo(text: part) else {
                keysProblem = "“\(part)” isn't keys MacsBored knows. Write them like ctrl+opt+cmd+P or hyper+N."
                return
            }
            guard keys.isUsableAsTrigger else {
                keysProblem = "“\(part)” on its own would take over typing. Add ctrl, opt or cmd, or use an F-key."
                return
            }
            if !parsed.contains(keys) { parsed.append(keys) }
        }
        keysProblem = nil
        draft.keys = parsed
        typed = parsed.map(\.text).joined(separator: ", ")
    }

    @ViewBuilder private var keysHint: some View {
        if let keysProblem {
            hint(keysProblem, symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else if recordingKeys {
            hint(draft.tab == .passthrough
                 ? "Press each shortcut the app should get, one after another. esc when you're done."
                 : "Hold the modifiers, then press a key. esc stops.")
        } else if typing {
            hint("As the settings file writes them, separated by commas: ctrl+opt+N, cmd+space. Return to use them.")
        } else {
            if let (keys, other) = clash {
                hint("\(keys.displayName) already runs “\(other.name)”. Saving moves it here.",
                     symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if !systemNotes.isEmpty {
                hint("macOS uses " + ListFormatter.localizedString(byJoining: systemNotes) + ". "
                     + (draft.tab == .passthrough ? "While this works, the app gets "
                        + (systemNotes.count == 1 ? "it" : "them") + " instead."
                        : "This trigger takes " + (systemNotes.count == 1 ? "it" : "them") + " over wherever it works."),
                     symbol: "info.circle")
            }
            let offered = picks.filter { !draft.keys.contains($0) }
            if !offered.isEmpty, draft.keys.isEmpty || draft.tab == .passthrough {
                FlowLayout(spacing: 4) {
                    Text(draft.tab == .passthrough ? "Common:" : "Free:").font(.caption).foregroundStyle(.secondary)
                    ForEach(offered, id: \.self) { keys in
                        Button(keys.modifiers == .hyper ? "Hyper \(keys.keyName)" : keys.displayName) { add(keys) }
                            .controlSize(.mini)
                    }
                }
            }
        }
    }

    /// The first of these keys another trigger already has in the same place.
    private var clash: (KeyCombo, Trigger)? {
        for keys in draft.keys {
            if let other = model.trigger(using: keys, apps: draft.onlyInApps ? draft.apps : [], except: triggerID) {
                return (keys, other)
            }
        }
        return nil
    }

    /// "⌘Space to open Spotlight", for each of these keys macOS uses itself.
    private var systemNotes: [String] {
        draft.keys.compactMap { keys in Self.systemUses[keys].map { "\(keys.displayName) to \($0)" } }
    }

    private func hint(_ text: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(text).foregroundStyle(tint == .orange ? Color.primary.opacity(0.75) : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    private var triggerID: UUID? {
        if case let .trigger(id) = draft.origin { return id }
        return nil
    }

    /// A few keys to add with a click: ones nothing else here uses, or, to pass through, the shortcuts
    /// a session most often wants.
    private var picks: [KeyCombo] {
        let candidates = draft.tab == .passthrough
            ? ["cmd+space", "cmd+tab", "ctrl+left", "ctrl+right"]
            : ["ctrl+opt+N", "ctrl+opt+cmd+N", "hyper+N", "F13"]
        return candidates.compactMap(KeyCombo.init(text:)).filter { model.trigger(using: $0, apps: [], except: nil) == nil }
    }

    private static let systemUses: [KeyCombo: String] = {
        let uses = ["cmd+space": "open Spotlight", "cmd+tab": "switch apps", "shift+cmd+3": "take a screenshot",
                    "shift+cmd+4": "take a screenshot", "shift+cmd+5": "take a screenshot", "ctrl+up": "open Mission Control",
                    "ctrl+left": "move to the space on the left", "ctrl+right": "move to the space on the right",
                    "ctrl+space": "change the input source"]
        return Dictionary(uniqueKeysWithValues: uses.compactMap { text, use in KeyCombo(text: text).map { ($0, use) } })
    }()

    // MARK: - What it does

    private var whatItDoes: some View {
        FormGroup(title: "What it does") {
            switch draft.tab {
            case .remap:
                FormRow(label: "Press instead", divider: false) {
                    KeyRecorderField(keys: $state.draft.sendKeys, recording: $recordingSend, allowPlain: true, model: model)
                    Spacer()
                }
            case .open:
                FormRow(label: "Open", divider: false) {
                    Picker("Open", selection: $state.draft.openTarget) {
                        Text("An app").tag(EntryDraft.OpenTarget.app)
                        Text("A link").tag(EntryDraft.OpenTarget.link)
                        Text("A file or folder").tag(EntryDraft.OpenTarget.file)
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                }
                switch draft.openTarget {
                case .app:
                    FormRow(label: "App") { appPicker; Spacer() }
                case .link:
                    FormRow(label: "Link") {
                        TextField("https://…", text: $state.draft.link).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                case .file:
                    FormRow(label: "File") {
                        TextField("~/Documents/plan.pdf", text: $state.draft.file).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        Button("Choose…", action: chooseFile)
                    }
                }
            case .shortcut:
                FormRow(label: "Shortcut", divider: false) {
                    Picker("Shortcut", selection: $state.draft.shortcutName) {
                        Text("Choose a Shortcut").tag("")
                        ForEach(shortcutChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                FormRow {
                    Spacer()
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            case .passthrough:
                EmptyView()
            }
        }
    }

    private var shortcutChoices: [String] {
        let names = shortcutNames
        return draft.shortcutName.isEmpty || names.contains(draft.shortcutName) ? names : [draft.shortcutName] + names
    }

    private var appPicker: some View {
        HStack(spacing: 6) {
            if let app = draft.app, let icon = AppIcons.icon(bundleID: app.bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            }
            appMenu.fixedSize()
        }
    }

    private var appMenu: some View {
        Menu {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                .compactMap { app -> AppRef? in
                    guard let id = app.bundleIdentifier else { return nil }
                    return AppRef(bundleID: id, name: app.localizedName ?? id)
                }
            Section("Open now") { ForEach(running) { app in Button(app.name) { draft.app = app } } }
            Divider()
            Button("Choose an app…") { stepAway { AppChooser.choose { draft.app = $0 } } }
        } label: {
            Text(draft.app.map(AppIcons.name) ?? "Choose an app")
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        stepAway {
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            draft.file = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    // MARK: - Where (triggers) and the passthrough app

    private var whereGroup: some View {
        FormGroup(title: "Where") {
            FormRow(label: "Works", divider: false) {
                Picker("Works", selection: $state.draft.onlyInApps) {
                    Text("Everywhere").tag(false)
                    Text("Only in certain apps").tag(true)
                }
                .labelsHidden().fixedSize()
                Spacer()
            }
            if draft.onlyInApps {
                FormRow(label: "Apps", top: true) {
                    AppChips(apps: $state.draft.apps, suggestions: runningApps, suggestionsTitle: "Open now", stepAway: stepAway)
                }
            }
        }
    }

    private var runningApps: [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { AppRef(bundleID: $0, name: app.localizedName ?? $0) } }
    }

    @ViewBuilder private var passthroughApp: some View {
        FormGroup(title: "Apps") {
            FormRow(top: true, divider: false) {
                AppChips(apps: $state.draft.apps, suggestions: KnownPassthroughApps.all.filter {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
                }, stepAway: stepAway)
            }
        }
        let all = Set(SystemShortcutGroup.allCases)
        FormGroup(title: "macOS shortcuts sent to the app",
                  trailing: AnyView(Button(draft.systemShortcuts == all ? "Select None" : "Select All") {
                      draft.systemShortcuts = draft.systemShortcuts == all ? [] : all
                  }.buttonStyle(.borderless).controlSize(.small)),
                  folding: .folded, summary: "\(draft.systemShortcuts.count) of \(all.count)") {
            ForEach(Array(SystemShortcutGroup.allCases.enumerated()), id: \.element) { index, group in
                FormRow(divider: index > 0) {
                    Toggle(isOn: Binding(get: { draft.systemShortcuts.contains(group) }, set: { on in
                        if on { draft.systemShortcuts.insert(group) } else { draft.systemShortcuts.remove(group) }
                    })) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.title)
                                Spacer(minLength: 6)
                                Text(group.keys).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(group.windowsMeaning).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        FormGroup(title: "Keys", folding: .folded,
                  summary: draft.captureAllKeys ? "Every key to the app" : draft.modifierLayout.title) {
            FormRow(divider: false) {
                Text("Send every key straight to the app")
                    .help("Ahead of global shortcuts from Raycast, Alfred or window managers. Only triggers that name this app still run.")
                Spacer()
                Toggle("Send every key straight to the app", isOn: $state.draft.captureAllKeys)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            FormRow(label: "Modifiers") {
                Picker("Modifier keys", selection: $state.draft.modifierLayout) {
                    ForEach(ModifierLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                Spacer()
            }
        }
    }
}

#endif
