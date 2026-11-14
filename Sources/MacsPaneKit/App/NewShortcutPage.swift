#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsPaneCore
import MacsShared

/// "New shortcut", a page of the dropdown opened by the + beside Shortcuts: press the keys, pick a
/// layout or a preset from the strip, click the box the window should go to on the big screen under
/// it, and add it. The keys are waited for as soon as the page opens; while they are, MacsPane's own
/// shortcuts don't run, so keys already in use can be pressed and moved here.
final class NewShortcutModel: ObservableObject {
    /// What the big screen shows: a layout, whose boxes are clicked, or a preset.
    enum Shown: Hashable {
        case layout(String)
        case preset(String)
    }

    /// The page's name in the dropdown.
    static let page = "macspane-new-shortcut"

    let app: MacsPaneModel
    @Published private(set) var keys: KeyShortcut?
    @Published private(set) var recording = false
    @Published private(set) var hint: String?
    @Published private(set) var shown: Shown?
    @Published var target: ShortcutAction?

    init(app: MacsPaneModel) {
        self.app = app
        if let layout = app.config.windows.layoutCatalog.first {
            shown = .layout(layout.id)
        } else if let preset = app.config.presets.first {
            show(.preset(preset.id))
        }
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

    /// Show a layout or a preset on the big screen. A preset is picked as it is shown; a layout's box
    /// is picked by clicking it, unless the layout has only the one.
    func show(_ item: Shown) {
        shown = item
        switch item {
        case .preset(let id):
            target = .preset(id: id)
        case .layout(let id):
            if case let .layoutBox(layoutID, _)? = target, layoutID == id { return }
            let boxes = app.config.windows.layoutCatalog.first { $0.id == id }?.boxes.count ?? 0
            target = boxes == 1 ? .layoutBox(layoutID: id, box: 0) : nil
        }
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

    /// What the shortcut will do, in a line under the big screen.
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

struct NewShortcutView: View {
    @ObservedObject var model: NewShortcutModel
    @Environment(\.closePage) private var closePage

    private static let screen = CGSize(width: 340, height: 196)

    var body: some View {
        let config = model.app.config
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection("Keys", footer: keysNote) {
                KeysField(model: model)
            }
            if config.windows.layoutCatalog.isEmpty && config.presets.isEmpty {
                Text("No layouts or presets yet.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                PickerStrip(model: model)
                bigScreen(config)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                Text(model.summary + (model.replacing.map { " Replaces \($0.displayName)." } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
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

    @ViewBuilder
    private func bigScreen(_ config: MacsPaneConfig) -> some View {
        switch model.shown {
        case .layout(let id)?:
            if let layout = config.windows.layoutCatalog.first(where: { $0.id == id }) {
                LayoutBoxPicker(layout: layout, target: $model.target, size: Self.screen)
            }
        case .preset(let id)?:
            if let preset = config.presets.first(where: { $0.id == id }) {
                presetGlyph(preset, size: Self.screen)
                    .accessibilityElement()
                    .accessibilityLabel(preset.name)
            }
        case nil:
            EmptyView()
        }
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

/// Every layout, then every preset, small, each kind on a row of its own under a heading: the rows
/// keep one height and scroll sideways when they hold more than fits. The one on the big screen is
/// ringed.
private struct PickerStrip: View {
    @ObservedObject var model: NewShortcutModel

    private static let thumb = CGSize(width: 50, height: 32)
    /// A row's height: a thumbnail, its ring and its name.
    private static let rowHeight: CGFloat = 56

    var body: some View {
        let config = model.app.config
        VStack(alignment: .leading, spacing: 6) {
            heading("Layouts")
            SidewaysRow(height: Self.rowHeight) {
                HStack(spacing: 6) {
                    ForEach(config.windows.layoutCatalog) { layout in
                        item(.layout(layout.id), name: layout.name,
                             glyph: MacsPaneLayoutGlyph(boxes: layout.boxes, size: Self.thumb))
                    }
                }
                .padding(.horizontal, 2)
            }
            heading("Presets")
            if config.presets.isEmpty {
                Text("None yet.").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 4)
                    .frame(height: Self.rowHeight, alignment: .leading)
            } else {
                SidewaysRow(height: Self.rowHeight) {
                    HStack(spacing: 6) {
                        ForEach(config.presets, id: \.id) { preset in
                            item(.preset(preset.id), name: preset.name, glyph: presetGlyph(preset, size: Self.thumb))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func item(_ item: NewShortcutModel.Shown, name: String, glyph: MacsPaneLayoutGlyph) -> some View {
        let on = model.shown == item
        return Button { model.show(item) } label: {
            VStack(spacing: 3) {
                glyph
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                Text(name).font(.system(size: 9)).lineLimit(1).frame(width: 58)
                    .foregroundStyle(on ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A row of fixed height that scrolls sideways when its content is wider than it: by a trackpad's
/// sideways swipe, or by a mouse's wheel, which would otherwise scroll the page (a trackpad's up-and-down
/// swipe still does). A thin scroll bar lies over its bottom edge then (its thumb shows how much is in
/// view, and drags); as macOS's overlay bars do, it shows while the row is scrolled, pointed at or
/// dragged, and when the page opens, then fades. A row that fits never shows it. All SwiftUI, so it
/// scales with the menu's Size.
private struct SidewaysRow<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: Content
    @StateObject private var scroller = SidewaysScroller()
    @State private var hovering = false
    @State private var wheel: Any?

    var body: some View {
        GeometryReader { outer in
            content
                .fixedSize()
                .background(GeometryReader { inner in
                    Color.clear.onChange(of: inner.size.width, initial: true) { _, width in scroller.setTotal(width) }
                })
                .offset(x: -scroller.offset)
                .frame(width: outer.size.width, height: height, alignment: .leading)
                .onChange(of: outer.size.width, initial: true) { _, width in scroller.setVisible(width) }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            SidewaysScrollBar(scroller: scroller)
                .frame(height: 7)
                .padding(.bottom, 1)
                .opacity(scroller.overflows && (scroller.isActive || hovering) ? 1 : 0)
                .allowsHitTesting(scroller.overflows && (scroller.isActive || hovering))
                .animation(.easeOut(duration: 0.25), value: scroller.isActive || hovering)
                .accessibilityHidden(true)
        }
        .onHover { inside in
            hovering = inside
            inside ? listen() : stopListening()
        }
        .onDisappear(perform: stopListening)
    }

    /// While the pointer is on the row, its wheel and swipes scroll the row.
    private func listen() {
        guard wheel == nil else { return }
        wheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [scroller] event in
            scroller.wheel(event) ? nil : event
        }
    }

    private func stopListening() {
        if let wheel { NSEvent.removeMonitor(wheel) }
        wheel = nil
    }
}

/// How far a sideways row has scrolled, and scrolling it.
private final class SidewaysScroller: ObservableObject {
    @Published private(set) var visible: CGFloat = 0
    @Published private(set) var total: CGFloat = 0
    @Published private(set) var offset: CGFloat = 0
    /// Scrolled a moment ago, or being dragged: the bar shows.
    @Published private(set) var isActive = false
    private var fade: DispatchWorkItem?
    /// Whether the bar has flashed yet, to show the row scrolls.
    private var flashed = false
    var dragging = false {
        didSet { dragging ? wake() : rest() }
    }

    var overflows: Bool { total > visible + 0.5 }
    private var range: CGFloat { max(0, total - visible) }

    func setVisible(_ width: CGFloat) { visible = width; settle() }
    func setTotal(_ width: CGFloat) { total = width; settle() }

    /// Keep the offset in range, and flash the bar the first time the row is found to overflow.
    private func settle() {
        if offset > range { offset = range }
        if overflows, visible > 0, !flashed {
            flashed = true
            wake()
            rest(after: 1.5)
        }
    }

    func scroll(to x: CGFloat) {
        let x = min(max(0, x), range)
        guard x != offset else { return }
        offset = x
        wake()
        rest()
    }

    /// A wheel or swipe over the row: true when it scrolled the row. A mouse's wheel turns sideways, a
    /// line a notch; a trackpad's up-and-down swipe is left for the page.
    func wheel(_ event: NSEvent) -> Bool {
        guard overflows else { return false }
        let upAndDown = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        if upAndDown && event.hasPreciseScrollingDeltas { return false }
        let delta = upAndDown ? event.scrollingDeltaY * 10 : event.scrollingDeltaX
        scroll(to: offset - delta)
        return true
    }

    private func wake() {
        fade?.cancel()
        if !isActive { isActive = true }
    }

    /// Fade the bar out a moment after the last scroll, unless it is being dragged.
    private func rest(after delay: TimeInterval = 1) {
        guard !dragging else { return }
        fade?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isActive = false }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// A thumb as wide as the share of the row in view, where the view is, as an overlay scroll bar draws
/// one: on its own, and over a faint track while the pointer is on the bar. Dragging the thumb scrolls
/// the row.
private struct SidewaysScrollBar: View {
    @ObservedObject var scroller: SidewaysScroller
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let share = scroller.total > 0 ? min(1, scroller.visible / scroller.total) : 1
            let thumb = max(28, width * share)
            let range = max(0, scroller.total - scroller.visible)
            let x = range > 0 ? (width - thumb) * scroller.offset / range : 0
            let wide = hovering || dragStart != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(wide ? 0.08 : 0))
                Capsule().fill(Color.primary.opacity(wide ? 0.5 : 0.35))
                    .frame(width: thumb, height: wide ? 7 : 5)
                    .offset(x: x)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                        let start = dragStart ?? scroller.offset
                        if dragStart == nil { dragStart = start; scroller.dragging = true }
                        guard width > thumb else { return }
                        scroller.scroll(to: start + drag.translation.width * range / (width - thumb))
                    }.onEnded { _ in dragStart = nil; scroller.dragging = false })
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: wide)
        }
        .padding(.horizontal, 2)
    }
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


/// A layout drawn as a big screen, its boxes numbered and clicked to pick one: the box picked is
/// filled, and the one under the pointer lights.
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
        MacsPaneLayoutGlyph(boxes: layout.boxes, size: size, highlighted: hovered ?? picked)
            .overlay(alignment: .topLeading) { boxes }
    }

    /// A numbered button over each box, back ones first, so the front window's box wins where they
    /// overlap.
    private var boxes: some View {
        let layers = layout.layers
        let order = layout.boxes.indices.sorted { (layers[$0], -$0) > (layers[$1], -$1) }
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { index in
                let unit = layout.boxes[index].unitRect
                let rect = CGRect(x: unit.minX * size.width, y: (1 - unit.maxY) * size.height,
                                  width: unit.width * size.width, height: unit.height * size.height)
                let lit = (hovered ?? picked) == index
                Text("\(index + 1)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(lit ? Color.white : Color.accentColor)
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .offset(x: rect.minX, y: rect.minY)
                    .onTapGesture { target = .layoutBox(layoutID: layout.id, box: index) }
                    .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                    .accessibilityElement()
                    .accessibilityLabel("\(layout.name), box \(index + 1)")
                    .accessibilityAddTraits(picked == index ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { target = .layoutBox(layoutID: layout.id, box: index) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
#endif
