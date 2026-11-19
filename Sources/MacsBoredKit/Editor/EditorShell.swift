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

/// Choices laid out in place as pills that wrap, the chosen one filled with the accent: what the page
/// offers instead of a menu.
struct ChoiceChips<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    var symbol: (Value) -> String? = { _ in nil }
    var icon: (Value) -> NSImage? = { _ in nil }
    var isChosen: (Value) -> Bool = { _ in false }
    /// One more pill after the choices, laid out with them (a + New that becomes a field).
    var last: AnyView? = nil
    /// Deletes a choice itself (a pack), from its chip's right-click menu: the item's title and what
    /// it does; nil for a choice that can't be.
    var delete: ((Value) -> (title: String, action: () -> Void)?)? = nil
    let choose: (Value) -> Void
    @State private var hovered: Value?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(values, id: \.self) { value in
                let chosen = isChosen(value)
                Button { choose(value) } label: {
                    HStack(spacing: 5) {
                        if let image = icon(value) {
                            Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
                        } else if let name = symbol(value) {
                            Image(systemName: name).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(chosen ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.accentColor))
                        }
                        Text(title(value)).lineLimit(1)
                    }
                    .font(.callout.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Color.white : Color.primary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(chosen ? Color.accentColor : Color.primary.opacity(hovered == value ? 0.11 : 0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? value : (hovered == value ? nil : hovered) }
                .contextMenu {
                    if let item = delete?(value) {
                        Button(item.title, systemImage: "trash", role: .destructive, action: item.action)
                    }
                }
                .accessibilityLabel(title(value))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            if let last { last }
        }
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

/// A time of day, typed or stepped with the arrow keys in the Mac's own time field (12- or 24-hour,
/// as the Mac is set): no menu.
struct TimeChoice: View {
    /// Minutes since midnight.
    let minutes: Int
    let set: (Int) -> Void

    var body: some View {
        DatePicker("Time", selection: Binding(get: { Self.date(minutes) }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }), displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .fixedSize()
    }

    private static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
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
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One row of the editor's lists, drawn as the Actions list draws its rows (a card each): its icon,
/// what it is, its value and a bin. Click it and it opens in place, its controls under it on the same
/// card, as the list's rows open; click it again to close it. The bin asks first, as the list's does:
/// clicked once it grows into a red pill asking "bin?", a second click removes the row, and leaving
/// the row shrinks it back.
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
    @State private var asking = false

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
                if let remove { Button {
                    if asking { asking = false; remove() }
                    else { withAnimation(.bouncy(duration: 0.3, extraBounce: 0.15)) { asking = true } }
                } label: {
                    HStack(spacing: 1) {
                        Image(systemName: "trash")
                        if asking {
                            Text("?").transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(asking ? AnyShapeStyle(Color.white) : hotBin ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .frame(width: asking ? 44 : 26, height: asking ? 22 : 24)
                    .background {
                        RoundedRectangle(cornerRadius: asking ? 11 : 6, style: .continuous)
                            .fill(Color.red.opacity(asking ? 1 : hotBin ? 0.13 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hotBin = $0 }
                .help(asking ? "Click again to remove" : removeHelp)
                .accessibilityLabel(asking ? "Confirm \(removeHelp.lowercased()): \(title)" : "\(removeHelp): \(title)") }
            }
            .padding(.horizontal, 10)
            .frame(height: CardStyle.rowHeight)
            .background(Color.primary.opacity(hovering || isOpen ? 0.04 : 0))
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .onHover { inside in
                hovering = inside
                if !inside && asking { withAnimation(.bouncy(duration: 0.3, extraBounce: 0.15)) { asking = false } }
            }
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

/// An empty list, as the dropdown's lists say it: a line of text on a row card.
struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RowCard(lifted: false))
    }
}

/// One of the kinds + Add offers: what it's called, its symbol, and what choosing it does.
struct AddChoice {
    let title: String
    let symbol: String
    let action: () -> Void
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
        if let tap = tappedModifier { return [tap.symbol] }
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
    /// Take a modifier tapped on its own (pressed and let go, no key between) as keys, while this says so.
    var tapAllowed: () -> Bool = { false }
    var onRefused: (String) -> Void = { _ in }
    /// Drawn large, as New Shortcut's keys are, showing these keys (and clearing them with its x).
    var large: [KeyCombo]? = nil
    var onClear: () -> Void = {}
    let model: MacsBoredModel
    @State private var held: KeyCombo.Modifiers = []
    @State private var monitor: Any?
    /// A modifier pressed on its own, and when: a tap if it's let go soon, with no key between.
    @State private var tapping: (key: ModifierKey, at: TimeInterval)?

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
            if event.type == .flagsChanged {
                if let key = ModifierKey(modifiers), held.isEmpty {
                    tapping = (key, event.timestamp)
                } else if modifiers.isEmpty, let tap = tapping, event.timestamp - tap.at <= KeyRouter.doubleTapGap,
                          tapAllowed() {
                    keys = .tap(tap.key)
                    tapping = nil
                    if !keepsRecording { stop() }
                } else {
                    tapping = nil
                }
                held = modifiers
                return nil
            }
            tapping = nil
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

    /// As wide as offered; offered no width, or any (a stack asking how far it could grow), as wide
    /// as its longest line, so it never reports an endless width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = offered ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: offered ?? widest, height: y + line)
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

/// The apps as chips with a remove button; under them, apps to add with a click, and a way to choose
/// any other.
struct AppChips: View {
    @Binding var apps: [AppRef]
    let suggestions: [AppRef]
    var suggestionsTitle = "Suggested"
    /// Runs the app chooser with the dropdown out of its way.
    var stepAway: (() -> Void) -> Void = { $0() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !apps.isEmpty {
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
                }
            }
            AppSuggestions(title: suggestionsTitle, apps: suggestions.filter { !apps.contains($0) },
                           stepAway: stepAway) { app in if !apps.contains(app) { apps.append(app) } }
        }
    }
}

/// Apps to pick with a click, a few at most, then Choose an App… for any other.
struct AppSuggestions: View {
    let title: String
    let apps: [AppRef]
    var chosen: AppRef? = nil
    var stepAway: (() -> Void) -> Void = { $0() }
    let pick: (AppRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !apps.isEmpty {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ChoiceChips(values: Array(apps.prefix(8)), title: AppIcons.name,
                            icon: { AppIcons.icon(bundleID: $0.bundleID) }, isChosen: { $0 == chosen }, choose: pick)
            }
            Button("Choose an App…") { stepAway { AppChooser.choose(pick) } }
                .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
        }
    }
}

/// Only-if and unless conditions, any number, combined by all or any. With none, one row says what
/// that means (`empty`, "Always") with Add Condition at its end.
struct ConditionRows: View {
    @Binding var conditions: ConditionSet
    /// Add Condition's choices are showing, in a row under it.
    @State private var choosing = false
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
                addButton
            }
            if choosing { choices }
        } else {
            // Each condition reads on its own ("Only if…", "Unless…") and needs the card's width.
            ForEach(Array(conditions.conditions.enumerated()), id: \.element.id) { index, condition in
                FormRow(divider: index > 0 || dividedFromAbove) { row(index: index, condition: condition) }
            }
            FormRow(divider: true) {
                addButton
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
            if choosing { choices }
        }
    }

    /// Opens the kinds of condition in a row under it; again closes them.
    private var addButton: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { choosing.toggle() } } label: {
            Label(choosing ? "Close" : "Add Condition", systemImage: choosing ? "xmark" : "plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
    }

    /// The kinds of condition, in place: one click adds it.
    private var choices: some View {
        FormRow(divider: true) {
            ChoiceChips(values: Array(Condition.Kind.templates.indices), title: { Condition.Kind.templates[$0].title },
                        symbol: { Condition.Kind.templates[$0].symbol }) { index in
                withAnimation(.easeOut(duration: 0.15)) {
                    conditions.conditions.append(Condition(Condition.Kind.templates[index]))
                    choosing = false
                }
            }
        }
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
            ConditionControls.parameter(binding)
        }
    }
}

/// A condition's settings, in its open row: whether it must be true or must not, and what it checks
/// for (a window title's text, a span of time).
struct ConditionControls: View {
    @Binding var condition: Condition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $condition.negated) {
                Text("Only if").tag(false)
                Text("Unless").tag(true)
            }
            .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
            Self.parameter($condition)
        }
    }

    @ViewBuilder static func parameter(_ condition: Binding<Condition>) -> some View {
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

    private static func timePicker(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        TimeChoice(minutes: minutes, set: set)
    }
}
#endif
