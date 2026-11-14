#if canImport(AppKit)
import AppKit
import MacsBoredKit
import MacsPaneKit
import MacsShared

/// mac++: one menu-bar app holding MacsPane (windows) and MacsBored (keys), each a page of one
/// dropdown. One boot path, shared by `swift run mac-plus-plus` and the bundled app.
///
///   macsbored path | check [file] | schema   MacsBored's config file, for scripts and agents.
///   --smoke-test             Boot, then quit after ~1.5 s: a launch check.
///   --open-menu [macspane|macsbored]   Open the dropdown once launched, on that page.
///   --open-setup macspane|macsbored    Open that app's first-time setup.
///   --open-editor macspane | remap|open|shortcut|passthrough   Open MacsPane's box editor, or
///                            MacsBored's editor on a new entry on that tab.
///   --snapshot-menu <dir>    Write the dropdown's pages as PNGs, then quit.
///   --snapshot-macspane, --snapshot-notch-open, --export-icon   MacsPane's developer renders.
///   --snapshot-macsbored <dir>   MacsBored's editor tabs and setup steps as PNGs.
public enum MacPlusPlusApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        if let outcome = MacsBoredFeature.runCommand(arguments: arguments) {
            FileHandle.standardOutput.write(Data((outcome.output + "\n").utf8))
            exit(outcome.status)
        }
        if MainActor.assumeIsolated({ MacsPaneFeature.runDevCommand(arguments: arguments) }) { return }
        if MainActor.assumeIsolated({ MacsBoredFeature.runDevCommand(arguments: arguments) }) { return }
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

/// The composition root: the two apps, the one menu-bar icon and its dropdown with a page for each,
/// and first-run setup, one app after the other. Quitting, or a TERM or INT signal, stops both apps,
/// so MacsBored puts every macOS shortcut back first.
@MainActor
final class MacPlusPlusAppDelegate: NSObject, NSApplicationDelegate {
    private enum Page: Int { case macsPane, macsBored }

    // Made once AppKit has finished launching, as each app made its own.
    private var pane: MacsPaneFeature!
    private var bored: MacsBoredFeature!
    private var statusItem: NSStatusItem?
    private var menu: TabbedMenuController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        pane = MacsPaneFeature()
        bored = MacsBoredFeature()
        installStatusItem()
        installSignalHandlers()
        pane.onShowMenu = { [weak self] in self?.menu?.show(tab: Page.macsPane.rawValue) }
        bored.onShowMenu = { [weak self] in self?.menu?.show(tab: Page.macsBored.rawValue) }
        bored.onPassthroughChange = { [weak self] _ in self?.updateIcon() }
        pane.start()
        bored.start()
        updateIcon()
        // First run: one setup at a time, MacsPane's then MacsBored's, rather than two windows at once.
        if pane.needsSetup {
            pane.onSetupClosed = { [weak self] in
                guard let self else { return }
                self.pane.onSetupClosed = nil
                if self.bored.needsSetup { self.bored.showSetup() }
            }
            pane.showSetup()
        } else if bored.needsSetup {
            bored.showSetup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bored?.stop()
        pane?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.toolTip = "mac++"
        menu = TabbedMenuController(button: button, tabs: [pane.tab, bored.tab]) { NSApp.terminate(nil) }
    }

    /// MacsPane's mark, or MacsBored's filled ⌘ key while it is handing macOS's shortcuts to an app,
    /// so it is plain from the menu bar that ⌘⇥ and the rest are going somewhere else.
    private func updateIcon() {
        let passing = bored.isPassingThrough ? MacsBoredFeature.passingImage() : nil
        statusItem?.button?.image = passing ?? MacsPaneFeature.menuBarImage()
        statusItem?.button?.toolTip = bored.isPassingThrough ? "mac++ · shortcuts going to the app in front" : "mac++"
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

    func runLaunchFlags(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if arguments.contains("--open-menu") {
            menu?.show(tab: value(after: "--open-menu") == "macsbored" ? Page.macsBored.rawValue
                : value(after: "--open-menu") == "macspane" ? Page.macsPane.rawValue : nil)
        }
        switch value(after: "--open-setup") {
        case "macspane": pane.showSetup()
        case "macsbored": bored.showSetup()
        default: break
        }
        switch value(after: "--open-editor") {
        case nil: break
        case "macspane": pane.openEditor()
        case let tab?: bored.openEditor(tab)
        }
        if let directory = value(after: "--snapshot-menu") {
            TabbedMenuSnapshot.write(tabs: [pane.tab, bored.tab], into: URL(fileURLWithPath: directory))
            NSApp.terminate(nil)
        }
    }
}
#endif
