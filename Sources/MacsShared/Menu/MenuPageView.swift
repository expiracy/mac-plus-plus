#if canImport(AppKit)
import AppKit
import SwiftUI

/// A tool's page of the dropdown, drawn the same for every tool: the tool's mark, name and main
/// switch; then rounded cards, each under a small title: what is happening now with its one button,
/// any warning with its fix, the general switches, and the titled lists. Rows lead with a tinted icon
/// tile, an app's icon or a drawing of the tool's own. A long list scrolls inside its card, and a list
/// that can be reordered has a grip on every row: drag it and the other rows slide aside. The
/// dropdown around it adds the switcher, the bubble and the footer shared by every page.
public struct MenuPageView: View {
    @ObservedObject var model: MenuPageModel
    @Environment(\.openHelp) private var openHelp
    @State private var hoveredRow: String?
    @State private var hoveredTrash: String?
    @State private var drag: RowDrag?

    public init(model: MenuPageModel) {
        self.model = model
    }

    /// The row being dragged by its grip: which list, where it started, and how far the pointer has gone.
    private struct RowDrag: Equatable {
        let group: String
        let from: Int
        var height: CGFloat
    }

    enum Metric {
        static let edge: CGFloat = 12
        static let row: CGFloat = 38
        static let corner: CGFloat = CardStyle.corner
        static let tile: CGFloat = 24
        /// A list taller than this many rows scrolls; the half row peeking out says there is more.
        static let visibleRows: CGFloat = 3.5
        /// Where a row's choices bubble puts its nub: over the row's icon, which sits 10 pt in from the
        /// row and the bubble 4 pt.
        static let submenuNubX: CGFloat = 10 + tile / 2 + 1 - 4
    }

    public var body: some View {
        let content = model.content
        VStack(alignment: .leading, spacing: 14) {
            header(content)
            if !content.live.isEmpty || model.brand.emptyLive != nil { liveCard(content.live) }
            ForEach(content.warnings) { warningCard($0) }
            if !content.toggles.isEmpty {
                TitledCard(model.brand.togglesTitle) { rows(content.toggles) }
            }
            ForEach(content.groups) { groupCard($0) }
        }
        .padding(Metric.edge)
        .overlayPreferenceValue(SubmenuAnchorKey.self) { anchors in submenuLayer(anchors) }
    }

    // MARK: - A row's choices

    /// The open row's choices in a small bubble of the dropdown's own kind, its nub pointing up at the
    /// row's icon. A click anywhere else in the dropdown closes it.
    @ViewBuilder private func submenuLayer(_ anchors: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let id = model.openSubmenu, let anchor = anchors[id],
               let entry = model.content.groups.flatMap(\.actions).first(where: { $0.id == id }) {
                let row = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.openSubmenu = nil } }
                    submenuBubble(entry)
                        .offset(x: row.minX + 4, y: row.maxY - 6)
                        .transition(.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
                }
            }
        }
    }

    private func submenuBubble(_ entry: MenuEntry) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.submenu.enumerated()), id: \.element.id) { index, item in
                Button { model.run(item) } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: item.symbol ?? "circle", tint: .accentColor, size: Metric.tile)
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Metric.row - 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hoveredRow == item.id ? 0.06 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover(item, $0) }
                .overlay(alignment: .top) { if index > 0 { Divider().padding(.horizontal, 8) } }
            }
        }
        .padding(6)
        .padding(.top, SpeechBubbleShape.standardNub.height)
        .frame(width: 230)
        .background(SpeechBubbleShape(nubX: Metric.submenuNubX, corner: Metric.corner)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: Metric.submenuNubX, corner: Metric.corner)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.title)
    }

    // MARK: - Bands

    private func header(_ content: MenuPageContent) -> some View {
        PageHeader(logo: model.brand.logo(32), title: model.brand.name,
                   line: content.liveFact ?? content.primary?.title, help: openHelp) {
            if let primary = content.primary, case let .toggle(isOn, _, _) = primary.kind {
                switchControl(primary, isOn: isOn)
            }
        }
    }

    /// What is happening now: its icon (an app's own, when it is about an app), what and one fact,
    /// and the one button, drawn in the accent when it is the point of the line.
    private func liveCard(_ live: [MenuEntry]) -> some View {
        TitledCard(model.brand.liveTitle) {
            if live.isEmpty, let empty = model.brand.emptyLive {
                Text(empty).font(.callout).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(live) { entry in
                if case let .live(fact, actionTitle, accent) = entry.kind {
                    HStack(spacing: 10) {
                        if case let .appIcon(image) = entry.leading {
                            Image(nsImage: image).resizable().interpolation(.high).frame(width: 30, height: 30)
                        } else {
                            IconTile(symbol: entry.symbol ?? "clock", tint: accent ? .accentColor : .secondary, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.headline).lineLimit(1)
                            if !fact.isEmpty {
                                Text(fact).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        if let actionTitle {
                            Button(actionTitle) { model.run(entry) }
                                .buttonStyle(.borderedProminent)
                                .tint(accent ? .accentColor : .gray)
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture { model.open(entry) }
                }
            }
        }
    }

    /// A feature that can't run yet: the reason, and the one click that fixes it, on an orange card.
    private func warningCard(_ entry: MenuEntry) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "exclamationmark.triangle.fill", tint: .orange, size: Metric.tile)
            Text(entry.title).font(.callout.weight(.medium)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if case let .warning(actionTitle) = entry.kind, let actionTitle {
                Button(actionTitle) { model.run(entry) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    /// A titled list: its rows in a card (scrolling inside it once there are more than fit), or its
    /// empty line, then the commands that always show at the card's foot.
    private func groupCard(_ group: MenuGroup) -> some View {
        TitledCard(group.title) {
            if group.rows.isEmpty, let empty = group.empty {
                Text(empty)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if CGFloat(group.rows.count) > Metric.visibleRows {
                ScrollViewReader { proxy in
                    ScrollView { rows(group.rows, in: group) }
                        .frame(height: Metric.visibleRows * Metric.row)
                        // A row just added to be named is at the foot of the list: bring it into view.
                        .onChange(of: model.content.renaming, initial: true) { _, id in
                            guard let id, group.rows.contains(where: { $0.id == id }) else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                        }
                }
            } else {
                rows(group.rows, in: group)
            }
            if !group.actions.isEmpty {
                Divider()
                rows(group.actions)
            }
        }
    }

    // MARK: - Cards and rows

    /// Rows separated by hairlines across the card. In a list that can be reordered (`group.move`),
    /// each row leads with a grip; while one is dragged the lines step aside so nothing is left behind.
    private func rows(_ entries: [MenuEntry], in group: MenuGroup? = nil) -> some View {
        let movable = group?.move != nil && entries.count > 1 ? group : nil
        let dragging = movable != nil && drag?.group == movable?.id
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let lifted = dragging && drag?.from == index
                row(entry, grip: movable.map { grip(entry, index: index, count: entries.count, in: $0) })
                    .id(entry.id)
                    .overlay(alignment: .top) {
                        if index > 0 && !dragging { Divider() }
                    }
                    .background {
                        if lifted {
                            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(Color.accentColor.opacity(0.08))
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                        }
                    }
                    .offset(y: rowOffset(index, count: entries.count, dragging: dragging))
                    .animation(lifted ? nil : .easeOut(duration: 0.15),
                               value: rowOffset(index, count: entries.count, dragging: dragging))
                    .zIndex(lifted ? 1 : 0)
            }
        }
    }

    /// Where a dragged row would land: the pointer's travel in whole rows, kept inside the list.
    private func target(_ drag: RowDrag, count: Int) -> Int {
        min(max(drag.from + Int((drag.height / Metric.row).rounded()), 0), count - 1)
    }

    /// The dragged row follows the pointer; the rows between its start and where it would land slide
    /// one row the other way to make room.
    private func rowOffset(_ index: Int, count: Int, dragging: Bool) -> CGFloat {
        guard dragging, let drag else { return 0 }
        let to = target(drag, count: count)
        if index == drag.from {
            return min(max(drag.height, -CGFloat(drag.from) * Metric.row), CGFloat(count - 1 - drag.from) * Metric.row)
        }
        if drag.from < to, index > drag.from, index <= to { return -Metric.row }
        if to < drag.from, index >= to, index < drag.from { return Metric.row }
        return 0
    }

    /// The handle a row is dragged by: faint until its row is under the pointer. Move up and Move down
    /// do the same for VoiceOver.
    private func grip(_ entry: MenuEntry, index: Int, count: Int, in group: MenuGroup) -> some View {
        let active = hoveredRow == entry.id || drag?.group == group.id && drag?.from == index
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(active ? 0.9 : 0.35))
            .frame(width: 18, height: Metric.row)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if drag == nil { NSCursor.closedHand.push() }
                    drag = RowDrag(group: group.id, from: index, height: value.translation.height)
                }
                .onEnded { _ in
                    guard let current = drag else { return }
                    NSCursor.pop()
                    let to = target(current, count: count)
                    withAnimation(.easeOut(duration: 0.15)) {
                        drag = nil
                        if to != current.from { model.move(group, from: current.from, to: to) }
                    }
                })
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(entry.title)")
            .accessibilityAction(named: "Move up") {
                if index > 0 { model.move(group, from: index, to: index - 1) }
            }
            .accessibilityAction(named: "Move down") {
                if index < count - 1 { model.move(group, from: index, to: index + 1) }
            }
    }

    @ViewBuilder private func row(_ entry: MenuEntry, grip: (some View)? = Optional<EmptyView>.none) -> some View {
        switch entry.kind {
        case .section:
            Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case let .toggle(isOn, disabled, _):
            HStack(spacing: 10) {
                if let grip { grip.padding(.trailing, -4) }
                icon(entry, tint: .secondary)
                if renaming(entry) {
                    MenuNameField(model: model, title: entry.title)
                } else {
                    Text(entry.title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let trailing = entry.trailing {
                        Text(trailing).font(.callout.monospacedDigit())
                            .foregroundStyle(isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .accessibilityLabel(entry.trailingLabel.map { "\($0) \(trailing)" } ?? trailing)
                    }
                    if let secondary = entry.secondary {
                        secondaryButton(entry, secondary, hovered: hoveredRow == entry.id)
                    }
                    if entry.trash != nil { trashButton(entry).padding(.leading, -8) }
                }
                switchControl(entry, isOn: isOn)
            }
            .padding(.leading, grip == nil ? 10 : 4)
            .padding(.trailing, 10)
            .frame(height: Metric.row)
            .background(Color.primary.opacity(hoveredRow == entry.id ? 0.04 : 0))
            .onHover { hover(entry, $0) }
            .disabled(disabled)
        case let .choice(options, selected):
            HStack(spacing: 10) {
                icon(entry, tint: .secondary)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 4)
                Picker(entry.title, selection: Binding(get: { selected }, set: { model.pick(entry, index: $0) })) {
                    ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row)
        case let .command(danger):
            commandRow(entry, danger: danger, grip: grip)
        case .live, .warning:
            EmptyView()
        }
    }

    /// A row you click: the whole line is the target and lights under the pointer. A command that adds
    /// something ("New preset…", a plus or a symbol badged with one) is drawn in the accent, like the app's other primary actions. A
    /// second button (Edit) sits at the end.
    /// The row just added and being named shows its name field in place of the title and buttons.
    private func commandRow(_ entry: MenuEntry, danger: Bool, grip: (some View)?) -> some View {
        let hovered = hoveredRow == entry.id
        let adds = (entry.symbol == "plus" || entry.symbol?.hasSuffix(".badge.plus") == true) && entry.leadsWithSymbol
        if renaming(entry) {
            return AnyView(HStack(spacing: 10) {
                if let grip { grip.padding(.trailing, -4) }
                icon(entry, tint: .secondary)
                MenuNameField(model: model, title: entry.title)
            }
            .padding(.leading, grip == nil ? 10 : 4)
            .padding(.trailing, 10)
            .frame(height: Metric.row))
        }
        let label = HStack(spacing: 10) {
            icon(entry, tint: adds ? .accentColor : .secondary)
            Text(entry.title).lineLimit(1).truncationMode(.tail)
                .fontWeight(adds ? .medium : .regular)
                .foregroundStyle(danger ? AnyShapeStyle(.red) : adds ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            if let trailing = entry.trailing {
                Text(trailing).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 4)
                    .accessibilityLabel(entry.trailingLabel.map { "\($0) \(trailing)" } ?? trailing)
            }
        }
        .padding(.leading, grip == nil ? 10 : 6)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        return AnyView(HStack(spacing: 0) {
            if let grip { grip.padding(.leading, 4) }
            if entry.submenu.isEmpty {
                Button { model.run(entry) } label: { label }
                    .buttonStyle(.plain)
            } else {
                // A choice of how: its choices hang under the row in a bubble (`submenuLayer`).
                Button { withAnimation(.bouncy(duration: 0.25)) { model.toggleSubmenu(entry) } } label: { label }
                    .buttonStyle(.plain)
                    .anchorPreference(key: SubmenuAnchorKey.self, value: .bounds) { [entry.id: $0] }
            }
            if let secondary = entry.secondary {
                secondaryButton(entry, secondary, hovered: hovered)
                    .padding(.trailing, entry.trash == nil ? 6 : 0)
            }
            if entry.trash != nil {
                trashButton(entry).padding(.trailing, 6)
            } else if entry.secondary == nil {
                Spacer().frame(width: 10)
            }
        }
        .frame(height: Metric.row)
        .background(Color.primary.opacity(hovered ? 0.06 : 0))
        .onHover { hover(entry, $0) })
    }

    /// Whether `entry` is the row being named in place.
    private func renaming(_ entry: MenuEntry) -> Bool {
        model.content.renaming == entry.id && entry.rename != nil
    }

    private func hover(_ entry: MenuEntry, _ inside: Bool) {
        hoveredRow = inside ? entry.id : (hoveredRow == entry.id ? nil : hoveredRow)
        if !inside { withAnimation(.bouncy(duration: 0.3)) { model.cancelTrash(entry) } }
    }

    /// A row's second button (Edit): quiet until its row is under the pointer.
    private func secondaryButton(_ entry: MenuEntry, _ secondary: (symbol: String, help: String, action: () -> Void),
                                 hovered: Bool) -> some View {
        Button { model.runSecondary(entry) } label: {
            Image(systemName: secondary.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(hovered ? 0.13 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(secondary.help)
        .accessibilityLabel("\(secondary.help) \(entry.title)")
    }

    /// A row's trash button: quiet beside the pencil, red under the pointer. Clicked once, the bin
    /// grows a little into a red pill asking "bin?", and a second click deletes; leaving the row
    /// shrinks it back.
    private func trashButton(_ entry: MenuEntry) -> some View {
        let hot = hoveredTrash == entry.id
        let asking = model.confirmingTrash == entry.id
        return Button { withAnimation(.bouncy(duration: 0.3, extraBounce: 0.15)) { model.runTrash(entry) } } label: {
            HStack(spacing: 1) {
                Image(systemName: "trash")
                if asking {
                    Text("?").transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(asking ? AnyShapeStyle(Color.white) : hot ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            .frame(width: asking ? 44 : 26, height: asking ? 22 : 24)
            .background {
                RoundedRectangle(cornerRadius: asking ? 11 : 6, style: .continuous)
                    .fill(Color.red.opacity(asking ? 1 : hot ? 0.13 : 0))
            }
            .padding(.trailing, asking ? 4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredTrash = inside ? entry.id : (hoveredTrash == entry.id ? nil : hoveredTrash) }
        .help(asking ? "Click again to delete" : entry.trash?.help ?? "Delete")
        .accessibilityLabel(asking ? "Confirm delete \(entry.title)" : "Delete \(entry.title)")
    }

    /// The system switch, wired to the entry's own action so the registry stays the one source of state.
    private func switchControl(_ entry: MenuEntry, isOn: Bool) -> some View {
        Toggle(entry.title, isOn: Binding(get: { isOn }, set: { _ in model.run(entry) }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }

    /// A row's icon: a drawing of the tool's own, an app's icon, or a tinted tile.
    @ViewBuilder private func icon(_ entry: MenuEntry, tint: Color) -> some View {
        switch entry.leading {
        case let .drawing(view, width):
            view.frame(width: max(Metric.tile + 2, width), height: Metric.tile)
        case let .appIcon(image):
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: Metric.tile, height: Metric.tile)
                .frame(width: Metric.tile + 2)
        case .symbol:
            IconTile(symbol: entry.symbol ?? "circle", tint: tint, size: Metric.tile)
                .frame(width: Metric.tile + 2)
        }
    }
}

extension MenuEntry {
    var leadsWithSymbol: Bool {
        if case .symbol = leading { return true }
        return false
    }
}

/// Where each row with choices sits, so its bubble can hang under it.
private struct SubmenuAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A row's name being typed in place, focused with its text selected: Return keeps it, esc keeps the
/// name it had, and clicking away or closing the dropdown keeps what was typed.
private struct MenuNameField: View {
    @ObservedObject var model: MenuPageModel
    let title: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $model.renameDraft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { model.finishRename() }
            .onChange(of: focused) { _, now in if !now { model.finishRename() } }
            .onAppear {
                model.renameDraft = title
                DispatchQueue.main.async { focused = true }
            }
            .accessibilityLabel("Name")
    }
}
#endif
