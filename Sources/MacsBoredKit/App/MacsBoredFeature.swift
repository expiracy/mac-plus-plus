#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsBoredCore
import MacsShared

/// MacsBored, mac++'s keyboard half: hands macOS's own shortcuts to the apps that should have them
/// (Windows App, Citrix Viewer, a VM) and runs your own triggers everywhere else. The app that hosts
/// it (mac++) owns the menu-bar icon and the dropdown; this is the rest: the config file, the model,
/// the editors and setup. `stop()` puts every macOS shortcut back, so the host calls it on the way out.
@MainActor
public final class MacsBoredFeature {
    /// MacsBored's page of the dropdown.
    public let tab: MenuTab
    /// Opens the dropdown on MacsBored's page (after setup).
    public var onShowMenu: (() -> Void)?
    /// Whether macOS's shortcuts are being handed to an app right now; the host shows it in its icon.
    public var onPassthroughChange: ((Bool) -> Void)?
    /// Setup's window closed, finished or not.
    public var onSetupClosed: (() -> Void)?

    private let model: MacsBoredModel
    private let editor = EditorWindowController()
    private let setup = EditorWindowController()

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

    /// The menu-bar icon while shortcuts are being handed to an app: MacsBored's filled ⌘ key.
    public static func passingImage() -> NSImage? { MenuBarGlyph.image(.passing) }

    private nonisolated static var configURL: URL {
        (try? MacsBoredPaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-config.json")
    }

    public init() {
        let model = MacsBoredModel(store: MacsBoredConfigStore(url: Self.configURL,
                                                               legacyURL: try? MacsBoredPaths.legacyConfigURL()))
        self.model = model
        let menu = StatusMenuModel(name: MacsBoredMenu.name) { [weak model] in
            MainActor.assumeIsolated { model.map(MacsBoredMenu.content) ?? StatusMenuContent() }
        }
        menu.onQuit = { NSApp.terminate(nil) }
        tab = MacsBoredTab(menu: menu)
        model.onEdit = { [weak self] draft in self?.edit(draft) }
        model.onShowSetup = { [weak self] in self?.showSetup() }
        model.onPlanChange = { [weak self] plan, enabled in self?.onPassthroughChange?(enabled && plan.isActive) }
        menu.onSetup = { [weak self, weak menu] in
            menu?.onClose()
            self?.showSetup()
        }
        menu.onNew = { [weak model, weak menu] in
            menu?.onClose()
            model?.newEntry()
        }
        setup.onClose = { [weak self] in self?.onSetupClosed?() }
    }

    /// First run: setup hasn't been finished yet.
    public var needsSetup: Bool { !model.config.setupCompleted }

    /// Whether shortcuts are being handed to an app right now.
    public var isPassingThrough: Bool { model.config.passthroughEnabled && model.plan.isActive }

    public func start() {
        model.start()
    }

    /// Gives macOS back every shortcut.
    public func stop() {
        model.stop()
    }

    /// Open the editor on a new entry on `tab` (remap, open, shortcut or passthrough; `--open-editor`).
    public func openEditor(_ tab: String) {
        setup.close()
        var draft = EntryDraft()
        draft.tab = EntryDraft.Tab(rawValue: tab) ?? .remap
        edit(draft)
    }

    private func edit(_ draft: EntryDraft) {
        let model = model
        let isNew = draft.origin == .new
        editor.show(title: isNew ? "New" : draft.name, size: CGSize(width: EntryEditor.width, height: 640), fitsContent: true) {
            EntryEditor(draft: draft, isNew: isNew, model: model,
                        onSave: { [weak self] result in model.save(result, replacing: draft.origin); self?.editor.close() },
                        onDelete: { [weak self] in model.delete(draft.origin); self?.editor.close() },
                        onCancel: { [weak self] in self?.editor.close() })
        }
    }

    public func showSetup() {
        let model = model
        setup.show(title: "Set up MacsBored", size: SetupView.size) {
            SetupView(model: model) { [weak self] in
                model.completeSetup()
                self?.setup.close()
                self?.onShowMenu?()
            }
        }
    }
}

/// MacsBored's dropdown (`StatusMenuView`) as a page of mac++'s.
private final class MacsBoredTab: MenuTab {
    private let menu: StatusMenuModel

    init(menu: StatusMenuModel) {
        self.menu = menu
    }

    var title: String { menu.name }
    func icon() -> AnyView { AnyView(MacsBoredLogo(size: 16)) }
    func page() -> AnyView { AnyView(StatusMenuView(model: menu, embedded: true)) }
    func refresh() { menu.refresh() }
    var changes: AnyPublisher<Void, Never> {
        menu.$content.dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    var onClose: () -> Void {
        get { menu.onClose }
        set { menu.onClose = newValue }
    }

    func escape() -> Bool { false }
    func willHide() {}
}
#endif
