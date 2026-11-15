#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsPaneCore
import MacsShared

/// "New shortcut", a page of the dropdown opened by Add beside Shortcuts: press the keys, then click
/// the box the window goes to on one of the layouts, or click a preset, and add it. The keys are waited for as soon as the page opens; while they are, MacsPane's own
/// shortcuts don't run, so keys already in use can be pressed and moved here.
final class NewShortcutModel: ObservableObject {
    /// The page's name in the dropdown.
    static let page = "macspane-new-shortcut"

    let app: MacsPaneModel
    @Published private(set) var keys: KeyShortcut?
    @Published private(set) var recording = false
    @Published private(set) var hint: String?
    /// What the keys will do: a layout's box (clicked on its tile) or a preset.
    @Published var target: ShortcutAction?

    init(app: MacsPaneModel) {
        self.app = app
    }


    deinit { if recording { app.setShortcutsSuspended(false) } }

    // MARK: - Keys

    func startRecording() {
        guard !recording else { return }
        recording = true
        hint = nil
        app.setShortcutsSuspended(true)
    }

    func stopRecording() {
        guard recording else { return }
        recording = false
        hint = nil
        app.setShortcutsSuspended(false)
    }

    /// While recording, the next combo is the shortcut: esc stops waiting, ⌫ clears the keys, and keys
    /// without ⌘, ⌃ or ⌥ ask for one. False lets the dropdown have the key (esc goes back).
    func keyDown(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        let pressed = KeyShortcut(event: event)
        switch (pressed.keyCode, pressed.modifiers.isEmpty) {
        case (53, true):
            stopRecording()
        case (51, true), (117, true):
            keys = nil
            hint = nil
        default:
            guard pressed.isUsable else { hint = "Hold ⌘, ⌃ or ⌥ too"; return true }
            keys = pressed
            stopRecording()
        }
        return true
    }

    func clearKeys() {
        keys = nil
        startRecording()
    }

    // MARK: - What it does

    /// A preset from the list: the keys will apply it.
    func pickPreset(_ id: String) {
        target = .preset(id: id)
    }

    /// What the keys do now, elsewhere: adding moves them here.
    var takenFrom: String? {
        guard let keys, let owner = app.shortcutOwner(keys), owner.action != target else { return nil }
        return owner.name
    }

    /// The keys the picked box or preset has now: adding replaces them.
    var replacing: KeyShortcut? {
        guard let target else { return nil }
        return app.config.shortcuts.first { $0.action == target && $0.shortcut != keys }?.shortcut
    }

    /// What the shortcut will do, in a line above Add Shortcut.
    var summary: String {
        let config = app.config
        switch target {
        case let .layoutBox(id, box)?:
            let name = config.windows.layoutCatalog.first { $0.id == id }?.name ?? "the layout"
            return "Sends the window you're in to \(name), box \(box + 1)."
        case .preset(let id)?:
            return "Applies \(config.presets.first { $0.id == id }?.name ?? "the preset")."
        case nil:
            return "Click the box to send the window you're in to."
        }
    }

    var canAdd: Bool { keys != nil && target != nil }

    func add() {
        guard let keys, let target else { return }
        stopRecording()
        app.setShortcut(keys, for: target)
    }
}

extension MacsPaneModel {
    /// The dropdown's "New shortcut" page.
    func newShortcutPage() -> TabbedMenuSubpage {
        let page = NewShortcutModel(app: self)
        return TabbedMenuSubpage(title: "New Shortcut", content: AnyView(NewShortcutView(model: page)),
                                 changes: page.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                 keyDown: { [weak page] in page?.keyDown($0) ?? false })
    }
}

// MARK: - The page

/// The page: the keys, then what they do, every choice in view. Sending the window to a box: every
/// layout as a small screen with its boxes numbered, and the box clicked on it. Applying a preset:
/// every preset as a small screen with its apps, clicked to pick it. Then Add Shortcut.
struct NewShortcutView: View {
    @ObservedObject var model: NewShortcutModel
    @Environment(\.closePage) private var closePage
    /// Presets chosen with the switch, before any is picked.
    @State private var presetsChosen = false

    /// A layout's or preset's tile: three to a row across the page.
    private static let tile = CGSize(width: 100, height: 62)
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let config = model.app.config
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                title("Keys")
                SettingsSection(footer: keysNote) {
                    KeysField(model: model)
                }
            }
            if config.windows.layoutCatalog.isEmpty && config.presets.isEmpty {
                Text("No layouts or presets yet.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        title("What they do")
                        Spacer(minLength: 6)
                        Picker("What they do", selection: Binding(get: { showsPresets }, set: choosePresets)) {
                            Text("Send to a box").tag(false)
                            Text("Apply a preset").tag(true)
                        }
                        .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                    }
                    if showsPresets { presetTiles(config) } else { layoutTiles(config) }
                }
            }
            Text(model.target == nil
                 ? (showsPresets ? "Click a preset." : "Click the box the window goes to.")
                 : model.summary + (model.replacing.map { " Replaces \($0.displayName)." } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Cancel") { leave() }
                Button("Add Shortcut") {
                    model.add()
                    leave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAdd)
            }
        }
        .padding(12)
        .onAppear { if model.keys == nil { model.startRecording() } }
        .onDisappear { model.stopRecording() }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Choosing

    /// Whether the presets show: one is picked, the switch was set to them, or there are no layouts.
    private var showsPresets: Bool {
        if case .preset? = model.target { return true }
        return presetsChosen || model.app.config.windows.layoutCatalog.isEmpty
    }

    /// The switch: what was picked on the other side is let go.
    private func choosePresets(_ presets: Bool) {
        presetsChosen = presets
        model.target = nil
    }

    /// Every layout as a small screen, its boxes numbered: clicking a box picks it.
    private func layoutTiles(_ config: MacsPaneConfig) -> some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(config.windows.layoutCatalog) { layout in
                let picked: Bool = {
                    if case let .layoutBox(id, _)? = model.target { return id == layout.id }
                    return false
                }()
                VStack(spacing: 4) {
                    LayoutBoxPicker(layout: layout, target: $model.target, size: Self.tile)
                    name(layout.name, picked: picked)
                }
            }
        }
    }

    /// Every preset as a small screen with its apps: clicking one picks it.
    @ViewBuilder
    private func presetTiles(_ config: MacsPaneConfig) -> some View {
        if config.presets.isEmpty {
            Text("No presets yet. Save one with Add beside Presets on MacsPane's page.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(config.presets, id: \.id) { preset in
                    let picked = model.target == .preset(id: preset.id)
                    Button { model.pickPreset(preset.id) } label: {
                        VStack(spacing: 4) {
                            presetGlyph(preset, size: Self.tile)
                                .overlay(RoundedRectangle(cornerRadius: Self.tile.height * 0.14 + 3, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: picked ? 2.5 : 0)
                                    .padding(-3))
                            name(preset.name, picked: picked)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }

    private func name(_ text: String, picked: Bool) -> some View {
        Text(text).font(.caption.weight(picked ? .semibold : .regular))
            .foregroundStyle(picked ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
    }

    private func leave() {
        model.stopRecording()
        closePage?()
    }

    private var keysNote: String? {
        if let hint = model.hint { return hint }
        if let from = model.takenFrom { return "Now on \(from): adding moves it here." }
        return nil
    }
}

/// A preset's boxes, each with its app's icon.
private func presetGlyph(_ preset: SnapLayout, size: CGSize) -> MacsPaneLayoutGlyph {
    let slots = preset.slots.filter { !$0.isRemoved }
    return MacsPaneLayoutGlyph(boxes: slots.map(\.region), size: size, icons: slots.map { slot in
        guard case let .app(bundleID) = slot.binding else { return nil }
        return SnapAppIcons.icon(bundleID: bundleID)
    }, largestIcon: 56)
}

/// The keys of the shortcut being made, as keycaps, or, while they are waited for, a dashed prompt.
/// A click starts waiting again; the x clears them.
private struct KeysField: View {
    @ObservedObject var model: NewShortcutModel

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let keys = model.keys, !model.recording {
                HStack(spacing: 4) {
                    ForEach(Array(Self.caps(keys).enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .frame(minWidth: 26, minHeight: 26)
                            .padding(.horizontal, cap.count > 1 ? 6 : 0)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.18), radius: 0, y: 1))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12)))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(keys.displayName)
            } else {
                Label(model.keys.map { "\($0.displayName) — press new keys" } ?? "Press the keys",
                      systemImage: "keyboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 50)
        .overlay {
            if model.recording {
                RoundedRectangle(cornerRadius: CardStyle.corner - 2, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(4)
            }
        }
        .overlay(alignment: .trailing) {
            if model.keys != nil, !model.recording {
                Button { model.clearKeys() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the keys")
                .padding(.trailing, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.startRecording() }
        .help(model.recording ? "Press the keys, holding ⌘, ⌃ or ⌥; esc stops waiting" : "Click to press other keys")
    }

    /// "⌃⌥←" as its keys one by one: each modifier, then the key.
    static func caps(_ keys: KeyShortcut) -> [String] {
        var caps: [String] = []
        if keys.modifiers.contains(.control) { caps.append("⌃") }
        if keys.modifiers.contains(.option) { caps.append("⌥") }
        if keys.modifiers.contains(.shift) { caps.append("⇧") }
        if keys.modifiers.contains(.command) { caps.append("⌘") }
        caps.append(keys.keyName)
        return caps
    }
}


/// A layout drawn as a small screen with its boxes numbered: clicking one picks it. Which box the
/// pointer is on comes from the layout itself (the one in front, where boxes overlap), so the box
/// that lights and the box that's picked are always the one drawn there. The box picked is filled
/// and stays so; the one under the pointer takes a light tint, without hiding it.
private struct LayoutBoxPicker: View {
    let layout: WindowLayout
    @Binding var target: ShortcutAction?
    let size: CGSize
    @State private var hovered: Int?

    private var picked: Int? {
        guard case let .layoutBox(id, box) = target, id == layout.id else { return nil }
        return box
    }

    var body: some View {
        MacsPaneLayoutGlyph(boxes: layout.boxes, size: size, highlighted: picked)
            .overlay { numbers.allowsHitTesting(false) }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): hovered = box(at: point)
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { tap in
                if let box = box(at: tap.location) { pick(box) }
            })
            .help(hovered.map { "\(layout.name), box \($0 + 1)" } ?? layout.name)
    }

    /// The box under a point in the picture.
    private func box(at point: CGPoint) -> Int? {
        layout.boxIndex(atTopLeftUnit: CGPoint(x: point.x / size.width, y: point.y / size.height))
    }

    private func pick(_ box: Int) {
        target = .layoutBox(layoutID: layout.id, box: box)
    }

    /// Each box's number, and the tint on the one under the pointer. VoiceOver picks a box by its
    /// number.
    private var numbers: some View {
        ZStack {
            ForEach(layout.boxes.indices, id: \.self) { index in
                let rect = rect(of: index)
                let isPicked = picked == index
                Text("\(index + 1)")
                    .font(.system(size: min(20, max(11, size.height * 0.2)), weight: .semibold, design: .rounded))
                    .foregroundStyle(isPicked ? Color.white : Color.accentColor)
                    .frame(width: rect.width, height: rect.height)
                    .background(Color.accentColor.opacity(hovered == index && !isPicked ? 0.18 : 0))
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel("\(layout.name), box \(index + 1)")
                    .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { pick(index) }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size.height * 0.14), style: .continuous))
    }

    /// Where box `index` is drawn, in points from the picture's top left.
    private func rect(of index: Int) -> CGRect {
        let unit = layout.boxes[index].unitRect
        return CGRect(x: unit.minX * size.width, y: (1 - unit.maxY) * size.height,
                      width: unit.width * size.width, height: unit.height * size.height)
    }
}
#endif
