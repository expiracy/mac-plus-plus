#if canImport(AppKit)
import AppKit
import ApplicationServices
import Combine
import SwiftUI
import MacsShared

/// mac++'s Settings, one page of the dropdown drawn as System Settings draws a pane: which mac++
/// this is, mac++'s own settings (Accessibility, Open at login, the menu's Size), then a row for each
/// tool that opens its settings page. Each tool's main switch stays on its page.
///
/// What explains them is Help, a page of its own: a tool's opens from the ? beside its name on its
/// page, mac++'s from the ? beside mac++ in Settings. Only the onboarding and the lessons, played
/// again from Help, leave the dropdown, for a window of their own.
final class AppSettings: ObservableObject {
    struct Actions {
        /// Open a page (Help) over the page showing.
        var openPage: (String) -> Void
        var setOpenAtLogin: (Bool) -> Void
        /// Draw the dropdown at this size.
        var setSize: (MenuSize) -> Void
        var requestAccess: () -> Void
        /// Play the onboarding (nil) or the lessons of the tool at this index again, in the
        /// onboarding window.
        var replay: (Int?) -> Void
        /// Close the dropdown, before what leaves it.
        var close: () -> Void
    }

    /// A tool's row in Settings: its name and mark, and the page of its settings.
    struct ToolLink {
        let name: String
        let logo: (CGFloat) -> AnyView
        let page: String
    }

    /// Each tool's Help, in the order of their pages (for the Help pages).
    let tools: [HelpContent]
    /// Each tool's settings, in the order of their pages.
    let toolLinks: [ToolLink]
    private let actions: Actions
    @Published private(set) var granted = AXIsProcessTrusted()
    @Published private(set) var openAtLogin = LoginItem.isEnabled
    @Published private(set) var size = MenuSize.current

    init(tools: [HelpContent], toolLinks: [ToolLink], actions: Actions) {
        self.tools = tools
        self.toolLinks = toolLinks
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
            view = AnyView(HelpPane(content: help, replayTitle: "Play the \(help.title ?? help.name) lessons again") { [weak self] in
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

    func setSize(_ size: MenuSize) {
        self.size = size
        actions.setSize(size)
    }

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
        mark: { AnyView(MacPlusPlusGlyph(filled: true).frame(width: $0, height: $0).foregroundStyle(.primary)) },
        shape: .init("What mac++ is made of", parts: [
            .init("menubar.rectangle", "The menu",
                  "Click the apple in the menu bar. Each tool has a page of it; switch between them at its top."),
            .init("square.stack", "A tool's page",
                  "The tool's switch, what it's doing now, and its lists: MacsPane's layouts, presets and shortcuts, MacsBored's actions. + Add on a list makes a new one; a row's pencil changes it."),
            .init("gearshape", "Settings and Help",
                  "Settings, at the foot of the menu, holds Accessibility, Open at login and the menu's size, then each tool's own settings. The ? beside a tool's name opens its Help."),
        ], footnote: "MacsPane decides where windows go; MacsBored decides what happens when you do something."),
        topics: [
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

/// Settings: which mac++ this is (its ? opens mac++'s Help), Accessibility, Open at login and how big
/// the menu is drawn, then each tool's settings, a page each.
private struct SettingsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHero(icon: AnyView(MacPlusPlusGlyph(filled: true).frame(width: 40, height: 40)
                                           .foregroundStyle(.primary)), title: "mac++",
                         text: settings.version.map { "Version \($0)" } ?? "Built from source") {
                settings.open(TabbedMenuPage.help(for: nil))
            }
            SettingsSection("General", footer: "For mac++ as a whole: they cover both apps.") {
                SettingsRow(icon: AnyView(SettingsIcon("hand.raised.fill", .blue)), "Accessibility") {
                    if settings.granted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant") { settings.requestAccess() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                SettingsToggle(icon: AnyView(SettingsIcon("power", .gray)), "Open at login",
                               isOn: settings.openAtLogin) { settings.setOpenAtLogin($0) }
                SettingsRow(icon: AnyView(SettingsIcon("textformat.size", .indigo)), "Size") {
                    Picker("Size", selection: Binding(get: { settings.size }, set: { settings.setSize($0) })) {
                        ForEach(MenuSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
                }
            }
            if !settings.toolLinks.isEmpty {
                SettingsSection("Apps", footer: "Each app's own settings. Its on switch is on its page of the menu.") {
                    ForEach(settings.toolLinks, id: \.page) { tool in
                        SettingsLink(icon: tool.logo(22), tool.name) { settings.open(tool.page) }
                    }
                }
            }
        }
        // The same margin as a tool's page.
        .padding(12)
    }
}
#endif
