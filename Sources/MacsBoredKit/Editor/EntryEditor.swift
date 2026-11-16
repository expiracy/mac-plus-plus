#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// The one editor, for every action, as a page of the dropdown, drawn as the Actions list is: a card
/// with its name, what it does in a sentence and its On button; then TRIGGERS and STEPS, each a list
/// of row cards with + Add (a bubble of kinds) on the heading, a row opening in place to its
/// controls when clicked; then WHERE AND WHEN, folded to a line until opened. Every section folds to
/// its title. "An app is in front" is passthrough: on its own, with the app's settings in place of
/// steps.
struct EntryEditor: View {
    @ObservedObject var state: EntryEditorState
    @ObservedObject var model: MacsBoredModel

    private var draft: EntryDraft {
        get { state.draft }
        nonmutating set { state.draft = newValue }
    }

    @State private var recordingKeys = false
    /// The step whose keys are being recorded.
    @State private var recordingStep: UUID?
    @State private var keysProblem: String?
    @State private var typing = false
    @State private var typed = ""
    @State private var shortcutNames: [String] = []
    /// The row whose controls are open ("when-keys", "step-<id>"); one at a time.
    @State private var openRow: String?
    @State private var addingTrigger = false
    @State private var addingStep = false
    /// Room added at the page's foot while + Add's choices need it, so the dropdown grows to hold them.
    @State private var addRoom: CGFloat = 0
    /// The sections folded to their title, by title: where and when starts folded, as the list's do.
    @State private var folded: Set<String> = ["Where and when"]
    @Environment(\.stepAway) private var stepAway

    /// The action only sends its own keys to the app in front.
    private var passing: Bool { draft.steps.map(\.kind) == [.passThrough] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerCard
            triggersSection
            if draft.isPassthroughApp {
                passthroughApp
                FormGroup(title: "Only when", folding: .open,
                          summary: Self.conditionCount(draft.conditions.conditions.count)) {
                    ConditionRows(conditions: $state.draft.conditions, empty: "Whenever one of these apps is in front")
                }
            } else if draft.when != nil {
                stepsSection
                whereSection
            }
        }
        .padding(12)
        .padding(.bottom, addRoom)
        .onChange(of: addingTrigger || addingStep) { _, open in if !open { addRoom = 0 } }
        .overlayPreferenceValue(AddAnchorKey.self) { anchors in
            Color.clear.preference(key: FloatingLayerKey.self, value: addLayer(anchors))
        }
        .animation(.easeOut(duration: 0.15), value: openRow)
        .task {
            let names = await Task.detached { ActionRunner.shortcutNames() }.value
            shortcutNames = names
        }
    }

    private func toggleRow(_ key: String) {
        addingTrigger = false
        addingStep = false
        openRow = openRow == key ? nil : key
    }

    private func isFolded(_ title: String) -> Bool { folded.contains(title) }
    private func toggleFold(_ title: String) {
        if folded.remove(title) == nil { folded.insert(title) }
    }

    // MARK: - The card at the top

    /// As the Actions page's own card: the action's name (typed in place; it follows what it does
    /// until you give one), what it does in a sentence, and its On button.
    private var headerCard: some View {
        let shape = RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(draft.suggestedName, text: $state.draft.customName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .help("The action's name: it follows what it does until you type one")
                Text(draft.sentence ?? "Add a trigger, then what it does.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            PowerButton(name: draft.name, isOn: draft.isEnabled) { draft.isEnabled.toggle() }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(shape.fill(CardStyle.fill))
        .overlay(shape.strokeBorder(CardStyle.stroke))
    }

    // MARK: - Triggers

    private var triggersSection: some View {
        let shut = isFolded("Triggers")
        let choosing = !shut && draft.whens.isEmpty
        return VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Triggers", count: draft.whens.count,
                               trailing: draft.whens.count > 1 ? "Any of these starts it" : nil,
                               summary: draft.whens.map { triggerValue($0) ?? Self.cardTitle($0) }.joined(separator: " · "),
                               folded: shut, toggleFold: { toggleFold("Triggers") },
                               add: draft.isPassthroughApp ? nil : { startAdding(trigger: true) },
                               addHelp: "Add a trigger", adding: addingTrigger)
            if !shut { ForEach(draft.whens, id: \.self) { when in
                EditorRow(symbol: when.symbol, title: Self.cardTitle(when), value: triggerValue(when),
                          isOpen: openRow == "when-\(when.rawValue)",
                          toggle: { toggleRow("when-\(when.rawValue)") },
                          remove: { draft.remove(when) }, removeHelp: "Remove this trigger") {
                    triggerControls(when)
                }
            } }
            // With none yet, the choices are the section, in a row of their own.
            if choosing {
                EditorRow(symbol: "plus", title: "New trigger", isOpen: true, toggle: {}) {
                    AddChoices(items: triggerChoices)
                }
            }
        }
    }

    private var triggerChoices: [AddChoices.Item] {
        EntryDraft.When.allCases
            .filter { !draft.whens.contains($0) && (draft.whens.isEmpty || $0 != .appInFront) }
            .map { when in .init(title: Self.cardTitle(when), symbol: when.symbol) {
                withAnimation(.easeOut(duration: 0.15)) {
                    draft.add(when)
                    addingTrigger = false
                }
            } }
    }

    /// + Add opens its choices in a bubble over the page, as the Actions list's + does; again closes it.
    private func startAdding(trigger: Bool) {
        withAnimation(.easeOut(duration: 0.12)) {
            if trigger { addingTrigger.toggle(); addingStep = false } else { addingStep.toggle(); addingTrigger = false }
        }
    }

    /// The open + Add's choices, floating over the whole dropdown under its pill: over it when there
    /// is room above and not below, and otherwise under it with the page grown to hold them, so none is
    /// ever cut off. A click anywhere else closes them.
    private func addLayer(_ anchors: [String: Anchor<CGRect>]) -> FloatingLayer? {
        let open: (key: String, items: [AddChoices.Item])? =
            addingTrigger && !draft.whens.isEmpty ? ("Triggers", triggerChoices)
            : addingStep && !draft.steps.isEmpty ? ("Steps", stepChoices) : nil
        guard let open, let anchor = anchors[open.key] else { return nil }
        let close = { startAdding(trigger: addingTrigger) }
        let room = $addRoom
        let added = addRoom
        return FloatingLayer(anchor: anchor) { pill, space in
            let width = AddMenu.width
            let x = max(12, min(pill.midX - width + 34, space.width - width - 12))
            let height = AddMenu.height(open.items.count)
            // Measured against the dropdown without the room already added, so the room settles.
            let below = space.height - added - pill.maxY - 4 - 8
            let up = height > below && pill.minY - 4 - height >= 8
            let needed = up ? 0 : min(max(0, height - below), height + 20)
            return AnyView(ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                AddMenu(items: open.items, up: up, nubX: pill.midX - x)
                    .offset(x: x, y: up ? pill.minY - 4 - height : pill.maxY + 4)
                    .transition(.scale(scale: 0.85, anchor: up ? .bottomTrailing : .topTrailing).combined(with: .opacity))
            }
            .onChange(of: needed, initial: true) { _, needed in
                if abs(room.wrappedValue - needed) > 0.5 { room.wrappedValue = needed }
            })
        }
    }

    private static func cardTitle(_ when: EntryDraft.When) -> String {
        switch when {
        case .keys: "Keys"
        case .mouseButton: "Mouse button"
        case .appOpens: "App opens"
        case .appInFront: "App in front"
        case .typed: "Typed letters"
        case .time: "Time of day"
        }
    }

    /// What the trigger is set to, at its row's end: "Hyper W", "Button 4, 5", "9:00".
    private func triggerValue(_ when: EntryDraft.When) -> String? {
        let words: [String]
        switch when {
        case .keys: words = draft.keys.map(\.displayName)
        case .mouseButton: words = draft.mouseButtons.sorted().map { $0 == 3 ? "Middle" : "Button \($0)" }
        case .appOpens: words = draft.openingApps.map(AppIcons.name)
        case .appInFront: words = draft.apps.map(AppIcons.name)
        case .typed: words = draft.letters.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        case .time: words = draft.times.map(MacsBoredMenu.clock)
        }
        guard let first = words.first else { return "Not set" }
        return words.count == 1 ? first : "\(first) +\(words.count - 1)"
    }

    @ViewBuilder private func triggerControls(_ when: EntryDraft.When) -> some View {
        switch when {
        case .keys:
            keysControls
        case .mouseButton:
            ToggleChips(values: Array(Set([3, 4, 5] + draft.mouseButtons)).sorted(),
                        title: { $0 == 3 ? "Middle" : "Button \($0)" },
                        isOn: { draft.mouseButtons.contains($0) }) { button in
                if let at = draft.mouseButtons.firstIndex(of: button) { draft.mouseButtons.remove(at: at) }
                else { draft.mouseButtons.append(button) }
            }
            hint("On most mice, 4 is Back and 5 is Forward. Pick several if you like.")
        case .appOpens:
            AppChips(apps: $state.draft.openingApps, suggestions: runningApps, suggestionsTitle: "Open now", stepAway: stepAway)
        case .typed:
            TextField(";sig", text: $state.draft.letters)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            hint("Type them anywhere: they're taken out again as the steps run. Several? Put spaces between them. Start with ; or , so they never turn up by accident.")
        case .time:
            ForEach(Array(draft.times.enumerated()), id: \.offset) { index, minutes in
                HStack(spacing: 8) {
                    TimeChoice(minutes: minutes) { if draft.times.indices.contains(index) { draft.times[index] = $0 } }
                    Text("every day").foregroundStyle(.secondary)
                    Spacer()
                    if draft.times.count > 1 {
                        iconButton("minus.circle", help: "Remove this time") { draft.times.remove(at: index) }
                    }
                }
            }
            Button { draft.times.append(((draft.times.last ?? 9 * 60) + 60) % (24 * 60)) } label: {
                Label(draft.times.isEmpty ? "Add a Time" : "Add Another Time", systemImage: "plus")
            }
            .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
        case .appInFront:
            AppChips(apps: $state.draft.apps, suggestions: KnownPassthroughApps.all.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
            }, stepAway: stepAway)
            hint("While one of these is in front, it gets your Mac's shortcuts: ⌘⇥, Spotlight, the screenshot keys and the rest.")
        }
    }

    // MARK: - Keys

    /// The keys, large as New Shortcut has them, with what to know about them under them. Passing
    /// keys through usually wants several (⌘Space, ⌘⇥…), so there it keeps listening until esc.
    @ViewBuilder private var keysControls: some View {
        if typing {
            TextField("ctrl+opt+N, cmd+space", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(commitTyped)
        } else {
            KeyRecorderField(keys: Binding(get: { nil }, set: { add($0) }),
                             recording: $recordingKeys,
                             keepsRecording: passing,
                             onRefused: { keysProblem = $0 },
                             large: draft.keys,
                             onClear: { draft.keys = [] },
                             model: model)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
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
            hint(passing
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
                     + (passing ? "While this works, the app gets "
                        + (systemNotes.count == 1 ? "it" : "them") + " instead."
                        : "This action takes " + (systemNotes.count == 1 ? "it" : "them") + " over wherever it works."),
                     symbol: "info.circle")
            }
            if !draft.keys.isEmpty && !passing {
                hint("Click the keys to add another set: any of them starts it.")
            }
            let offered = picks.filter { !draft.keys.contains($0) }
            if !offered.isEmpty, draft.keys.isEmpty || passing {
                FlowLayout(spacing: 4) {
                    Text(passing ? "Common:" : "Free:").font(.caption).foregroundStyle(.secondary)
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
        let candidates = passing
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

    // MARK: - Steps

    private var stepsSection: some View {
        let shut = isFolded("Steps")
        let choosing = !shut && draft.steps.isEmpty
        return VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Steps", count: draft.steps.count,
                               trailing: draft.steps.count > 1 ? "In order" : nil,
                               summary: draft.steps.map { $0.missing == nil ? $0.phrase : Self.title($0.kind) }.joined(separator: " · "),
                               folded: shut, toggleFold: { toggleFold("Steps") },
                               add: passing ? nil : { startAdding(trigger: false) },
                               addHelp: "Add a step", adding: addingStep)
            if !shut {
                ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(index: index, step: step)
                }
            }
            if choosing {
                EditorRow(symbol: "plus", title: "New step", isOpen: true, toggle: {}) {
                    AddChoices(items: stepChoices)
                }
            }
        }
    }

    private var stepChoices: [AddChoices.Item] {
        stepKinds.map { kind in .init(title: Self.title(kind), symbol: kind.symbol) {
            withAnimation(.easeOut(duration: 0.15)) {
                draft.steps.append(EntryDraft.Step(kind))
                addingStep = false
            }
        } }
    }

    /// The kinds of step, in the order + Add offers them.
    private var stepKinds: [TriggerAction.Kind] {
        var kinds: [TriggerAction.Kind] = [.openApp, .sendKeys, .typeText, .open, .runShortcut, .wait]
        if draft.whens == [.keys] && draft.steps.isEmpty { kinds.append(.passThrough) }
        return kinds
    }

    private static func title(_ kind: TriggerAction.Kind) -> String {
        switch kind {
        case .sendKeys: "Press other keys"
        case .openApp: "Open an app"
        case .open: "Open a link or file"
        case .runShortcut: "Run a Shortcut"
        case .typeText: "Type text"
        case .wait: "Wait"
        case .passThrough: "Send these keys to the app"
        }
    }

    /// One step as a row: its number (when there are several), what it does, and its bin;
    /// open, its control, and buttons to move it.
    private func stepRow(index: Int, step: EntryDraft.Step) -> some View {
        let binding = Binding<EntryDraft.Step>(
            get: { draft.steps.first { $0.id == step.id } ?? step },
            set: { new in if let at = draft.steps.firstIndex(where: { $0.id == step.id }) { draft.steps[at] = new } })
        return EditorRow(number: draft.steps.count > 1 ? index + 1 : nil, symbol: step.kind.symbol,
                         title: step.missing == nil ? step.phrase : Self.title(step.kind),
                         value: step.missing == nil ? nil : "Not set",
                         isOpen: openRow == "step-\(step.id)",
                         toggle: { toggleRow("step-\(step.id)") },
                         remove: { draft.steps.removeAll { $0.id == step.id } }, removeHelp: "Remove this step") {
            stepControl(binding)
            if draft.steps.count > 1 {
                HStack(spacing: 12) {
                    if index > 0 {
                        Button { draft.steps.swapAt(index, index - 1) } label: { Label("Move Up", systemImage: "arrow.up") }
                    }
                    if index < draft.steps.count - 1 {
                        Button { draft.steps.swapAt(index, index + 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                    }
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder private func stepControl(_ step: Binding<EntryDraft.Step>) -> some View {
        switch step.wrappedValue.kind {
        case .sendKeys:
            KeyRecorderField(keys: step.keys,
                             recording: Binding(get: { recordingStep == step.wrappedValue.id },
                                                set: { recordingStep = $0 ? step.wrappedValue.id : nil }),
                             allowPlain: true, model: model)
        case .openApp:
            appChoice(step.app)
        case .open:
            HStack(spacing: 6) {
                TextField("https://… or ~/Documents/plan.pdf", text: step.text)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                Button("Choose…") { chooseFile { step.wrappedValue.text = $0 } }
            }
        case .runShortcut:
            HStack(spacing: 8) {
                if !step.wrappedValue.text.isEmpty {
                    ChosenChip(title: step.wrappedValue.text, symbol: "square.stack.3d.up")
                }
                LinkMenu(title: step.wrappedValue.text.isEmpty ? "Choose a Shortcut" : "Change") {
                    ForEach(shortcutChoices(step.wrappedValue.text), id: \.self) { name in
                        Button(name) { step.wrappedValue.text = name }
                    }
                    if shortcutNames.isEmpty { Text("No Shortcuts yet") }
                    Divider()
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                }
                Spacer(minLength: 0)
            }
        case .typeText:
            TextField("Text to type", text: step.text, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4).frame(maxWidth: .infinity)
        case .wait:
            HStack(spacing: 8) {
                Picker("Wait", selection: step.seconds) {
                    ForEach([0.5, 1, 2, 5], id: \.self) { Text("\($0.formatted())s").tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                Text("or").font(.callout).foregroundStyle(.secondary)
                TextField("Seconds", value: Binding(get: { step.wrappedValue.seconds },
                                                     set: { step.wrappedValue.seconds = min(max($0, 0.1), TriggerAction.longestWait) }),
                          format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 58)
                    .help("Any time up to an hour, in seconds")
                Text("s").font(.callout).foregroundStyle(.secondary)
            }
        case .passThrough:
            hint("The keys above go straight to the app in front, ahead of macOS and other apps' shortcuts.")
        }
    }

    private func shortcutChoices(_ chosen: String) -> [String] {
        chosen.isEmpty || shortcutNames.contains(chosen) ? shortcutNames : [chosen] + shortcutNames
    }

    /// The app chosen, as a chip, and a menu to choose or change it.
    private func appChoice(_ app: Binding<AppRef?>) -> some View {
        HStack(spacing: 8) {
            if let chosen = app.wrappedValue {
                ChosenChip(title: AppIcons.name(chosen), icon: AppIcons.icon(bundleID: chosen.bundleID))
            }
            LinkMenu(title: app.wrappedValue == nil ? "Choose an App" : "Change") {
                Section("Open now") { ForEach(runningApps) { running in Button(running.name) { app.wrappedValue = running } } }
                Divider()
                Button("Choose an app…") { stepAway { AppChooser.choose { app.wrappedValue = $0 } } }
            }
        }
    }

    private func chooseFile(_ picked: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        stepAway {
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            picked((url.path as NSString).abbreviatingWithTildeInPath)
        }
    }

    // MARK: - Where (triggers) and the passthrough app

    /// Where it works (for what happens in an app: keys, clicks, typing) and when: folded to its
    /// heading and a summary ("Everywhere · always") until opened.
    private var whereSection: some View {
        let inApps = draft.whens.contains { [.keys, .mouseButton, .typed].contains($0) }
        let place = inApps && draft.onlyInApps
            ? (draft.apps.isEmpty ? "In apps you choose" : "Only in " + draft.apps.map(AppIcons.name).joined(separator: ", "))
            : "Everywhere"
        let count = draft.conditions.conditions.count
        let summary = place + " · " + Self.conditionCount(count).lowercased()
        return VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Where and when", summary: summary,
                               folded: isFolded("Where and when"), toggleFold: { toggleFold("Where and when") })
            if !isFolded("Where and when") {
                FormGroup {
                    if inApps {
                        FormRow(label: "Works", divider: false) {
                            Picker("Works", selection: $state.draft.onlyInApps) {
                                Text("Everywhere").tag(false)
                                Text("Only in some apps").tag(true)
                            }
                            .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                            Spacer()
                        }
                        if draft.onlyInApps {
                            FormRow(label: "Apps", top: true) {
                                AppChips(apps: $state.draft.apps, suggestions: runningApps, suggestionsTitle: "Open now", stepAway: stepAway)
                            }
                        }
                    }
                    ConditionRows(conditions: $state.draft.conditions, label: "When", empty: "Always", dividedFromAbove: inApps)
                }
            }
        }
    }

    private static func conditionCount(_ count: Int) -> String {
        count == 0 ? "Always" : count == 1 ? "1 condition" : "\(count) conditions"
    }

    private var runningApps: [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { AppRef(bundleID: $0, name: app.localizedName ?? $0) } }
    }

    /// While the app is in front, which of macOS's shortcuts it gets, and how its keys reach it.
    @ViewBuilder private var passthroughApp: some View {
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
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                Spacer()
            }
        }
    }
}

#endif
