#if canImport(AppKit)
import MacsShared
import SwiftUI
import MacsBoredCore

/// What the editor page is editing, shared by its form and its bar.
final class EntryEditorState: ObservableObject {
    @Published var draft: EntryDraft
    let isNew: Bool

    init(draft: EntryDraft) {
        self.draft = draft
        isNew = draft.origin == .new
    }
}

/// The editor page's bar, kept in view under the form however far it scrolls: what is still missing,
/// then the bin (for a saved one), Cancel and Save.
struct EntryEditorBar: View {
    @ObservedObject var state: EntryEditorState
    let onSave: (EntryDraft.Result) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    @State private var confirmingDelete = false
    @Environment(\.closePage) private var closePage

    private var draft: EntryDraft { state.draft }
    private var isNew: Bool { state.isNew }

    var body: some View {
        HStack(spacing: 8) {
            if let missing = draft.missing {
                Text(missing).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if !isNew { deleteButton }
            Button("Cancel") { onCancel(); closePage?() }
            Button("Save") {
                guard let result = draft.result else { return }
                onSave(result)
                closePage?()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.result == nil)
        }
    }

    /// The bin, as in MacsPane: clicked once it turns into a red "bin ?", and a second click deletes.
    @ViewBuilder private var deleteButton: some View {
        if confirmingDelete {
            Button { onDelete(); closePage?() } label: {
                HStack(spacing: 1) { Image(systemName: "trash"); Text("?").fontWeight(.semibold) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .help("Click again to delete for good")
            .accessibilityLabel("Confirm delete")
        } else {
            Button { withAnimation(.bouncy(duration: 0.3)) { confirmingDelete = true } } label: {
                Image(systemName: "trash")
            }
            .help(draft.isPassthroughApp ? "Delete this passthrough app" : "Delete this trigger")
            .accessibilityLabel("Delete")
        }
    }
}
#endif
