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
    /// `--snapshot-notch-open`). True when one ran and the process should end.
    @MainActor public static func runDevCommand(arguments: [String]) -> Bool {
        DevMacsPaneSnapshot.runIfRequested(arguments: arguments)
            || DevMacsPaneSnapshot.recordOpenIfRequested(arguments: arguments)
    }

    /// The names of MacsPane's own pages of the dropdown, for pictures of them.
    public static let pages = [NewShortcutModel.page]
    /// MacsPane's settings page, opened from mac++'s Settings.
    static let settingsPage = "macspane-settings"

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
        // Help shows the settings file in Finder, closing the dropdown first.
        let tab = MenuPageTab(model: page, help: MacsPaneHelp.content { [weak page, weak model] in
            page?.onClose()
            model?.revealConfigFile()
        })
        tab.pages = { [weak model, weak tab] name in
            switch name {
            case NewShortcutModel.page: model?.newShortcutPage()
            case Self.settingsPage: model?.settingsPage { tab?.onClose() }
            default: nil
            }
        }
        tab.settingsPage = Self.settingsPage
        model.onOpenPage = { [weak tab] in tab?.onOpenPage($0) }
        self.tab = tab
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

    // MARK: - For MacsBored's window steps

    /// The presets, by ID and name, in the menu's order.
    public var presets: [(id: String, name: String)] { model.config.presets.map { ($0.id, $0.name) } }

    /// Arrange a preset, as clicking it in the menu does.
    public func applyPreset(_ id: String) { model.applyPreset(id) }

    /// Send the window you are in to a snap zone, by its name ("leftHalf", "maximize"); unknown names
    /// do nothing.
    public func moveFocusedWindow(toZone name: String) {
        guard let zone = WindowSnapZone(rawValue: name) else { return }
        model.moveFocusedWindow(to: zone)
    }
}

/// What MacsPane's Help page says.
enum MacsPaneHelp {
    static func content(revealConfigFile: @escaping () -> Void) -> HelpContent { HelpContent(
        name: "MacsPane",
        tagline: "Snap windows into place by dragging them to the notch.",
        logo: { AnyView(MacsPaneLogo(size: $0)) },
        title: "Windows",
        mark: HelpContent.symbolMark("rectangle.split.2x1"),
        shape: .init("What a move is made of", parts: [
            .init("hand.point.up.left", "How",
                  "What starts it: drag a window by its title bar onto the notch and let go on a box, press a shortcut in any app, or click a preset in the menu."),
            .init("macwindow", "Which windows",
                  "The window you're dragging or working in, or for a preset, a whole set of apps, opening any that are closed."),
            .init("rectangle.split.2x1", "Where",
                  "A box of a layout (a half, a third, a quarter, the whole screen, or one you draw), on the screen the window is on. A preset gives each of its apps a box of its own."),
        ], examples: [
            ["Drag to the notch", "The window", "Left half"],
            ["Press ⌃⌥→", "The window you're in", "Right half"],
            ["Click a preset", "Xcode, Terminal and Safari", "Each to its own box"],
        ], footnote: "After a move, Undo at the notch puts the windows back where they were."),
        topics: [
            .init("square.grid.2x2", "Layouts",
                  "A layout is a screen cut into boxes. The notch offers the ones switched on, in the menu's order. Add saves the windows on screen as one, or draws your own."),
            .init("square.stack.3d.up", "Presets",
                  "A preset is a set of apps and where each one goes. Add saves your desktop as one, or draws one."),
            .init("keyboard", "Shortcuts",
                  "A shortcut is keys and one place: a box of a layout, or a preset. Switch one off to let its keys through to your apps for a while."),
            .init("doc.text", "The settings file",
                  "Presets, layouts and shortcuts are all in one JSON file that MacsPane reloads the moment it changes, so you, a script or an AI agent can edit it. Show the settings file, below, finds it in Finder."),
        ],
        keys: [
            .init("⌃⌥← / ⌃⌥→", "The window in front to the left or right half, once those boxes have the keys onboarding suggests."),
        ],
        footnote: "Check the settings file from Terminal: \"/Applications/mac++.app/Contents/MacOS/mac++\" macspane check",
        links: [.init("Show the settings file", action: revealConfigFile)])
    }
}
#endif
