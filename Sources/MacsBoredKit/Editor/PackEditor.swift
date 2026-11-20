#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore
import MacsShared

/// The pack a page is on, by its name now (renaming on the page changes it), for the page and its bar.
@MainActor
final class PackPageState: ObservableObject {
    @Published var name: String
    init(name: String) { self.name = name }
}

/// A pack's page, opened from its pencil: a folder of actions. Its name (typed in place, as an
/// action's is) and switch, then its actions, then Add actions. Each change applies as it's made, as
/// the list's switches do; the bar has the bin, which asks first, and Done.
struct PackEditor: View {
    @ObservedObject var model: MacsBoredModel
    @ObservedObject var page: PackPageState
    private var name: String { page.name }
    @State private var typed: String?
    @State private var refused = false
    @FocusState private var naming: Bool
    /// Add actions is open: its choices show under the pack's actions.
    @State private var adding = false

    private var pack: ActionPack? { model.config.pack(named: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pack {
                header(pack)
                contents
            } else {
                EmptyNote(text: "This pack is gone.")
            }
        }
        .padding(12)
    }

    /// One line, as the action editor's: the pack's mark, its name with a pencil, its switch; what it
    /// does in a sentence under them.
    private func header(_ pack: ActionPack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pack.isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                HStack(spacing: 3) {
                    TextField("Name", text: Binding(get: { typed ?? name }, set: { typed = $0; refused = false }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($naming)
                        .onSubmit(commitName)
                        .fixedSize()
                    Button { naming = true } label: {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(naming ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename")
                    .accessibilityLabel("Rename")
                }
                Spacer(minLength: 4)
                Toggle(name, isOn: Binding(get: { pack.isEnabled }, set: { _ in model.togglePack(name) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help(pack.isEnabled ? "Turn \(name) off" : "Turn \(name) on")
            }
            .frame(height: 24)
            Text(refused ? "Another pack has that name. Choose another." : sentence(pack))
                .font(.caption).foregroundStyle(refused ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 4)
        .onChange(of: naming) { _, now in if !now { commitName() } }
    }

    private func sentence(_ pack: ActionPack) -> String {
        let count = actions.count
        let what = count == 0 ? "Empty" : count == 1 ? "1 action" : "\(count) actions"
        return pack.isEnabled ? what : "\(what), off with the pack"
    }

    /// The pack's actions, as the Actions list draws them: each its name, what starts it and its
    /// switch, opening in the editor when clicked, and taken out of the pack from its right-click
    /// menu. Then Add actions, which opens in place into a new action (in this pack) and every action
    /// not in it.
    private var contents: some View {
        VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            ForEach(actions, id: \.id) { action in
                memberRow(action)
            }
            if adding {
                addChoices
            } else {
                addRow
            }
        }
    }

    /// "+ Add actions", on a dashed card where the next row would go.
    private var addRow: some View {
        let shape = RoundedRectangle(cornerRadius: CardStyle.rowCorner, style: .continuous)
        return Button { withAnimation(.easeOut(duration: 0.15)) { adding = true } } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                Text(actions.isEmpty ? "Add actions, or drag them onto the pack in the list" : "Add actions")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: CardStyle.rowHeight)
            .contentShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    private func memberRow(_ action: Member) -> some View {
        HStack(spacing: 8) {
            Button { action.edit() } label: {
                HStack(spacing: 8) {
                    Text(action.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(action.start).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    // The pencil the Actions list's rows have: the whole row opens the editor.
                    Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit \(action.name)")
            Toggle(action.name, isOn: Binding(get: { action.isOn }, set: { _ in action.toggle() }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .help(action.isOn ? "Turn \(action.name) off" : "Turn \(action.name) on")
        }
        .padding(.horizontal, 10)
        .frame(height: CardStyle.rowHeight)
        .modifier(RowCard())
        .contextMenu {
            Button("Edit", systemImage: "pencil") { action.edit() }
            Button("Take Out of Pack", systemImage: "shippingbox") { [weak model] in
                model?.setInPack(action.entry, name, false)
            }
        }
    }

    /// A new action, in this pack, then each action not in it, to put in.
    private var addChoices: some View {
        let others = model.config.triggers.filter { !$0.packs.contains(name) }.map { trigger in
            AddChoice(title: trigger.name, symbol: trigger.starts.first?.kind.symbol ?? TriggerStart.Kind.keys.symbol) { [weak model] in
                model?.setInPack(.trigger(trigger.id), name, true)
            }
        } + model.config.profiles.filter { !$0.packs.contains(name) }.map { profile in
            AddChoice(title: profile.name, symbol: EntryDraft.When.appInFront.symbol) { [weak model] in
                model?.setInPack(.profile(profile.id), name, true)
            }
        }
        let new = AddChoice(title: "New action", symbol: "plus") { [weak model, name] in
            var draft = EntryDraft()
            draft.packs = [name]
            model?.newEntry(draft)
        }
        let items = [new] + others
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Add to \(name)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.15)) { adding = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }
            ChoiceChips(values: items.indices.map { $0 }, title: { items[$0].title },
                        symbol: { items[$0].symbol }) { index in
                withAnimation(.easeOut(duration: 0.15)) {
                    items[index].action()
                    // Stays open to add more, until the new action's editor opens or none are left.
                    if index == 0 || others.count == 1 { adding = false }
                }
            }
            if others.isEmpty {
                Text("Every action is in it already.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RowCard())
        .overlay(RoundedRectangle(cornerRadius: CardStyle.rowCorner, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.45)))
    }

    private struct Member {
        let id: UUID
        let entry: MacsBoredConfig.Entry
        let name: String
        let start: String
        let isOn: Bool
        let edit: () -> Void
        let toggle: () -> Void
    }

    private var actions: [Member] {
        model.config.triggers.filter { $0.packs.contains(name) }.map { trigger in
            Member(id: trigger.id, entry: .trigger(trigger.id), name: trigger.name,
                   start: MacsBoredMenu.startLabel(trigger), isOn: trigger.isEnabled,
                   edit: { [weak model] in model?.editTrigger(trigger.id) },
                   toggle: { [weak model] in model?.toggleTrigger(trigger.id) })
        } + model.config.profiles.filter { $0.packs.contains(name) }.map { profile in
            Member(id: profile.id, entry: .profile(profile.id), name: profile.name, start: MacsBoredMenu.profileLabel(profile),
                   isOn: profile.isEnabled,
                   edit: { [weak model] in model?.editProfile(profile.id) },
                   toggle: { [weak model] in model?.toggleProfile(profile.id) })
        }
    }

    private func commitName() {
        guard let typed, typed != name else { self.typed = nil; return }
        if model.renamePack(name, to: typed) {
            page.name = typed.trimmingCharacters(in: .whitespaces)
            self.typed = nil
        } else {
            refused = !typed.trimmingCharacters(in: .whitespaces).isEmpty
            if !refused { self.typed = nil }
        }
    }
}

/// The pack page's bar: its bin, which asks first and keeps the pack's actions, then Done.
struct PackEditorBar: View {
    let onDelete: () -> Void
    @State private var confirming = false
    @Environment(\.closePage) private var closePage

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
            if confirming {
                Button { onDelete(); closePage?() } label: {
                    HStack(spacing: 1) { Image(systemName: "trash"); Text("?").fontWeight(.semibold) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Click again to delete the pack. Its actions stay.")
                .accessibilityLabel("Confirm delete")
            } else {
                Button { withAnimation(.bouncy(duration: 0.3)) { confirming = true } } label: { Image(systemName: "trash") }
                    .help("Delete this pack, keeping its actions")
                    .accessibilityLabel("Delete")
            }
            Button("Done") { closePage?() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
#endif
