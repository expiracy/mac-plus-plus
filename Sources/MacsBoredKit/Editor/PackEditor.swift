#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore
import MacsShared

/// A pack's page, opened from its pencil: its name (typed in place, as an action's is), its switch,
/// the apps its actions work in, and what's in it. Each change applies as it's made, as the list's
/// switches do; the bar has Done, and the bin, which asks first.
/// The pack a page is on, by its name now (renaming on the page changes it), for the page and its bar.
@MainActor
final class PackPageState: ObservableObject {
    @Published var name: String
    init(name: String) { self.name = name }
}

struct PackEditor: View {
    @ObservedObject var model: MacsBoredModel
    @ObservedObject var page: PackPageState
    private var name: String { page.name }
    @State private var typed: String?
    @State private var refused = false
    @FocusState private var naming: Bool
    /// The sections folded to their title, by title: both start open.
    @State private var folded: Set<String> = []
    @Environment(\.stepAway) private var stepAway

    private var pack: ActionPack? { model.config.pack(named: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pack {
                header(pack)
                appsSection(pack)
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
        let what = count == 0 ? "Nothing in it yet" : count == 1 ? "1 action" : "\(count) actions"
        let place = pack.apps.isEmpty ? "working everywhere" : "working only in " + Self.joined(pack.apps.map(AppIcons.name))
        return pack.isEnabled ? "\(what), \(place)." : "\(what), all off while the pack is."
    }

    private func appsSection(_ pack: ActionPack) -> some View {
        VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "Works only in", count: pack.apps.count,
                               summary: pack.apps.isEmpty ? "Everywhere" : pack.apps.map(AppIcons.name).joined(separator: ", "),
                               folded: folded.contains("Works only in"), toggleFold: { fold("Works only in") })
            if !folded.contains("Works only in") {
            AppChips(apps: Binding(get: { pack.apps }, set: { model.setPackApps(name, $0) }),
                     suggestions: Self.runningApps, suggestionsTitle: "Open now", stepAway: stepAway)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(RowCard())
            Text("Its actions work only in these apps, unless one names apps of its own. None: everywhere.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The pack's actions, by name; each opens in the editor, where it can leave the pack.
    private var contents: some View {
        VStack(alignment: .leading, spacing: CardStyle.rowGap) {
            EditorSectionTitle(title: "In it", count: actions.count, summary: actions.map(\.name).joined(separator: " · "),
                               folded: folded.contains("In it"), toggleFold: { fold("In it") })
            if folded.contains("In it") {
                EmptyView()
            } else if actions.isEmpty {
                EmptyNote(text: "Choose this pack in an action's editor to add it here.")
            } else {
                ForEach(actions, id: \.id) { action in
                    Button { action.edit() } label: {
                        HStack(spacing: 8) {
                            Text(action.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: CardStyle.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(RowCard())
                    .help("Edit \(action.name)")
                }
            }
        }
    }

    private struct Member {
        let id: UUID
        let name: String
        let edit: () -> Void
    }

    private var actions: [Member] {
        model.config.triggers.filter { $0.packs.contains(name) }.map { trigger in
            Member(id: trigger.id, name: trigger.name) { [weak model] in model?.editTrigger(trigger.id) }
        } + model.config.profiles.filter { $0.packs.contains(name) }.map { profile in
            Member(id: profile.id, name: profile.name) { [weak model] in model?.editProfile(profile.id) }
        }
    }

    private func fold(_ title: String) {
        withAnimation(.easeOut(duration: 0.15)) { if folded.remove(title) == nil { folded.insert(title) } }
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

    private static var runningApps: [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { AppRef(bundleID: $0, name: app.localizedName ?? $0) } }
    }

    private static func joined(_ words: [String]) -> String {
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " or " + words[words.count - 1]
    }
}

/// The pack page's bar: its bin, which asks first and keeps the pack's actions, then Done.
struct PackEditorBar: View {
    let onDelete: () -> Void
    @State private var confirming = false
    @Environment(\.closePage) private var closePage

    var body: some View {
        HStack(spacing: 8) {
            Text("Deleting a pack keeps its actions.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if confirming {
                Button { onDelete(); closePage?() } label: {
                    HStack(spacing: 1) { Image(systemName: "trash"); Text("?").fontWeight(.semibold) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Click again to delete the pack")
                .accessibilityLabel("Confirm delete")
            } else {
                Button { withAnimation(.bouncy(duration: 0.3)) { confirming = true } } label: { Image(systemName: "trash") }
                    .help("Delete this pack")
                    .accessibilityLabel("Delete")
            }
            Button("Done") { closePage?() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
#endif
