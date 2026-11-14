#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsBoredCore

/// `--snapshot-macsbored <dir>`: MacsBored's editor on each of its tabs and its setup's steps, drawn
/// offscreen, light and dark, over a config in a temporary file. No status item, no keyboard tap, no
/// system shortcuts touched.
enum DevMacsBoredSnapshot {
    @MainActor static func runIfRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--snapshot-macsbored"), flag + 1 < arguments.count else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.async { render(into: directory) }
        app.run()
        return true
    }

    @MainActor private static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macsbored-snapshot-\(UUID()).json")
        let model = MacsBoredModel(store: MacsBoredConfigStore(url: url))

        var drafts: [(String, EntryDraft, Bool)] = EntryDraft.Tab.allCases.map { tab in
            var draft = EntryDraft()
            draft.tab = tab
            return ("editor-\(tab.rawValue)", draft, true)
        }
        var someKeys = EntryDraft()
        someKeys.tab = .passthrough
        someKeys.passMode = .someKeys
        drafts.append(("editor-passthrough-keys", someKeys, true))
        if let profile = model.config.profiles.first {
            drafts.append(("editor-profile", EntryDraft(profile: profile), false))
        }
        var remap = EntryDraft()
        remap.keys = ["ctrl+opt+N", "hyper+N"].compactMap(KeyCombo.init(text:))
        remap.sendKeys = KeyCombo(text: "cmd+left")
        remap.onlyInApps = true
        drafts.append(("editor-remap-filled", remap, true))

        var windows: [(String, NSWindow)] = []
        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            for (name, draft, isNew) in drafts {
                let editor = EntryEditor(draft: draft, isNew: isNew, model: model,
                                         onSave: { _ in }, onDelete: {}, onCancel: {})
                    .environment(\.controlActiveState, .key)
                windows.append((name + suffix, window(NSHostingView(rootView: editor), size: nil, dark: dark)))
            }
            for step in SetupView.Step.allCases {
                let setup = SetupView(model: model, startAt: step, onDone: {})
                    .environment(\.controlActiveState, .key)
                windows.append(("setup-\(step)\(suffix)",
                                window(NSHostingView(rootView: setup), size: SetupView.size, dark: dark)))
            }
        }
        // The editor fits its form once the form has measured itself: written after a beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for (name, window) in windows {
                if let host = window.contentView, name.hasPrefix("editor") {
                    host.layoutSubtreeIfNeeded()
                    let size = host.fittingSize
                    window.setContentSize(size)
                    host.frame = NSRect(origin: .zero, size: size)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for (name, window) in windows { write(window, to: directory.appendingPathComponent("\(name).png")) }
                try? FileManager.default.removeItem(at: url)
                exit(0)
            }
        }
    }

    @MainActor private static func window(_ host: NSView, size: CGSize?, dark: Bool) -> NSWindow {
        let size = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    @MainActor private static func write(_ window: NSWindow, to url: URL) {
        guard let host = window.contentView else { return }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
