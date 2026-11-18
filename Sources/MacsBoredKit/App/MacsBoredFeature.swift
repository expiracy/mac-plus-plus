#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsBoredCore
import MacsShared

/// MacsBored, mac++'s Actions: when something happens (keys pressed, a mouse button, an app opening,
/// a few letters typed, a time of day), it does a few things in order; and it hands macOS's own
/// shortcuts to the apps that should have them (Windows App, Citrix Viewer, a VM). The app that hosts
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
    /// The pack whose page opens next.
    private var editingPack: String?

    /// The editor's page of the dropdown.
    static let editorPage = "macsbored-entry"
    static let packPage = "macsbored-pack"
    /// The names of MacsBored's own pages of the dropdown, for pictures of them.
    public static let pages = [editorPage]
    /// MacsBored's settings page, opened from mac++'s Settings.
    static let settingsPage = "macsbored-settings"

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
        tab.pages = { [weak self, weak model, weak tab] name in
            MainActor.assumeIsolated {
                switch name {
                case Self.editorPage: self?.editorPage()
                case Self.packPage: self?.packPage()
                case Self.settingsPage: model?.settingsPage { tab?.onClose() }
                default: nil
                }
            }
        }
        tab.settingsPage = Self.settingsPage
        model.onEdit = { [weak self] draft in
            self?.editing = draft
            self?.tab.onOpenPage(Self.editorPage)
        }
        model.onEditPack = { [weak self] name in
            self?.editingPack = name
            self?.tab.onOpenPage(Self.packPage)
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

    /// Open the editor on a new action, its trigger chosen when `when` names one (`--open-editor`).
    /// Window steps, done by the Windows tool: move the window you're in to a zone by name
    /// ("leftHalf"), arrange a preset by ID, and the presets to offer, by ID and name.
    public func connectWindows(move: @escaping (String) -> Void, applyPreset: @escaping (String) -> Void,
                               presets: @escaping () -> [(id: String, name: String)]) {
        ActionRunner.moveWindow = { move($0.rawValue) }
        ActionRunner.applyPreset = applyPreset
        ActionRunner.presets = { presets().map { PresetRef(id: $0.id, name: $0.name) } }
    }

    public func openEditor(_ when: String?) {
        model.newEntry(when.flatMap(EntryDraft.When.init(rawValue:)).map { EntryDraft(whens: [$0]) } ?? EntryDraft())
    }

    /// A pack's page: its name, switch and apps, changed as they're set.
    private func packPage() -> TabbedMenuSubpage? {
        guard let name = editingPack else { return nil }
        editingPack = nil
        let model = model
        let page = PackPageState(name: name)
        return TabbedMenuSubpage(
            title: name,
            content: AnyView(PackEditor(model: model, page: page)),
            changes: model.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            bar: AnyView(PackEditorBar(onDelete: { [weak model] in model?.deletePack(page.name) })))
    }

    /// The editor, on the entry asked for (a new action with none), as a page of the dropdown. While one
    /// of its fields records keys, every key goes to it, esc included.
    private func editorPage() -> TabbedMenuSubpage {
        let draft = editing ?? EntryDraft()
        editing = nil
        let model = model
        let state = EntryEditorState(draft: draft)
        return TabbedMenuSubpage(
            title: state.isNew ? "New Action" : draft.name,
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
        tagline: "When something happens, do a few things: your own keys, clicks and routines, and your Mac's shortcuts sent to a remote computer.",
        logo: { AnyView(MacsBoredLogo(size: $0)) },
        title: "Actions",
        mark: HelpContent.symbolMark("bolt"),
        topics: [
            .init("bolt", "Actions",
                  "An action is a trigger and what it does. When you press keys, click a mouse button, open an app, type a few letters, or at a time of day, it runs its steps in order: press other keys, type text, open an app, a link or a file, run a Shortcut, or wait. + Add on the list makes one."),
            .init("arrow.right.to.line", "Sending keys to an app",
                  "Choose “An app is in front” as the trigger and pick Windows App, Citrix Viewer or a virtual machine: while it's in front, ⌘⇥, Spotlight, ⌃←/→, the screenshot keys and the rest go to it, not your Mac. Switch to any other app and macOS has them back."),
            .init("pause.circle", "Pausing",
                  "\(MacsBoredConfig.defaultPauseKeys.displayName) gives macOS its shortcuts back in the app in front until you switch apps."),
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
