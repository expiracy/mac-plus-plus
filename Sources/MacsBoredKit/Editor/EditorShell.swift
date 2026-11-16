#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

// MARK: - Form pieces, one look for every page

/// The editor's sizes, to fit the dropdown's width: a label column, then a field, on the menu's rows.
enum FormMetric {
    static let label: CGFloat = 84
    static let field: CGFloat = 232
    static let row: CGFloat = 38
}

/// A titled group of rows on a card, drawn as the rest of the dropdown draws its sections: the same
/// heading, card and hairlines. A long group can fold to its heading as the menu's sections do (a
/// chevron before it, and `summary` beside it while folded).
struct FormGroup<Content: View>: View {
    enum Folding { case never, open, folded }

    var title: String?
    var caption: String? = nil
    var trailing: AnyView? = nil
    var folding: Folding = .never
    var summary: String? = nil
    @ViewBuilder var content: Content
    @State private var foldedNow: Bool?

    private var folded: Bool { foldedNow ?? (folding == .folded) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    if folding == .never {
                        SectionLabel(title)
                    } else {
                        foldButton(title)
                    }
                    Spacer()
                    if !folded { trailing }
                }
                .padding(.horizontal, 4)
            }
            if !folded {
                VStack(spacing: 0) { content }
                    .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(CardStyle.fill))
                    .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(CardStyle.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous))
                if let caption, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func foldButton(_ title: String) -> some View {
        HStack(spacing: 6) {
            FoldTitle(title: title, folded: folded) { foldedNow = !folded }
            Spacer(minLength: 6)
            if folded, let summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// A section's title that folds it, as the menu's sections fold: a chevron before the name in small
/// capitals; click it to fold the section to its title or open it again.
struct FoldTitle: View {
    let title: String
    let folded: Bool
    let toggle: () -> Void

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded ? 0 : 90))
                    .frame(width: 12)
                SectionLabel(title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show \(title)" : "Hide \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(folded ? "Collapsed" : "Expanded")
    }
}

/// Values to switch on and off, as small pills: the ones on filled with the accent.
struct ToggleChips<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    let isOn: (Value) -> Bool
    let toggle: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                let on = isOn(value)
                Button { toggle(value) } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        Text(title(value))
                    }
                    .font(.callout.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(value))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A menu drawn as the rest of the page draws its links: accent text, a small chevron after it.
struct LinkMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: {
            Text("\(title) \(Image(systemName: "chevron.down"))")
        }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
    }
}

/// Something chosen (an app, a Shortcut), as the app chips draw it: its icon and name on a soft fill.
struct ChosenChip: View {
    let title: String
    var icon: NSImage? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            } else if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            Text(title).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// A time of day as the page's chips draw choices: the hour and the minute, each a chip that opens
/// its list, and AM | PM pills where the Mac uses a 12-hour clock.
struct TimeChoice: View {
    /// Minutes since midnight.
    let minutes: Int
    let set: (Int) -> Void

    private static let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    private var hour: Int { minutes / 60 }
    private var minute: Int { minutes % 60 }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(Self.twelveHour ? Array(1...12) : Array(0...23), id: \.self) { shown in
                    Button(Self.twelveHour ? "\(shown)" : String(format: "%02d", shown)) { set(hourOf(shown) * 60 + minute) }
                }
            } label: { chip(Self.twelveHour ? "\(hour % 12 == 0 ? 12 : hour % 12)" : String(format: "%02d", hour)) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Hour")
            Text(":").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            Menu {
                ForEach(Array(Set(Array(stride(from: 0, to: 60, by: 5)) + [minute])).sorted(), id: \.self) { value in
                    Button(String(format: "%02d", value)) { set(hour * 60 + value) }
                }
            } label: { chip(String(format: "%02d", minute)) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Minute")
            if Self.twelveHour {
                Picker("AM or PM", selection: Binding(get: { hour >= 12 }, set: { pm in
                    set(((hour % 12) + (pm ? 12 : 0)) * 60 + minute)
                })) {
                    Text("AM").tag(false)
                    Text("PM").tag(true)
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                .padding(.leading, 4)
            }
        }
    }

    /// The hour of the day a shown hour means, keeping the morning or afternoon on a 12-hour clock.
    private func hourOf(_ shown: Int) -> Int {
        guard Self.twelveHour else { return shown }
        return (shown % 12) + (hour >= 12 ? 12 : 0)
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
    }
}

/// A section's heading as the Actions list draws its own: a chevron that folds it, the name in small
/// capitals, a count in the accent, and + Add at its end (nil for none), which opens it if folded.
/// Folded, `summary` says what it holds; open, `trailing` says how its rows go together.
struct EditorSectionTitle: View {
    let title: String
    var count: Int? = nil
    var trailing: String? = nil
    var summary: String? = nil
    let folded: Bool
    let toggleFold: () -> Void
    var add: (() -> Void)? = nil
    var addHelp = "Add"
    /// Its + Add's choices are showing.
    var adding = false

    var body: some View {
        HStack(spacing: 8) {
            FoldTitle(title: title, folded: folded, toggle: toggleFold)
            Spacer(minLength: 6)
            if let note = folded ? summary : trailing {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            if let count, count > 0 {
                Text("\(count)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Color.accentColor)
            }
            if let add {
                AddPill(help: addHelp, open: adding) {
                    if folded { toggleFold() }
                    add()
                }
                .anchorPreference(key: AddAnchorKey.self, value: .bounds) { [title: $0] }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One row of the editor's lists, drawn as the Actions list draws its rows (a card each): its icon,
/// what it is, its value and a bin. Click it and it opens in place, its controls under it on the same
/// card, as the list's rows open; click it again to close it.
struct EditorRow<Controls: View>: View {
    var number: Int? = nil
    let symbol: String
    let title: String
    var value: String? = nil
    let isOpen: Bool
    let toggle: () -> Void
    /// The bin; nil leaves it out.
    var remove: (() -> Void)? = nil
    var removeHelp = "Remove"
    @ViewBuilder var controls: Controls
    @State private var hovering = false
    @State private var hotBin = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let number {
                    Text("\(number)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                IconTile(symbol: symbol, size: 24)
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let value, !isOpen {
                    Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                if let remove { Button(action: remove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hotBin ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hotBin = $0 }
                .help(removeHelp)
                .accessibilityLabel("\(removeHelp): \(title)") }
            }
            .padding(.horizontal, 10)
            .frame(height: CardStyle.rowHeight)
            .background(Color.primary.opacity(hovering || isOpen ? 0.04 : 0))
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .onHover { hovering = $0 }
            .help(isOpen ? "Click to close" : "Click to change")
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityAction(named: isOpen ? "Close \(title)" : "Change \(title)", toggle)
            if isOpen {
                Divider().padding(.leading, 10)
                VStack(alignment: .leading, spacing: 6) { controls }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(RowCard())
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: CardStyle.rowCorner, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45))
            }
        }
    }
}

/// What a section with nothing in it yet offers, inside its one row: a tile each, two to a line.
struct AddChoices: View {
    struct Item: Identifiable {
        let title: String
        let symbol: String
        let action: () -> Void
        var id: String { title }
    }

    let items: [Item]
    @State private var hovered: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 8) {
                        IconTile(symbol: item.symbol, size: 22)
                        Text(item.title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hovered == item.id ? 0.09 : 0.045)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            }
        }
    }
}

/// Where each section's + Add sits, by section title, for its choices' bubble to hang from.
struct AddAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// + Add's choices in a bubble of the dropdown's own kind, as the Actions list's + draws its own:
/// a row each, its icon in a tile, its nub pointing at the +.
struct AddMenu: View {
    static let width: CGFloat = 230
    static func height(_ count: Int) -> CGFloat {
        CGFloat(count) * (CardStyle.rowHeight - 4) + 12 + SpeechBubbleShape.standardNub.height
    }

    let items: [AddChoices.Item]
    let up: Bool
    let nubX: CGFloat
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 10) {
                        IconTile(symbol: item.symbol, size: 24)
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: CardStyle.rowHeight - 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hovered == item.id ? 0.06 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
                .overlay(alignment: .top) { if index > 0 { Divider().padding(.horizontal, 8) } }
            }
        }
        .padding(6)
        .padding(up ? .bottom : .top, SpeechBubbleShape.standardNub.height)
        .frame(width: Self.width)
        .background(SpeechBubbleShape(nubX: nubX, corner: CardStyle.corner, pointsDown: up)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: nubX, corner: CardStyle.corner, pointsDown: up)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }
}

/// "+ Add" as the dropdown's section titles draw it: a small pill.
struct AddPill: View {
    var title = "Add"
    let help: String
    var open = false
    let action: () -> Void
    @State private var hot = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.primary.opacity(hot || open ? 0.12 : 0.07)))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: hot)
        }
        .buttonStyle(.plain)
        .onHover { hot = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A row: its label in the one left-hand column, then its control.
struct FormRow<Content: View>: View {
    var label: String?
    var top = false
    var divider = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: top ? .top : .center, spacing: 8) {
            if let label {
                Text(label).frame(width: FormMetric.label, alignment: .leading)
                    .frame(minHeight: 28)
            }
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: FormMetric.row, alignment: .leading)
        .overlay(alignment: .top) { if divider { Divider().padding(.leading, 10) } }
    }
}

/// The box every single-value control sits in: a text field's border, height and width.
struct FieldBox<Content: View>: View {
    var active = false
    var problem = false
    var width: CGFloat = FormMetric.field
    @ViewBuilder var content: Content
    @Environment(\.controlSize) private var controlSize

    /// A rounded text field's height at the control size around it.
    private var height: CGFloat {
        switch controlSize {
        case .large, .extraLarge: 28
        case .small: 19
        case .mini: 16
        default: 22
        }
    }

    var body: some View {
        HStack(spacing: 4) { content }
            .padding(.horizontal, 6)
            .frame(width: width, height: height, alignment: .leading)
            .background {
                // An empty text field underneath, so this box has exactly the name field's look.
                TextField("", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .focusable(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                if active || problem {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(problem ? Color.orange : Color.accentColor, lineWidth: 2)
                        .padding(-1)
                }
            }
            .contentShape(Rectangle())
    }
}

/// A key drawn as a keycap.
struct KeyCap: View {
    let text: String
    var held = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 6)
            .frame(minWidth: 21, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .opacity(held ? 0.5 : 1)
    }
}

extension KeyCombo {
    /// Each modifier and the key, as keycaps show them.
    var caps: [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1) + [keyName]
    }
}

/// A key recorder in a field: the keys as keycaps, or, once clicked, the modifiers you hold as you
/// hold them, waiting for a key. esc stops; ⌫ alone clears it.
struct KeyRecorderField: View {
    @Binding var keys: KeyCombo?
    @Binding var recording: Bool
    /// Accept keys without ⌘, ⌃ or ⌥ (for keys pressed instead, where ↖ alone is fine).
    var allowPlain = false
    var placeholder = "Click to record"
    var width: CGFloat = FormMetric.field
    /// Keep listening after each set of keys, for adding several in a row; esc or a click stops.
    var keepsRecording = false
    var onRefused: (String) -> Void = { _ in }
    /// Drawn large, as New Shortcut's keys are, showing these keys (and clearing them with its x).
    var large: [KeyCombo]? = nil
    var onClear: () -> Void = {}
    let model: MacsBoredModel
    @State private var held: KeyCombo.Modifiers = []
    @State private var monitor: Any?

    var body: some View {
        if let large { largeBody(large) } else { fieldBody }
    }

    /// The keys as big keycaps in the middle of the card, or a prompt in the accent; dashed round
    /// while it waits for keys.
    private func largeBody(_ shown: [KeyCombo]) -> some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            if recording && !held.isEmpty {
                bigCaps(Array(KeyCombo(keyCode: 0, modifiers: held).caps.dropLast()), held: true)
            } else if !shown.isEmpty && !(recording && !keepsRecording) {
                ForEach(shown, id: \.self) { bigCaps($0.caps) }
                if recording {
                    Text("then the next…").font(.callout).foregroundStyle(Color.accentColor)
                }
            } else {
                Label(recording ? "Press the keys" : "Click, then press the keys", systemImage: "keyboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, minHeight: 50)
        .overlay {
            if recording {
                RoundedRectangle(cornerRadius: CardStyle.corner - 2, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(4)
            }
        }
        .overlay(alignment: .trailing) {
            if !shown.isEmpty, !recording {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .help("Clear the keys")
                    .padding(.trailing, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { recording ? stop() : start() }
        .help(recording ? "Press the keys, holding ⌘, ⌃ or ⌥; esc stops waiting" : "Click to press the keys")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keys: " + (shown.isEmpty ? "none" : shown.map(\.displayName).joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
        .onDisappear { stop() }
        .onChange(of: recording) { _, now in if !now { stop() } }
    }

    /// Keycaps as New Shortcut draws them.
    private func bigCaps(_ caps: [String], held: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, cap.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 0, y: 1))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                    .opacity(held ? 0.5 : 1)
            }
        }
    }

    private var fieldBody: some View {
        Button { recording ? stop() : start() } label: {
            FieldBox(active: recording, width: width) {
                if recording {
                    ForEach(KeyCombo(keyCode: 0, modifiers: held).caps.dropLast(), id: \.self) { KeyCap(text: $0, held: true) }
                    if held.isEmpty { Text("Press the keys…").foregroundStyle(.secondary).padding(.leading, 3) }
                    Spacer(minLength: 0)
                    Circle().fill(Color.red).frame(width: 6, height: 6).padding(.trailing, 3)
                } else if let keys {
                    ForEach(Array(keys.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                    Spacer(minLength: 0)
                } else {
                    Text(placeholder).foregroundStyle(.secondary).padding(.leading, 3)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .help(recording ? "Hold the modifiers, then press a key" : "Click, then press the keys")
        .accessibilityLabel("Keys: \(keys?.displayName ?? "none")")
        .onDisappear { stop() }
        .onChange(of: recording) { _, now in if !now { stop() } }
    }

    private func start() {
        recording = true
        held = []
        model.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = FlagBits.modifiers(UInt64(event.modifierFlags.rawValue))
            if event.type == .flagsChanged { held = modifiers; return nil }
            if event.keyCode == KeyCombo.Code.escape && modifiers.isEmpty { stop(); return nil }
            if event.keyCode == 51 && modifiers.isEmpty { keys = nil; stop(); return nil }
            let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers, character: event.charactersIgnoringModifiers)
            if combo.isUsableAsTrigger || allowPlain {
                keys = combo
                if keepsRecording { held = [] } else { stop() }
            } else {
                onRefused("“\(combo.keyName)” on its own would take over typing. Hold ⌘, ⌃ or ⌥ with it, or use an F-key.")
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.isRecording = false; recording = false }
        held = []
    }
}

/// Lays its children out in rows, wrapping, for app chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// The apps as chips with a remove button, then a menu to add one.
struct AppChips: View {
    @Binding var apps: [AppRef]
    let suggestions: [AppRef]
    var suggestionsTitle = "Suggested"
    /// Runs the app chooser with the dropdown out of its way.
    var stepAway: (() -> Void) -> Void = { $0() }

    var body: some View {
        FlowLayout {
            ForEach(apps) { app in
                HStack(spacing: 4) {
                    if let icon = AppIcons.icon(bundleID: app.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(AppIcons.name(app)).lineLimit(1)
                    Button { apps.removeAll { $0.id == app.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(AppIcons.name(app))")
                }
                .padding(.leading, 8).padding(.trailing, 4)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            Menu {
                let available = suggestions.filter { !apps.contains($0) }
                if !available.isEmpty {
                    Section(suggestionsTitle) { ForEach(available) { app in Button(AppIcons.name(app)) { apps.append(app) } } }
                }
                Divider()
                Button("Choose an app…") {
                    stepAway { AppChooser.choose { app in if !apps.contains(app) { apps.append(app) } } }
                }
            } label: {
                Label("Add App", systemImage: "plus")
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
            .foregroundStyle(Color.accentColor)
            .fixedSize()
            .frame(height: 28)
        }
    }
}

/// Only-if and unless conditions, any number, combined by all or any. With none, one row says what
/// that means (`empty`, "Always") with Add Condition at its end.
struct ConditionRows: View {
    @Binding var conditions: ConditionSet
    /// The empty row's label, when the rows share a card with other rows ("When").
    var label: String? = nil
    var empty: String
    /// A hairline over the first row, for rows under others in the same card.
    var dividedFromAbove = false

    var body: some View {
        if conditions.conditions.isEmpty {
            FormRow(label: label, divider: dividedFromAbove) {
                Text(empty).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 6)
                addMenu
            }
        } else {
            // Each condition reads on its own ("Only if…", "Unless…") and needs the card's width.
            ForEach(Array(conditions.conditions.enumerated()), id: \.element.id) { index, condition in
                FormRow(divider: index > 0 || dividedFromAbove) { row(index: index, condition: condition) }
            }
            FormRow(divider: true) {
                addMenu
                Spacer()
                if conditions.conditions.count > 1 {
                    Text("Match").font(.caption).foregroundStyle(.secondary)
                    Picker("Match", selection: $conditions.match) {
                        Text("All").tag(ConditionMatch.all)
                        Text("Any").tag(ConditionMatch.any)
                    }
                    .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(Array(Condition.Kind.templates.enumerated()), id: \.offset) { _, kind in
                Button { conditions.conditions.append(Condition(kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
            }
        } label: {
            Label("Add Condition", systemImage: "plus")
        }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
    }

    private func row(index: Int, condition: Condition) -> some View {
        let binding = Binding<Condition>(
            get: { conditions.conditions.indices.contains(index) ? conditions.conditions[index] : condition },
            set: { if conditions.conditions.indices.contains(index) { conditions.conditions[index] = $0 } })
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: binding.negated) {
                    Text("Only if").tag(false)
                    Text("Unless").tag(true)
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                Text(condition.kind.title.lowercased()).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Button { conditions.conditions.removeAll { $0.id == condition.id } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this condition")
            }
            parameter(binding)
        }
    }

    @ViewBuilder private func parameter(_ condition: Binding<Condition>) -> some View {
        switch condition.wrappedValue.kind {
        case let .windowTitleContains(text):
            TextField("Text", text: Binding(get: { text }, set: { condition.wrappedValue.kind = .windowTitleContains($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        case let .timeBetween(start, end):
            HStack(spacing: 4) {
                timePicker(start) { condition.wrappedValue.kind = .timeBetween(start: $0, end: end) }
                Text("to").foregroundStyle(.secondary)
                timePicker(end) { condition.wrappedValue.kind = .timeBetween(start: start, end: $0) }
            }
        default:
            EmptyView()
        }
    }

    private func timePicker(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        TimeChoice(minutes: minutes, set: set)
    }
}
#endif
