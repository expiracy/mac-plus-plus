#if canImport(AppKit)
import AppKit
import ApplicationServices
import SwiftUI
import MacsBoredKit
import MacsPaneKit
import MacsShared

/// mac++: one menu-bar app holding MacsPane (windows) and MacsBored (keys), each a page of one
/// dropdown. One boot path, shared by `swift run mac-plus-plus` and the bundled app.
///
///   macspane path | check [file] | schema    MacsPane's settings file, for scripts and agents.
///   macsbored path | check [file] | schema   MacsBored's settings file, for scripts and agents.
///   --smoke-test             Boot, then quit after ~1.5 s: a launch check.
///   --open-menu [macspane|macsbored]   Open the dropdown once launched, on that page.
///   --open-onboarding [macspane|macsbored]   Open onboarding, at that tool's lessons.
///   --open-settings          Open the dropdown on mac++'s Settings.
///   --open-help [macspane|macsbored]   Open the dropdown on that tool's Help, or on mac++'s.
///   --open-new-shortcut      Open the dropdown on MacsPane's New Shortcut page.
///   --open-editor macspane | remap|open|shortcut|passthrough   Open MacsPane's box editor, or
///                            the dropdown on MacsBored's editor, on a new entry of that kind.
///   --snapshot-menu <dir>    Write the dropdown's pages, their Help, Settings and mac++'s Help as PNGs, then quit.
///   --snapshot-windows <dir> Write every onboarding step as PNGs, then quit.
///   --export-icon <dir>      Write the app icon's faces and marks layer (for scripts/make_icon.sh).
///   --snapshot-macspane, --snapshot-notch-open   MacsPane's developer renders.
public enum MacPlusPlusApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        if let outcome = MacsBoredFeature.runCommand(arguments: arguments)
            ?? MacsPaneFeature.runCommand(arguments: arguments) {
            FileHandle.standardOutput.write(Data((outcome.output + "\n").utf8))
            exit(outcome.status)
        }
        if MainActor.assumeIsolated({ IconExport.runIfRequested(arguments: arguments) }) { return }
        if MainActor.assumeIsolated({ MacsPaneFeature.runDevCommand(arguments: arguments) }) { return }
        let app = NSApplication.shared
        // `NSApplication.delegate` is weak; `run()` never returns, so this frame keeps it alive.
        let delegate = MainActor.assumeIsolated { MacPlusPlusAppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated { delegate.runLaunchFlags(arguments) }
        }
        if arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("mac++: smoke-test OK: launched cleanly, shutting down")
                NSApp.terminate(nil)
            }
        }
        app.run()
    }
}

/// The composition root: the two tools, the one menu-bar icon and its dropdown with a page for each,
/// and what belongs to the whole app: Settings and Help (pages of the dropdown), Quit, and
/// onboarding (the one window of mac++'s own). Quitting, or a
/// TERM or INT signal, stops both tools, so MacsBored puts every macOS shortcut back first.
@MainActor
final class MacPlusPlusAppDelegate: NSObject, NSApplicationDelegate {
    private enum Page: Int, CaseIterable { case macsPane, macsBored }

    // Made once AppKit has finished launching.
    private var pane: MacsPaneFeature!
    private var bored: MacsBoredFeature!
    private var statusItem: NSStatusItem?
    private var menu: TabbedMenuController?
    private var settings: AppSettings!
    private let onboarding = OnboardingController()
    private var signalSources: [DispatchSourceSignal] = []

    private var tabs: [MenuTab] { [pane.tab, bored.tab] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        pane = MacsPaneFeature()
        bored = MacsBoredFeature()
        settings = makeSettings()
        installStatusItem()
        installSignalHandlers()
        bored.onPassthroughChange = { [weak self] _ in self?.updateIcon() }
        pane.start()
        bored.start()
        updateIcon()
        // First run, or a tool whose lessons haven't been seen: one onboarding for the whole app.
        if pane.needsOnboarding || bored.needsOnboarding { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bored?.stop()
        pane?.stop()
    }

    // MARK: - The menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        let actions = TabbedMenuActions(
            page: { [weak self] in self?.settings.page($0) },
            quit: { NSApp.terminate(nil) },
            banner: { AXIsProcessTrusted() ? nil
                : TabbedMenuBanner(title: "mac++ needs Accessibility", actionTitle: "Grant") },
            fixBanner: { [weak self] in self?.requestAccess() })
        menu = TabbedMenuController(button: button, tabs: tabs, actions: actions)
    }

    /// mac++'s apple, solid with the "++" cut out while MacsBored is handing macOS's shortcuts to an
    /// app, so it is plain from the menu bar that ⌘⇥ and the rest are going somewhere else.
    private func updateIcon() {
        let passing = bored.isPassingThrough
        statusItem?.button?.image = MacPlusPlusGlyph.templateImage(filled: passing)
        statusItem?.button?.toolTip = passing ? "mac++ · shortcuts going to the app in front" : "mac++"
    }

    // MARK: - The app's own windows

    /// mac++'s welcome and Accessibility, each tool's lessons, then the menu bar. `tool` starts at that
    /// tool's lessons (its Help's "play again").
    private func showOnboarding(at tool: Page? = nil) {
        let parts: [OnboardingPart] = [
            WelcomeOnboarding(tools: tabs, requestAccess: { [weak self] in self?.requestAccess() }),
            pane.onboarding(),
            bored.onboarding(),
            MenuBarOnboarding(tabs: tabs, showMenu: { [weak self] in self?.menu?.show() },
                              setOpenAtLogin: { [weak self] in self?.bored.setOpenAtLogin($0) }),
        ]
        onboarding.show(parts: parts, startAt: tool.map { $0.rawValue + 1 } ?? 0)
    }

    /// mac++'s Settings and Help, drawn in the dropdown. Tools in the order of their pages.
    private func makeSettings() -> AppSettings {
        AppSettings(
            tools: tabs.map(\.help),
            actions: .init(
                openPage: { [weak self] in self?.menu?.openPage($0) },
                setOpenAtLogin: { [weak self] in self?.bored.setOpenAtLogin($0) },
                setSize: { [weak self] in self?.menu?.setSize($0) },
                requestAccess: { [weak self] in self?.requestAccess() },
                replay: { [weak self] in self?.showOnboarding(at: $0.flatMap(Page.init(rawValue:))) },
                close: { [weak self] in self?.menu?.close() }))
    }

    /// Accessibility for the whole app: macOS's prompt, then System Settings with a guide under it.
    /// Both tools notice the grant by themselves.
    private func requestAccess() {
        pane.requestAccess()
    }

    /// `kill` and Ctrl-C quit through the same door as ⌘Q, so system shortcuts never stay off.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Launch flags

    func runLaunchFlags(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        func page(_ name: String?) -> Page? {
            switch name {
            case "macspane": .macsPane
            case "macsbored": .macsBored
            default: nil
            }
        }
        if arguments.contains("--open-menu") {
            menu?.show(tab: page(value(after: "--open-menu"))?.rawValue)
        }
        if arguments.contains("--open-onboarding") {
            showOnboarding(at: page(value(after: "--open-onboarding")))
        }
        if arguments.contains("--open-settings") {
            menu?.showSettings()
        }
        if arguments.contains("--open-help") {
            if let tool = page(value(after: "--open-help")) {
                menu?.show(tab: tool.rawValue)
                menu?.openPage(TabbedMenuPage.help(for: tabs[tool.rawValue].title))
            } else {
                menu?.showSettings(TabbedMenuPage.help(for: nil))
            }
        }
        if arguments.contains("--open-new-shortcut") {
            menu?.show(tab: Page.macsPane.rawValue)
            menu?.openPage(MacsPaneFeature.pages[0])
        }
        switch value(after: "--open-editor") {
        case nil: break
        case "macspane": pane.openEditor()
        case let kind?:
            menu?.show(tab: Page.macsBored.rawValue)
            bored.openEditor(kind)
        }
        if let directory = value(after: "--snapshot-menu") {
            TabbedMenuSnapshot.write(tabs: tabs, pages: { [weak self] in self?.settings.page($0) },
                                     fromSettings: [TabbedMenuPage.help(for: nil)], toolPages: MacsPaneFeature.pages + MacsBoredFeature.pages,
                                     into: URL(fileURLWithPath: directory))
            NSApp.terminate(nil)
        }
        if let directory = value(after: "--snapshot-windows") {
            snapshotWindows(into: URL(fileURLWithPath: directory))
        }
    }

    /// Every step of onboarding, written once the lessons' pictures have settled; then mac++ quits.
    private func snapshotWindows(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var shots: [(String, NSWindow)] = []
        let parts: [OnboardingPart] = [
            WelcomeOnboarding(tools: tabs, requestAccess: {}),
            pane.onboarding(), bored.onboarding(),
            MenuBarOnboarding(tabs: tabs, showMenu: {}, setOpenAtLogin: { _ in }),
        ]
        let count = parts.reduce(0) { $0 + $1.steps.count }
        for index in 0..<count {
            let model = OnboardingModel(parts: parts)
            model.current = index
            shots.append((String(format: "onboarding-%02d", index + 1),
                          OffscreenSnapshot.window(OnboardingView(model: model), size: OnboardingView.size, dark: false)))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, window) in shots {
                OffscreenSnapshot.write(window, to: directory.appendingPathComponent("\(name).png"))
            }
            parts.forEach { $0.didShow(step: nil) }
            NSApp.terminate(nil)
        }
    }
}

/// `--export-icon <dir>`: the app icon's faces (1024 px), its marks layer and the menu-bar glyph, from
/// the drawing code, for `scripts/make_icon.sh`.
enum IconExport {
    @MainActor static func runIfRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--export-icon"), flag + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 1) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
        }
        for (face, name) in [(ColorScheme.dark, "dark"), (.light, "light")] {
            write(MacPlusPlusLogo(size: 1024, iconCanvas: true, face: face), "icon-1024-\(name).png")
            write(MacPlusPlusLogo(size: 1024 * 0.72, face: face, marksOnly: true).frame(width: 1024, height: 1024),
                  "marks-\(name).png")
        }
        for filled in [false, true] {
            write(MacPlusPlusGlyph(filled: filled).frame(width: 18, height: 18).foregroundStyle(.black),
                  "glyph-menu-bar\(filled ? "-passing" : "")@2x.png", scale: 2)
        }
        return true
    }
}
#endif
