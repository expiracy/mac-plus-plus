#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsPaneCore
import MacsShared

/// MacsPane, mac++'s window manager. The only thing at the notch is the drag: a window dragged to the
/// top opens the snap picker there; everything else is MacsPane's page of the menu-bar dropdown,
/// which holds every setting. The app that hosts it (mac++) owns the menu-bar icon and the dropdown;
/// this is the rest: the config file, the model, the notch, the box editor, the Undo prompt and setup.
public final class MacsPaneFeature {
    /// MacsPane's page of the dropdown.
    public let tab: MenuTab
    /// Opens the dropdown on MacsPane's page (setup's Show me).
    public var onShowMenu: (() -> Void)? {
        didSet { setup.onShowMenu = onShowMenu }
    }
    /// Setup's window closed, finished or not.
    public var onSetupClosed: (() -> Void)? {
        didSet { setup.onDidClose = onSetupClosed }
    }

    private let model: MacsPaneModel
    private let store: MacsPaneConfigStore
    private let setup = MacsPaneSetupController()
    private let editor = BoxEditorController()
    private let undoPrompt = UndoPromptController()

    /// The menu-bar icon mac++ wears: MacsPane's mark, as a template image.
    public static func menuBarImage() -> NSImage { MacsPaneGlyph.templateImage() }

    /// The settings file's commands for scripts and agents, answered before the app starts:
    /// `macspane path`, `macspane check [file]`, `macspane schema` (after the program's own path).
    /// Nil when `arguments` are the app's own.
    public nonisolated static func runCommand(arguments: [String]) -> (output: String, status: Int32)? {
        let rest = Array(arguments.dropFirst())
        guard rest.first == "macspane" else { return nil }
        let url = (try? MacsPanePaths.configURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("macspane-config.json")
        return MacsPaneConfigCommand.run(Array(rest.dropFirst()), defaultURL: url)
            ?? ("usage: macspane path | check [file] | schema", 64)
    }

    /// The developer commands answered before the app starts (`--snapshot-macspane`,
    /// `--snapshot-notch-open`, `--export-icon`). True when one ran and the process should end.
    @MainActor public static func runDevCommand(arguments: [String]) -> Bool {
        DevMacsPaneSnapshot.exportIconIfRequested(arguments: arguments)
            || DevMacsPaneSnapshot.runIfRequested(arguments: arguments)
            || DevMacsPaneSnapshot.recordOpenIfRequested(arguments: arguments)
    }

    public init() {
        if let url = try? MacsPanePaths.configURL() {
            store = MacsPaneConfigStore(url: url)
        } else {
            // No Application Support: run on defaults rather than not at all (nothing will persist).
            store = MacsPaneConfigStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("macspane-config.json"))
        }
        let model = MacsPaneModel(store: store)
        self.model = model
        let menu = StatusMenuModel(brand: MacsPaneMenu.brand) { [weak model] in
            model.map(MacsPaneMenu.content) ?? StatusMenuContent()
        }
        menu.onQuit = { NSApp.terminate(nil) }
        tab = MacsPaneTab(menu: menu)
        model.onShowSetup = { [weak self] in self?.showSetup() }
        model.onEdit = { [weak self, weak model] draft in
            guard let model else { return }
            self?.editor.show(draft, app: model)
        }
        model.onUndoPrompt = { [weak self, weak model] action in
            self?.undoPrompt.show(title: action.title, symbol: action.symbol, glyph: action.glyph,
                                  on: MacsPaneModel.pointerScreen) { done in
                guard let model else { return done() }
                model.perform(action, done: done)
            }
        }
        menu.onSetup = { [weak self, weak menu] in
            menu?.onClose()
            self?.showSetup()
        }
    }

    /// First run: setup hasn't been finished or closed yet.
    public var needsSetup: Bool { !store.config.setupCompleted }

    public func start() {
        undoPrompt.prepare()
        // A new window drag needs the notch: the Undo activity steps out of its way.
        model.notch.host.onWindowDragStart = { [weak self] in self?.undoPrompt.close() }
        model.start()
    }

    public func stop() {
        model.stop()
    }

    /// The setup window asks for Accessibility in its own step; afterwards the dropdown's warning
    /// carries the Grant button.
    public func showSetup() {
        setup.show(app: model)
    }

    /// Open the box editor on a new preset, to try drawing without the menu (`--open-editor`).
    public func openEditor() { model.newPreset() }
}

/// MacsPane's dropdown (`StatusMenuView`) as a page of mac++'s.
private final class MacsPaneTab: MenuTab {
    private let menu: StatusMenuModel

    init(menu: StatusMenuModel) {
        self.menu = menu
    }

    var title: String { menu.brand.name }
    func icon() -> AnyView { AnyView(MacsPaneLogo(size: 16)) }
    func page() -> AnyView { AnyView(StatusMenuView(model: menu, embedded: true)) }
    func refresh() { menu.refresh() }
    var changes: AnyPublisher<Void, Never> {
        menu.$content.dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    var onClose: () -> Void {
        get { menu.onClose }
        set { menu.onClose = newValue }
    }

    func escape() -> Bool {
        if menu.content.renaming != nil {
            menu.finishRename(cancel: true)
        } else if menu.openSubmenu != nil {
            menu.openSubmenu = nil
        } else {
            return false
        }
        return true
    }

    func willHide() {
        menu.finishRename()   // a name being typed in place is kept
        menu.openSubmenu = nil
    }
}
#endif
