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
    /// The held keys, or the keys in a row, being recorded.
    @State private var recordingWhen: EntryDraft.When?
    @State private var keysProblem: String?
    @State private var typing = false
    @State private var typed = ""
    @State private var shortcutNames: [String] = []
    /// The row whose controls are open ("when-keys", "step-<id>"); one at a time.
    @State private var openRow: String?
    @State private var addingTrigger = false
    @State private var addingStep = false
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
            } else {
                // All of it from the start, so setting up one part never moves the others.
                stepsSection
                whereSection
            }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.15), value: openRow)
        .task {
            let names = await Task.detached { ActionRunner.shortcutNames() }.value
            shortcutNames = names
            // The file keeps a preset's ID; show its name as the Windows tool has it now.
            let presets = ActionRunner.presets()
            for index in draft.steps.indices {
                if let id = draft.steps[index].preset?.id, let now = presets.first(where: { $0.id == id }) {
                    state.draft.steps[index].preset = now
                }
            }
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
                Text(draft.sentence ?? "Add what starts it and what it does.")
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
        return VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Triggers", count: draft.whens.count,
                               trailing: draft.whens.count > 1 ? "Any of these starts it" : nil,
                               summary: draft.whens.map { triggerValue($0) ?? Self.cardTitle($0) }.joined(separator: " · "),
                               folded: shut, toggleFold: { toggleFold("Triggers") },
                               add: draft.isPassthroughApp ? nil : { startAdding(trigger: true) },
                               addHelp: "Add a trigger", adding: addingTrigger)
            if !shut {
                VStack(spacing: CardStyle.rowGap) {
                    ForEach(draft.whens, id: \.self) { when in
                        EditorRow(symbol: when.symbol, title: Self.cardTitle(when), value: triggerValue(when),
                                  isOpen: openRow == "when-\(when.rawValue)",
                                  toggle: { toggleRow("when-\(when.rawValue)") },
                                  remove: { draft.remove(when) }, removeHelp: "Remove this trigger") {
                            triggerControls(when)
                        }
                    }
                    if addingTrigger {
                        choices(triggerChoices)
                    } else if draft.whens.isEmpty {
                        EmptyNote(text: "No triggers yet. Click + Add to add one.")
                    }
                }
            }
        }
    }

    private var triggerChoices: [AddChoice] {
        EntryDraft.When.allCases
            .filter { !draft.whens.contains($0) && (draft.whens.isEmpty || $0 != .appInFront) }
            .map { when in .init(title: Self.cardTitle(when), symbol: when.symbol) {
                withAnimation(.easeOut(duration: 0.15)) {
                    draft.add(when)
                    addingTrigger = false
                    openRow = "when-\(when.rawValue)"
                }
            } }
    }

    /// + Add shows its choices at the end of the list, where the new row will go; again hides them.
    private func startAdding(trigger: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            if trigger { addingTrigger.toggle(); addingStep = false } else { addingStep.toggle(); addingTrigger = false }
            if addingTrigger || addingStep { openRow = nil }
        }
    }

    /// What + Add shows, where the new trigger or step will go: its kinds as pills, like every other
    /// choice on the page, on a row card. Choosing one puts it there, open to set.
    private func choices(_ items: [AddChoice]) -> some View {
        ChoiceChips(values: items.map(\.title), title: { $0 },
                    symbol: { title in items.first { $0.title == title }?.symbol }) { title in
            items.first { $0.title == title }?.action()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RowCard())
        .overlay(RoundedRectangle(cornerRadius: CardStyle.rowCorner, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.45)))
    }

    private static func cardTitle(_ when: EntryDraft.When) -> String {
        switch when {
        case .keys: "Keys"
        case .mouseButton: "Mouse button"
        case .appOpens: "App opens"
        case .appInFront: "App in front"
        case .typed: "Typed letters"
        case .time: "Time of day"
        case .doubleTap: "Double-tap"
        case .hold: "Hold keys"
        case .sequence: "Keys in a row"
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
        case .doubleTap: words = draft.doubleTaps.map { $0.symbol + $0.symbol }
        case .hold: words = draft.holdKeys.map(\.displayName)
        case .sequence: words = draft.sequence.count < 2 ? [] : [draft.sequence.map(\.displayName).joined(separator: " ")]
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
        case .doubleTap:
            ToggleChips(values: ModifierKey.allCases, title: { "\($0.symbol) \(Self.modifierName($0))" },
                        isOn: { draft.doubleTaps.contains($0) }) { key in
                if let at = draft.doubleTaps.firstIndex(of: key) { draft.doubleTaps.remove(at: at) }
                else { draft.doubleTaps.append(key) }
            }
            hint("Tap it twice, quickly, on its own. The key still does what it does, so nothing else changes.")
        case .hold:
            KeyRecorderField(keys: Binding(get: { nil }, set: { keys in
                                 guard let keys else { return }
                                 keysProblem = nil
                                 if !draft.holdKeys.contains(keys) { draft.holdKeys.append(keys) }
                             }),
                             recording: recording(.hold),
                             onRefused: { keysProblem = $0 },
                             large: draft.holdKeys,
                             onClear: { draft.holdKeys = [] },
                             model: model)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            problemOr("Hold them a moment to run it. Let go sooner and they do what they always do.")
        case .sequence:
            KeyRecorderField(keys: Binding(get: { nil }, set: { keys in
                                 guard let keys else { return }
                                 guard !draft.sequence.isEmpty || keys.isUsableAsTrigger else {
                                     keysProblem = "Start with keys that use ⌘, ⌃ or ⌥ (or an F-key), so typing never starts it."
                                     return
                                 }
                                 keysProblem = nil
                                 draft.sequence.append(keys)
                             }),
                             recording: recording(.sequence),
                             allowPlain: true,
                             keepsRecording: true,
                             large: draft.sequence,
                             onClear: { draft.sequence = [] },
                             model: model)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            problemOr("Press each set of keys in turn, then esc. Run it by pressing them the same way, each within a second and a half.")
        case .appInFront:
            AppChips(apps: $state.draft.apps, suggestions: KnownPassthroughApps.all.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
            }, stepAway: stepAway)
            hint("While one of these is in front, it gets your Mac's shortcuts: ⌘⇥, Spotlight, the screenshot keys and the rest.")
        }
    }

    private static func modifierName(_ key: ModifierKey) -> String {
        switch key {
        case .command: "Cmd"
        case .option: "Opt"
        case .control: "Ctrl"
        case .shift: "Shift"
        }
    }

    /// Whether the held keys, or the keys in a row, are being recorded; one recorder at a time.
    private func recording(_ when: EntryDraft.When) -> Binding<Bool> {
        Binding(get: { recordingWhen == when }, set: { recordingWhen = $0 ? when : (recordingWhen == when ? nil : recordingWhen) })
    }

    /// What went wrong with the keys just pressed, or else `text`.
    @ViewBuilder private func problemOr(_ text: String) -> some View {
        if let keysProblem {
            hint(keysProblem, symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else {
            hint(text)
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
        return VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Steps", count: draft.steps.count,
                               trailing: draft.steps.count > 1 ? "In order" : nil,
                               summary: draft.steps.map { $0.missing == nil ? $0.phrase : Self.title($0.kind) }.joined(separator: " · "),
                               folded: shut, toggleFold: { toggleFold("Steps") },
                               add: passing ? nil : { startAdding(trigger: false) },
                               addHelp: "Add a step", adding: addingStep)
            if !shut {
                VStack(spacing: CardStyle.rowGap) {
                    ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(index: index, step: step)
                    }
                    if addingStep {
                        choices(stepChoices)
                    } else if draft.steps.isEmpty {
                        EmptyNote(text: "No steps yet. Click + Add to add one.")
                    }
                }
            }
        }
    }

    private var stepChoices: [AddChoice] {
        stepKinds.map { kind in .init(title: Self.title(kind), symbol: kind.symbol) {
            withAnimation(.easeOut(duration: 0.15)) {
                let step = EntryDraft.Step(kind)
                draft.steps.append(step)
                addingStep = false
                openRow = "step-\(step.id)"
            }
        } }
    }

    /// The kinds of step, in the order + Add offers them.
    private var stepKinds: [TriggerAction.Kind] {
        var kinds: [TriggerAction.Kind] = [.openApp, .sendKeys, .typeText, .open, .runShortcut, .runScript,
                                           .moveWindow, .applyPreset, .wait]
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
        case .runScript: "Run a script"
        case .moveWindow: "Move the window"
        case .applyPreset: "Arrange windows"
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
            if shortcutNames.isEmpty {
                hint("No Shortcuts yet. Make one in the Shortcuts app, then it's here.")
            } else {
                ScrollView {
                    ChoiceChips(values: shortcutChoices(step.wrappedValue.text), title: { $0 },
                                isChosen: { $0 == step.wrappedValue.text }) { step.wrappedValue.text = $0 }
                }
                .frame(maxHeight: 128)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
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
        case .runScript:
            Picker("Language", selection: step.language) {
                ForEach(Script.Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
            TextField(step.wrappedValue.language == .shell ? "say \"Hello\"" : "display notification \"Hello\"",
                      text: step.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2...8)
                .frame(maxWidth: .infinity)
            hint(step.wrappedValue.language == .shell
                 ? "Runs in zsh, as Terminal would. The next step waits for it to finish."
                 : "macOS may ask once to let mac++ control the app it talks to. The next step waits for it to finish.")
        case .moveWindow:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.placeGroups, id: \.self) { group in
                    ChoiceChips(values: group, title: \.title, isChosen: { $0 == step.wrappedValue.place }) {
                        step.wrappedValue.place = $0
                    }
                }
            }
            hint("The window you're in, on the screen it's on.")
        case .applyPreset:
            let presets = ActionRunner.presets()
            if presets.isEmpty {
                hint("No presets yet. Make one in the Windows tab, then it's here.")
            } else {
                ChoiceChips(values: presets.map(\.id), title: { id in presets.first { $0.id == id }?.name ?? id },
                            symbol: { _ in TriggerAction.Kind.applyPreset.symbol },
                            isChosen: { $0 == step.wrappedValue.preset?.id }) { id in
                    step.wrappedValue.preset = presets.first { $0.id == id }
                }
            }
            hint("Opens and places the preset's apps, as the Windows tab does.")
        }
    }

    /// Where a window can go, grouped as the Change menu lists them.
    private static let placeGroups: [[WindowPlace]] = [
        [.maximize],
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter],
        [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
    ]

    private func shortcutChoices(_ chosen: String) -> [String] {
        chosen.isEmpty || shortcutNames.contains(chosen) ? shortcutNames : [chosen] + shortcutNames
    }

    /// The apps open now, to pick with a click, the chosen one filled; or any other app.
    private func appChoice(_ app: Binding<AppRef?>) -> some View {
        let chosen = app.wrappedValue
        let open = runningApps
        let shown = chosen.map { picked in open.contains(picked) ? open : [picked] + open } ?? open
        return AppSuggestions(title: "Open now", apps: shown, chosen: chosen, stepAway: stepAway) { app.wrappedValue = $0 }
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
