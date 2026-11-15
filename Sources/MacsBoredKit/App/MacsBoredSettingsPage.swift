#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore
import MacsShared

/// MacsBored's settings, a page of the dropdown opened from mac++'s Settings: Caps Lock as Hyper, the
/// keys that pause passthrough, and the settings file. MacsBored's own switch stays on its page,
/// beside its name.
struct MacsBoredSettingsView: View {
    @ObservedObject var model: MacsBoredModel
    /// Closes the dropdown, before Finder or an editor comes forward.
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(footer: hyperNote) {
                SettingsToggle(icon: AnyView(SettingsIcon("capslock", .purple)), "Caps Lock as Hyper",
                               isOn: model.config.hyperKeyEnabled) { model.setHyperKey($0) }
            }
            SettingsSection(footer: "Gives macOS its shortcuts back in the passthrough app in front, until you switch apps. To change the keys, edit pauseKeys in the settings file.") {
                SettingsRow(icon: AnyView(SettingsIcon("pause.circle", .gray)), "Pause passthrough") {
                    Text(model.config.pauseKeys?.displayName ?? "None").foregroundStyle(.secondary)
                }
            }
            SettingsSection("Settings file",
                            footer: "Passthrough apps and triggers are kept in config.json. MacsBored picks up a change as soon as it's saved.") {
                SettingsLink(icon: AnyView(SettingsIcon("folder", .blue)), "Show in Finder", kind: .window) {
                    close()
                    model.revealConfigFile()
                }
                SettingsLink(icon: AnyView(SettingsIcon("doc.text", .gray)), "Open config.json", kind: .window) {
                    close()
                    model.openConfigFile()
                }
            }
        }
        // The same margin as a tool's page.
        .padding(12)
    }

    private var hyperNote: String {
        model.config.hyperKeyEnabled && model.hyperBlocked
            ? "Another tool already remaps keys, so Caps Lock stays as it is."
            : "Caps Lock holds ⌃⌥⇧⌘, a combination no app uses, for triggers of your own."
    }
}

extension MacsBoredModel {
    /// MacsBored's settings page of the dropdown.
    func settingsPage(close: @escaping () -> Void) -> TabbedMenuSubpage {
        TabbedMenuSubpage(title: "MacsBored", content: AnyView(MacsBoredSettingsView(model: self, close: close)),
                          changes: objectWillChange.map { _ in () }.eraseToAnyPublisher())
    }
}
#endif
