#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore
import MacsShared

/// MacsPane's settings, a page of the dropdown opened from mac++'s Settings: how long a dragged window
/// rests on the notch before the picker opens, and the settings file. Snapping's own switch stays on
/// MacsPane's page, beside its name.
struct MacsPaneSettingsView: View {
    @ObservedObject var model: MacsPaneModel
    /// Closes the dropdown, before Finder or an editor comes forward.
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(footer: "How long a window dragged by its title bar rests on the notch before your layouts open.") {
                SettingsRow(icon: AnyView(SettingsIcon("timer", .orange)), "Hold for") {
                    Picker("Hold for", selection: Binding(get: { model.config.dwellChoiceIndex },
                                                          set: { model.setDwell(MacsPaneConfig.dwellChoices[$0]) })) {
                        ForEach(MacsPaneConfig.dwellChoices.indices, id: \.self) {
                            Text(MacsPaneMenu.seconds(MacsPaneConfig.dwellChoices[$0])).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                }
            }
            SettingsSection("Settings file",
                            footer: "Presets, layouts and shortcuts are kept in config.json. MacsPane picks up a change as soon as it's saved.") {
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
}

extension MacsPaneModel {
    /// MacsPane's settings page of the dropdown.
    func settingsPage(close: @escaping () -> Void) -> TabbedMenuSubpage {
        TabbedMenuSubpage(title: "MacsPane", content: AnyView(MacsPaneSettingsView(model: self, close: close)),
                          changes: objectWillChange.map { _ in () }.eraseToAnyPublisher())
    }
}
#endif
