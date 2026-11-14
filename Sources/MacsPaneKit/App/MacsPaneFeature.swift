#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import MacsPaneCore
import MacsShared

/// MacsPane, mac++'s window manager. The only thing at the notch is the drag: a window dragged to the
/// top opens the snap picker there; everything else is MacsPane's page of the menu-bar dropdown,
/// which holds every setting. The app that hosts it (mac++) owns the menu-bar icon, the dropdown,
/// onboarding, Settings and Help; this is the rest: the config file, the model, the
/// notch, the box editor, the Undo prompt, and MacsPane's page, lessons and Help.
public final class MacsPaneFeature {
    /// MacsPane's page of the dropdown, with its Help.
    public let tab: MenuTab

    private let model: MacsPaneModel
    private let store: MacsPaneConfigStore
    private let editor = BoxEditorController()
    private let undoPrompt = UndoPromptController()

    /// The developer commands answered before the app starts (`--snapshot-macspane`,
    /// `--snapshot-notch-open`). True when one ran and the process should end.
    @MainActor public static func runDevCommand(arguments: [String]) -> Bool {
        DevMacsPaneSnapshot.runIfRequested(arguments: arguments)
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
        let page = MenuPageModel(brand: MacsPaneMenu.brand) { [weak model] in
            model.map(MacsPaneMenu.content) ?? MenuPageContent()
        }
        tab = MenuPageTab(model: page, help: MacsPaneHelp.content)
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
    }

    /// Onboarding hasn't been finished or closed yet.
    public var needsOnboarding: Bool { !store.config.setupCompleted }

    /// MacsPane's lessons, for mac++'s onboarding window. A new one each time the window opens.
    public func onboarding() -> OnboardingPart { MacsPaneOnboarding(app: model) }

    /// Accessibility, which moving other apps' windows needs.
    public var isAuthorized: Bool { model.isAuthorized }

    /// Ask for Accessibility: macOS's prompt, then System Settings with a guide under it.
    public func requestAccess() { model.requestAccess() }

    public func start() {
        undoPrompt.prepare()
        // A new window drag needs the notch: the Undo activity steps out of its way.
        model.notch.host.onWindowDragStart = { [weak self] in self?.undoPrompt.close() }
        model.start()
    }

    public func stop() {
        model.stop()
    }

    /// Open the box editor on a new preset, to try drawing without the menu (`--open-editor`).
    public func openEditor() { model.newPreset() }
}

/// What MacsPane's Help page says.
enum MacsPaneHelp {
    static let content = HelpContent(
        name: "MacsPane",
        tagline: "Snap windows into place by dragging them to the notch.",
        logo: { AnyView(MacsPaneLogo(size: $0)) },
        topics: [
            .init("rectangle.split.2x1", "Drag to the notch",
                  "Drag any window by its title bar to the top of the screen and hold it on the notch. Your layouts open; let go on a box and the window fills it. Hold for sets how long to wait."),
            .init("square.grid.2x2", "Layouts",
                  "The layouts the notch offers have their switch on. Drag them into the order you want by their grips, use New layout to save the windows on screen as one or draw your own, and the pencil to change one."),
            .init("square.stack.3d.up", "Presets",
                  "A preset puts a set of apps back where you like them. New preset saves your desktop as one or draws one; click it to apply it."),
            .init("keyboard", "Shortcuts",
                  "Give a layout's box or a preset keys in its editor, and they work from any app. The Shortcuts list shows them all, with a switch each."),
            .init("arrow.uturn.backward", "Undo",
                  "After a snap or a preset, a prompt at the notch offers to put the windows back where they were."),
        ],
        keys: [
            .init("⌃⌥← / ⌃⌥→", "The window in front to the left or right half, once those boxes have the keys onboarding suggests."),
        ],
        footnote: "MacsPane keeps its settings in ~/Library/Application Support/MacsPane.")
}
#endif
