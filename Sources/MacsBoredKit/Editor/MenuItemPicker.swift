#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// The menu item a step chooses: typed as "Format > Column > AutoFit Selection", or picked in place
/// from the app's own menus, a level at a time: a menu's items as chips (› on those with more), and
/// the way back up as a trail above them.
struct MenuItemPicker: View {
    @Binding var path: MenuPath
    /// The app whose menus are offered; nil when there's none to read.
    let app: NSRunningApplication?
    /// The app the action is limited to, when it isn't open: open it to pick from its menus.
    var closedApp: String?
    /// The menus gone into so far.
    @State private var browse: [String] = []
    @State private var entries: [AppMenus.Entry]?
    /// What's typed, kept as typed (a trailing " > " included) until the path is picked instead.
    @State private var typed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Format > Column > AutoFit Selection",
                      text: Binding(get: { typed ?? path.titles.joined(separator: " > ") },
                                    set: { typed = $0; path = MenuPath(text: $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            if let app {
                if let entries {
                    trail(app)
                    ScrollView {
                        ChoiceChips(values: entries, title: { $0.hasSubmenu ? $0.title + " ›" : $0.title },
                                    isChosen: { isChosen($0) }) { pick($0) }
                    }
                    .frame(maxHeight: 128)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    note("Couldn't read \(name(app))'s menus. Type the path above.")
                }
            } else if let closedApp {
                note("Open \(closedApp) to pick from its menus, or type the path above.")
            } else {
                note("Limit this action to an app under Where and when, or have the app open, to pick from its menus. Or type the path above.")
            }
        }
        .onAppear {
            if path.isComplete { browse = Array(path.titles.dropLast()) }
        }
        .task(id: Key(pid: app?.processIdentifier, browse: browse)) { load() }
    }

    private struct Key: Equatable {
        let pid: pid_t?
        let browse: [String]
    }

    /// The app, then each menu gone into, each a step back up.
    private func trail(_ app: NSRunningApplication) -> some View {
        HStack(spacing: 4) {
            crumb(name(app), depth: 0)
            ForEach(Array(browse.enumerated()), id: \.offset) { index, title in
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                crumb(title, depth: index + 1)
            }
        }
        .font(.caption)
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        let here = depth == browse.count
        return Button { browse = Array(browse.prefix(depth)) } label: {
            Text(title)
                .fontWeight(here ? .semibold : .regular)
                .foregroundStyle(here ? Color.primary : Color.accentColor)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(here)
    }

    private func isChosen(_ entry: AppMenus.Entry) -> Bool {
        let titles = browse + [entry.title]
        return path.titles.count == titles.count && zip(path.titles, titles).allSatisfy { MenuPath.matches($0, $1) }
    }

    private func pick(_ entry: AppMenus.Entry) {
        if entry.hasSubmenu {
            browse.append(entry.title)
        } else {
            path = MenuPath(browse + [entry.title])
            typed = nil
        }
    }

    private func load() {
        guard let app else { entries = nil; return }
        let found = AppMenus.entries(at: browse, pid: app.processIdentifier)
        if found == nil, !browse.isEmpty {
            browse = []   // a path the app doesn't have: back to its menu bar
            return
        }
        entries = found
    }

    private func name(_ app: NSRunningApplication) -> String { app.localizedName ?? "The app" }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
