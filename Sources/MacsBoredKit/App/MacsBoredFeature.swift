#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsBoredCore
import MacsShared

/// MacsBored, mac++'s keyboard half: hands macOS's own shortcuts to the apps that should have them
/// (Windows App, Citrix Viewer, a VM) and runs your own triggers everywhere else. The app that hosts
/// it (mac++) owns the menu-bar icon, the dropdown, onboarding, Settings and Help; this is
/// the rest: the config file, the model, the editor (a page of the dropdown), and MacsBored's page,
/// lessons and Help. `stop()`
/// puts every macOS shortcut back, so the host calls it on the way out.
@MainActor
public final class MacsBoredFeature {
    /// MacsBored's page of the dropdown, with its Help.
    public let tab: MenuTab
    /// Whether macOS's shortcuts are being handed to an app right now; the host shows it in its icon.
    public var onPassthroughChange: ((Bool) -> Void)?

    private let model: MacsBoredModel
    /// The entry the editor page opens on next.
    private var editing: EntryDraft?

    /// The editor's page of the dropdown.
    static let editorPage = "macsbored-entry"
    /// The names of MacsBored's own pages of the dropdown, for pictures of them.
    public static let pages = [editorPage]

    /// The config file's commands for scripts and agents, answered before the app starts:
    /// `macsbored path`, `macsbored check [file]`, `macsbored schema` (after the program's own path).
    /// Nil when `arguments` are the app's own.
    public nonisolated static func runCommand(arguments: [String]) -> (output: String, status: Int32)? {
        let rest = Array(arguments.dropFirst())
        guard rest.first == "macsbored" else { return nil }
        guard let outcome = ConfigCommand.run(Array(rest.dropFirst()), defaultURL: configURL) else {
            return ("usage: macsbored path | check [file] | schema", 64)
        }
        return (outcome.output, outcome.status)
    }

    private nonisolated static var configURL: URL {
        (try? MacsBoredPaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-config.json")
    }

    public init() {
        let model = MacsBoredModel(store: MacsBoredConfigStore(url: Self.configURL,
                                                               legacyURL: try? MacsBoredPaths.legacyConfigURL()))
        self.model = model
        let page = MenuPageModel(brand: MacsBoredMenu.brand) { [weak model] in
            MainActor.assumeIsolated { model.map(MacsBoredMenu.content) ?? MenuPageContent() }
        }
        // Help shows the settings file in Finder, closing the dropdown first.
        let tab = MenuPageTab(model: page, help: MacsBoredHelp.content { [weak page, weak model] in
            page?.onClose()
            model?.revealConfigFile()
        })
        self.tab = tab
        tab.pages = { [weak self] name in
            MainActor.assumeIsolated { name == Self.editorPage ? self?.editorPage() : nil }
        }
        model.onEdit = { [weak self] draft in
            self?.editing = draft
            self?.tab.onOpenPage(Self.editorPage)
        }
        model.onPlanChange = { [weak self] plan, enabled in self?.onPassthroughChange?(enabled && plan.isActive) }
    }

    /// Onboarding hasn't been finished or closed yet.
    public var needsOnboarding: Bool { !model.config.setupCompleted }

    /// MacsBored's lessons, for mac++'s onboarding window. A new one each time the window opens.
    public func onboarding() -> OnboardingPart { MacsBoredOnboarding(model: model) }

    /// Whether shortcuts are being handed to an app right now.
    public var isPassingThrough: Bool { model.config.isEnabled && model.plan.isActive }

    /// Open at login, kept in MacsBored's settings file too (`openAtLogin`), so the file and the app agree.
    public func setOpenAtLogin(_ on: Bool) { model.setOpenAtLogin(on) }

    public func start() {
        model.start()
    }

    /// Gives macOS back every shortcut.
    public func stop() {
        model.stop()
    }

    /// Open the editor on a new entry on `tab` (remap, open, shortcut or passthrough; `--open-editor`).
    public func openEditor(_ tab: String) {
        model.newEntry(EntryDraft.Tab(rawValue: tab) ?? .remap)
    }

    /// The editor page's title for a new entry of this kind: "New Key Remap".
    private static func newTitle(_ tab: EntryDraft.Tab) -> String {
        switch tab {
        case .remap: "New Key Remap"
        case .open: "New Quick Open"
        case .shortcut: "New Shortcut to Run"
        case .passthrough: "New Passthrough"
        }
    }

    /// The editor, on the entry asked for (a new remap with none), as a page of the dropdown. While one
    /// of its fields records keys, every key goes to it, esc included.
    private func editorPage() -> TabbedMenuSubpage {
        let draft = editing ?? EntryDraft()
        editing = nil
        let model = model
        let state = EntryEditorState(draft: draft)
        return TabbedMenuSubpage(
            title: state.isNew ? Self.newTitle(draft.tab) : draft.name,
            content: AnyView(EntryEditor(state: state, model: model)),
            // The bar's line of what is missing comes and goes.
            changes: state.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            ownsKeys: { [weak model] in MainActor.assumeIsolated { model?.isRecording ?? false } },
            bar: AnyView(EntryEditorBar(state: state,
                                        onSave: { model.save($0, replacing: draft.origin) },
                                        onDelete: { model.delete(draft.origin) },
                                        onCancel: {})))
    }
}

/// What MacsBored's Help page says.
enum MacsBoredHelp {
    static func content(revealConfigFile: @escaping () -> Void) -> HelpContent { HelpContent(
        name: "MacsBored",
        tagline: "Your Mac's shortcuts, sent to the computer you're remoting into, and keys of your own everywhere else.",
        logo: { AnyView(MacsBoredLogo(size: $0)) },
        topics: [
            .init("arrow.right.to.line", "Passthrough",
                  "While a passthrough app (Windows App, Citrix Viewer, a virtual machine) is in front, ⌘⇥, Spotlight, ⌃←/→, the screenshot keys and the rest go to it, not your Mac. Switch to any other app and macOS has them back."),
            .init("pause.circle", "Pausing",
                  "\(MacsBoredConfig.defaultPauseKeys.displayName) gives macOS its shortcuts back in the passthrough app in front until you switch apps."),
            .init("keyboard", "Triggers",
                  "A trigger gives a key a job everywhere: remap keys, open an app, a link or a file, or run a Shortcut. Each kind has its own section; the + on its title makes one."),
            .init("doc.text", "The settings file",
                  "Everything is in one JSON file that MacsBored reloads the moment it changes, so you, a script or an AI agent can edit it. Show the settings file, below, finds it in Finder."),
        ],
        keys: [
            .init(MacsBoredConfig.defaultPauseKeys.displayName, "Pause passthrough in the app in front."),
        ],
        footnote: "Check the settings file from Terminal: \"/Applications/mac++.app/Contents/MacOS/mac++\" macsbored check",
        links: [.init("Show the settings file", action: revealConfigFile)])
    }
}
#endif
