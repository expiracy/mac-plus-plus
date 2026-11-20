#if canImport(AppKit)
import AppKit
import MacsBoredCore

/// Does what an action says, step by step: presses other keys, types text, opens an app, a link or
/// a file, runs one of Apple's Shortcuts or a script, moves windows, chooses a menu item, or waits. Passing keys through
/// is the keyboard tap's job, so it never reaches here.
@MainActor
enum ActionRunner {
    /// What the Windows tool does for window steps, set by the app that holds both tools: move the
    /// window you're in, and arrange a preset by its ID. Unset, those steps beep.
    static var moveWindow: ((WindowPlace) -> Void)?
    static var applyPreset: ((String) -> Void)?
    /// The Windows tool's presets, for the editor to offer.
    static var presets: () -> [PresetRef] = { [] }

    /// The steps in order, with a moment between each so an app just opened is ready for the next.
    /// A script is waited for, so what it does is done before the next step.
    static func run(_ steps: [TriggerAction]) {
        Task { @MainActor in
            for (index, step) in steps.enumerated() {
                if case let .wait(seconds) = step {
                    try? await Task.sleep(for: .seconds(seconds))
                    continue
                }
                if index > 0 { try? await Task.sleep(for: .milliseconds(150)) }
                if case let .runScript(script) = step {
                    await run(script)
                    continue
                }
                run(step)
            }
        }
    }

    static func run(_ action: TriggerAction) {
        switch action {
        case let .sendKeys(keys):
            press(keys)
        case let .openApp(app):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
                NSSound.beep(); return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case let .open(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let url = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
                ? URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                : URL(string: trimmed)
            guard let url else { NSSound.beep(); return }
            NSWorkspace.shared.open(url)
        case let .runShortcut(name):
            runShortcut(name)
        case let .typeText(text):
            type(text)
        case let .runScript(script):
            Task { await run(script) }
        case let .moveWindow(place):
            if let moveWindow { moveWindow(place) } else { NSSound.beep() }
        case let .applyPreset(preset):
            if let applyPreset { applyPreset(preset.id) } else { NSSound.beep() }
        case let .chooseMenuItem(path):
            // The app in front: the one the keys were pressed in.
            guard let app = NSWorkspace.shared.frontmostApplication,
                  AppMenus.choose(path, pid: app.processIdentifier) else { NSSound.beep(); return }
        case .passThrough, .wait:
            break
        }
    }

    /// A shell script in zsh, or an AppleScript, run in the background; done when it finishes. A
    /// script that fails beeps. Homebrew's folders are on the shell's path, as in Terminal.
    static func run(_ script: Script) async {
        let process = Process()
        switch script.language {
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", script.source]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
                .joined(separator: ":")
            process.environment = environment
        case .appleScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script.source]
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32? = await withCheckedContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { process.terminationHandler = nil; done.resume(returning: nil) }
        }
        if status != 0 { NSSound.beep() }
    }

    /// The text as key presses carrying the characters themselves, so it types the same whatever the
    /// keyboard layout. macOS takes up to 20 characters an event.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var units = Array(text.utf16)[...]
        while !units.isEmpty {
            let chunk = Array(units.prefix(20))
            units = units.dropFirst(chunk.count)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                event.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.ownEventTag)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// The Shortcuts app's own command line, in the background.
    static func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 { DispatchQueue.main.async { NSSound.beep() } }
        }
        do { try process.run() } catch { NSSound.beep() }
    }

    /// The names of your Shortcuts, as the Shortcuts app lists them.
    nonisolated static func shortcutNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// The keys pressed and let go, with exactly their modifiers, whatever is physically held.
    static func press(_ keys: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keys.keyCode, keyDown: down) else { continue }
            event.flags = CGEventFlags(rawValue: FlagBits.rewrite(0, to: keys.modifiers, swapping: nil))
            event.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.ownEventTag)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
#endif
