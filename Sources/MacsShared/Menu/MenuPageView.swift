#if canImport(AppKit)
import AppKit
import SwiftUI

/// A tool's page of the dropdown, drawn the same for every tool: the tool's mark and name with what it
/// is doing, its Help and its main switch; then rounded cards, each under a title that folds it: what
/// is happening now with its one button, any warning with its fix, the titled lists, and the general
/// switches. Rows lead with a tinted icon tile, an app's icon or a drawing of the tool's own. A long
/// list scrolls inside its card, and a row of a list that can be reordered is dragged by its picture:
/// the other rows slide aside (VoiceOver finds Move up and Move down among the row's actions). A row
/// ends with its keys, its pencil and bin, then its switch. The dropdown around it adds the switcher,
/// the bubble and the footer shared by every page.
public struct MenuPageView: View {
    @ObservedObject var model: MenuPageModel
    @Environment(\.openHelp) private var openHelp
    @State private var hoveredRow: String?
    @State private var hoveredTrash: String?
    @State private var hoveredAdd: String?
    @State private var drag: RowDrag?

    public init(model: MenuPageModel) {
        self.model = model
    }

    /// The row being dragged by its picture: which list, where it started, and how far the pointer has gone.
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
        static let submenuWidth: CGFloat = 230
    }

    public var body: some View {
        let content = model.content
        VStack(alignment: .leading, spacing: 14) {
            header(content)
            if !content.live.isEmpty || model.brand.emptyLive != nil { liveCard(content.live) }
            ForEach(content.warnings) { warningCard($0) }
            ForEach(content.groups) { groupCard($0) }
            // Set once and left: under the lists, which are what the page is opened for.
            if !content.toggles.isEmpty {
                section(model.brand.togglesTitle, count: content.toggles.count) { rows(content.toggles) }
            }
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
               let entry = model.content.groups.flatMap({ $0.actions + [$0.add].compactMap { $0 } })
                   .first(where: { $0.id == id }) {
                let row = proxy[anchor]
                // From a row, the bubble lines up with its icon; from a + at a title's end, it keeps
                // inside the page, its nub pointing at the +.
                let x = min(row.minX + 4, proxy.size.width - Metric.submenuWidth - 4)
                let nubX = row.width > 60 ? Metric.submenuNubX : row.midX - x
                // Under the row, unless that would run past the foot of the page (into the dropdown's
                // footer, or off it): then over the row, its nub pointing down at it.
                let height = submenuHeight(entry)
                let up = row.maxY - 6 + height > proxy.size.height && row.minY + 6 - height >= 0
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.openSubmenu = nil } }
                    submenuBubble(entry, up: up, nubX: nubX)
                        .offset(x: x, y: up ? row.minY + 6 - height : row.maxY - 6)
                        .transition(.scale(scale: 0.85, anchor: up ? .bottomLeading : .topLeading).combined(with: .opacity))
                }
            }
        }
    }

    /// The bubble's height: its rows, its padding and its nub.
    private func submenuHeight(_ entry: MenuEntry) -> CGFloat {
        CGFloat(entry.submenu.count) * (Metric.row - 4) + 12 + SpeechBubbleShape.standardNub.height
    }

    private func submenuBubble(_ entry: MenuEntry, up: Bool, nubX: CGFloat) -> some View {
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
        .padding(up ? .bottom : .top, SpeechBubbleShape.standardNub.height)
        .frame(width: Metric.submenuWidth)
        .background(SpeechBubbleShape(nubX: nubX, corner: Metric.corner, pointsDown: up)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: nubX, corner: Metric.corner, pointsDown: up)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.title)
    }

    // MARK: - Bands

    /// The tool's name and mark with what it is doing, its Help and its main switch. Under the
    /// dropdown's switcher, which shows the name and mark already, only what it is doing.
    /// The tool's mark and name with what it is doing, its Help, and its main switch.
    private func header(_ content: MenuPageContent) -> some View {
        PageHeader(logo: model.brand.logo(32), title: model.brand.name,
                   line: content.liveFact ?? content.primary?.title, help: openHelp) {
            mainSwitch(content)
        }
    }

    @ViewBuilder private func mainSwitch(_ content: MenuPageContent) -> some View {
        if let primary = content.primary, case let .toggle(isOn, _, _) = primary.kind {
            switchControl(primary, isOn: isOn)
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
        section(group.title, count: group.rows.count, add: group.add) {
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
    /// a row is dragged by its picture; while one is dragged the lines step aside so nothing is left
    /// behind.
    private func rows(_ entries: [MenuEntry], in group: MenuGroup? = nil) -> some View {
        let movable = group?.move != nil && entries.count > 1 ? group : nil
        let dragging = movable != nil && drag?.group == movable?.id
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let lifted = dragging && drag?.from == index
                row(entry, handle: movable.map { RowHandle(group: $0, index: index, count: entries.count) })
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

    /// Moving a row one place up or down, for VoiceOver (the pointer drags the row's picture).
    private func moves(_ handle: RowHandle?) -> RowMoves? {
        guard let handle else { return nil }
        let (group, index, count) = (handle.group, handle.index, handle.count)
        return RowMoves(up: index > 0 ? { model.move(group, from: index, to: index - 1) } : nil,
                        down: index < count - 1 ? { model.move(group, from: index, to: index + 1) } : nil)
    }

    /// A row's picture, which drags the row when its list can be reordered: an open hand under the
    /// pointer, a closed one while dragging. A click (no drag) runs `tap`, as clicking the row would.
    @ViewBuilder
    private func picture(_ entry: MenuEntry, tint: Color, handle: RowHandle?, tap: (() -> Void)? = nil) -> some View {
        if let handle {
            icon(entry, tint: tint)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .onTapGesture { tap?() }
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if drag == nil { NSCursor.closedHand.push() }
                        drag = RowDrag(group: handle.group.id, from: handle.index, height: value.translation.height)
                    }
                    .onEnded { _ in
                        guard let current = drag else { return }
                        NSCursor.pop()
                        let to = target(current, count: handle.count)
                        withAnimation(.easeOut(duration: 0.15)) {
                            drag = nil
                            if to != current.from { model.move(handle.group, from: current.from, to: to) }
                        }
                    })
                .help("Drag to reorder")
                .accessibilityHidden(true)
        } else {
            icon(entry, tint: tint)
        }
    }

    /// The end of a row, before its switch: its keys, then its pencil and bin.
    private func rowEnd(_ entry: MenuEntry, dim: Bool) -> some View {
        HStack(spacing: 4) {
            if let trailing = entry.trailing {
                Text(trailing).font(.callout.monospacedDigit())
                    .foregroundStyle(dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(entry.trailingLabel.map { "\($0) \(trailing)" } ?? trailing)
            }
            HStack(spacing: 0) {
                if let secondary = entry.secondary {
                    secondaryButton(entry, secondary, hovered: hoveredRow == entry.id)
                }
                if entry.trash != nil { trashButton(entry) }
            }
        }
    }

    @ViewBuilder private func row(_ entry: MenuEntry, handle: RowHandle? = nil) -> some View {
        switch entry.kind {
        case .section:
            Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case let .toggle(isOn, disabled, _):
            HStack(spacing: 10) {
                picture(entry, tint: .secondary, handle: handle)
                if renaming(entry) {
                    MenuNameField(model: model, title: entry.title)
                } else {
                    Text(entry.title).lineLimit(1).truncationMode(.tail)
                        .modifier(RowActions(moves: moves(handle)))
                    Spacer(minLength: 4)
                    rowEnd(entry, dim: !isOn)
                }
                switchControl(entry, isOn: isOn)
            }
            .padding(.horizontal, 10)
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
            commandRow(entry, danger: danger, handle: handle)
        case .live, .warning:
            EmptyView()
        }
    }

    /// A row you click: the whole line is the target and lights under the pointer. A command that adds
    /// something ("New preset…", a plus or a symbol badged with one) is drawn in the accent, like the
    /// app's other primary actions. Its keys, then its pencil and bin, sit at the end.
    /// The row just added and being named shows its name field in place of the title and buttons.
    private func commandRow(_ entry: MenuEntry, danger: Bool, handle: RowHandle?) -> some View {
        let hovered = hoveredRow == entry.id
        let adds = (entry.symbol == "plus" || entry.symbol?.hasSuffix(".badge.plus") == true) && entry.leadsWithSymbol
        let tint: Color = adds ? .accentColor : .secondary
        if renaming(entry) {
            return AnyView(HStack(spacing: 10) {
                picture(entry, tint: tint, handle: handle)
                MenuNameField(model: model, title: entry.title)
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row))
        }
        // A row that drags keeps its picture out of the button, so a drag never clicks it.
        let label = HStack(spacing: 10) {
            if handle == nil { icon(entry, tint: tint) }
            Text(entry.title).lineLimit(1).truncationMode(.tail)
                .fontWeight(adds ? .medium : .regular)
                .foregroundStyle(danger ? AnyShapeStyle(.red) : adds ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(.primary))
            Spacer(minLength: 4)
        }
        .padding(.leading, handle == nil ? 10 : 0)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        return AnyView(HStack(spacing: 0) {
            if handle != nil {
                picture(entry, tint: tint, handle: handle) { model.run(entry) }
                    .padding(.leading, 10).padding(.trailing, 10)
            }
            if entry.submenu.isEmpty {
                Button { model.run(entry) } label: { label }
                    .buttonStyle(.plain)
                    .modifier(RowActions(moves: moves(handle)))
            } else {
                // A choice of how: its choices hang under the row in a bubble (`submenuLayer`).
                Button { withAnimation(.bouncy(duration: 0.25)) { model.toggleSubmenu(entry) } } label: { label }
                    .buttonStyle(.plain)
                    .anchorPreference(key: SubmenuAnchorKey.self, value: .bounds) { [entry.id: $0] }
            }
            rowEnd(entry, dim: false).padding(.trailing, 10)
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
    // MARK: - Sections

    /// A titled card of rows that folds to its title: click the title (a chevron before it) to fold
    /// or open it. Folded, the title says how many rows it holds. An empty section starts folded.
    @ViewBuilder
    private func section<Rows: View>(_ title: String, count: Int, add: MenuEntry? = nil,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        let folded = model.isFolded(title, isEmpty: count == 0)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitleButton(title, count: count, folded: folded)
                Spacer(minLength: 6)
                if let add { addButton(add, section: title, count: count, folded: folded) }
            }
            .padding(.horizontal, 4)
            if !folded { card(rows) }
        }
    }

    /// "+ Add" at the end of a section's title, on a grey capsule like the Back button's: it opens the
    /// section, then makes a new row (or opens its choices, in a bubble hanging from it). The capsule
    /// deepens under the pointer and while its choices are open.
    @ViewBuilder
    private func addButton(_ add: MenuEntry, section title: String, count: Int, folded: Bool) -> some View {
        let hot = hoveredAdd == add.id || model.openSubmenu == add.id
        let button = Button {
            if folded { model.toggleCollapsed(title, isEmpty: count == 0) }
            if add.submenu.isEmpty { model.run(add) }
            else { withAnimation(.bouncy(duration: 0.25)) { model.toggleSubmenu(add) } }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text("Add").font(.caption.weight(.medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.primary.opacity(hot ? 0.12 : 0.07)))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: hot)
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredAdd = inside ? add.id : (hoveredAdd == add.id ? nil : hoveredAdd) }
        .help(add.title)
        .accessibilityLabel(add.title)
        if add.submenu.isEmpty { button }
        else { button.anchorPreference(key: SubmenuAnchorKey.self, value: .bounds) { [add.id: $0] } }
    }

    private func chevron(folded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(folded ? 0 : 90))
            .frame(width: 12)
    }

    private func sectionTitleButton(_ title: String, count: Int, folded: Bool) -> some View {
        Button { model.toggleCollapsed(title, isEmpty: count == 0) } label: {
            HStack(spacing: 5) {
                chevron(folded: folded)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.8))
                if folded { Text("\(count)").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show \(title)" : "Hide \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(folded ? "Collapsed" : "Expanded")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(CardStyle.fill))
            .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(CardStyle.stroke))
            .clipShape(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous))
    }

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

/// A row of a list that can be reordered: which list, and where in it.
private struct RowHandle {
    let group: MenuGroup
    let index: Int
    let count: Int
}

/// Moving a row of a reorderable list one place; nil at that end of the list.
private struct RowMoves {
    let up: (() -> Void)?
    let down: (() -> Void)?
}

/// Moving a row of a reorderable list, as VoiceOver actions on its name: the pointer drags its picture.
private struct RowActions: ViewModifier {
    let moves: RowMoves?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let up = moves?.up { Button("Move up", action: up) }
            if let down = moves?.down { Button("Move down", action: down) }
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
