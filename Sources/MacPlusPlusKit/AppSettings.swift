#if canImport(AppKit)
import AppKit
import ApplicationServices
import Combine
import SwiftUI
import MacsShared

/// mac++'s Settings, one page of the dropdown drawn as System Settings draws a pane: which mac++
/// this is, then mac++'s own settings (Accessibility, Open at login). Settings is for mac++ only:
/// each tool's settings, its main switch among them, are on its page of the menu.
///
/// What explains them is Help, a page of its own: a tool's opens from the ? beside its name on its
/// page, mac++'s from the ? beside mac++ in Settings. Only the onboarding and the lessons, played
/// again from Help, leave the dropdown, for a window of their own.
final class AppSettings: ObservableObject {
    struct Actions {
        /// Open a page (Help) over the page showing.
        var openPage: (String) -> Void
        var setOpenAtLogin: (Bool) -> Void
        var requestAccess: () -> Void
        /// Play the onboarding (nil) or the lessons of the tool at this index again, in the
        /// onboarding window.
        var replay: (Int?) -> Void
        /// Close the dropdown, before what leaves it.
        var close: () -> Void
    }

    /// Each tool's Help, in the order of their pages (for the Help pages).
    let tools: [HelpContent]
    private let actions: Actions
    @Published private(set) var granted = AXIsProcessTrusted()
    @Published private(set) var openAtLogin = LoginItem.isEnabled

    init(tools: [HelpContent], actions: Actions) {
        self.tools = tools
        self.actions = actions
    }

    /// Read what Settings shows again.
    func refresh() {
        let granted = AXIsProcessTrusted(), login = LoginItem.isEnabled
        if granted != self.granted { self.granted = granted }
        if login != openAtLogin { openAtLogin = login }
    }

    /// Settings (`TabbedMenuPage.settings`) or a Help page, as a page of the dropdown.
    func page(_ name: String) -> TabbedMenuSubpage? {
        let view: AnyView, title: String
        switch name {
        case TabbedMenuPage.help(for: nil):
            title = "Help"
            view = AnyView(HelpPane(content: Self.help, replayTitle: "Play the onboarding again") { [weak self] in
                self?.replay(nil)
            })
        case let name where tools.contains { TabbedMenuPage.help(for: $0.name) == name }:
            let index = tools.firstIndex { TabbedMenuPage.help(for: $0.name) == name }!
            let help = tools[index]
            title = "Help"
            view = AnyView(HelpPane(content: help, replayTitle: "Play \(help.name)'s lessons again") { [weak self] in
                self?.replay(index)
            })
        case TabbedMenuPage.settings:
            title = "Settings"; view = AnyView(SettingsPage(settings: self))
        default:
            return nil
        }
        return TabbedMenuSubpage(title: title, content: view, refresh: { [weak self] in self?.refresh() })
    }

    // MARK: - What Settings and Help do

    func open(_ page: String) { actions.openPage(page) }

    func setOpenAtLogin(_ on: Bool) {
        actions.setOpenAtLogin(on)
        refresh()
    }

    func requestAccess() {
        actions.close()
        actions.requestAccess()
    }

    func replay(_ tool: Int?) {
        actions.close()
        actions.replay(tool)
    }

    /// mac++'s own Help: the menu, Settings, Accessibility and Quit, and the menu's keys.
    static let help = HelpContent(
        name: "mac++",
        tagline: "MacsPane and MacsBored, behind one icon.",
        logo: { AnyView(MacPlusPlusLogo(size: $0)) },
        topics: [
            .init("menubar.rectangle", "One icon, one menu",
                  "Click the apple in the menu bar. Each tool has a page of the menu; switch between them at its top. The ? beside a tool's name opens its Help."),
            .init("gearshape", "Settings",
                  "At the foot of the menu, for the whole app: Accessibility and Open at login. Each tool's own settings are on its page."),
            .init("hand.raised", "Accessibility",
                  "Moving windows and seeing keys both need it. One grant, in System Settings, covers both tools."),
            .init("power", "Quit mac++",
                  "Stops both tools. MacsBored gives macOS every shortcut back first."),
        ],
        keys: [
            .init("⌘1  ⌘2", "Switch between the tools"),
            .init("⌘,", "Open Settings"),
            .init("esc", "Back a page, or close the menu"),
            .init("⌘Q", "Quit mac++"),
        ],
        footnote: "The apple in the menu bar fills in while MacsBored is passing your shortcuts to an app.")

    /// "0.1.0 (12)", or nil when not run from the app bundle.
    var version: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        return short + ((info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? "")
    }
}

// MARK: - The page

/// Settings: which mac++ this is (its ? opens mac++'s Help), Accessibility and Open at login.
private struct SettingsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHero(icon: AnyView(MacPlusPlusLogo(size: 48)), title: "mac++",
                         text: settings.version.map { "Version \($0)" } ?? "Built from source") {
                settings.open(TabbedMenuPage.help(for: nil))
            }
            SettingsSection(footer: "Moving windows and seeing keys both need it. One grant, in System Settings, covers both tools.") {
                SettingsRow(icon: AnyView(SettingsIcon("hand.raised.fill", .blue)), "Accessibility") {
                    if settings.granted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant") { settings.requestAccess() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
            SettingsSection(footer: "Starts mac++, and both tools, when you log in.") {
                SettingsToggle(icon: AnyView(SettingsIcon("power", .gray)), "Open at login",
                               isOn: settings.openAtLogin) { settings.setOpenAtLogin($0) }
            }
        }
        // The same margin as a tool's page.
        .padding(12)
    }
}
#endif
