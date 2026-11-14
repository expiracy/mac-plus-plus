#if canImport(AppKit)
import AppKit
import SwiftUI

/// Development only: the dropdown drawn offscreen, to look at a change without the menu bar: each
/// tool's page in each appearance (`menu-<tool>-light.png`, `menu-<tool>-dark.png`) and its Help
/// (`menu-help-<tool>-…`) and any of its own pages named in `toolPages`, then Settings and each page named in `fromSettings` as it opens from it
/// (`menu-settings-…`, `menu-settings-<page>-…`).
public enum TabbedMenuSnapshot {
    @MainActor public static func write(tabs: [MenuTab], banner: TabbedMenuBanner? = nil,
                                        pages: @escaping (String) -> TabbedMenuSubpage? = { _ in nil },
                                        fromSettings: [String] = [], toolPages: [String] = [],
                                        into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var actions = TabbedMenuActions.inert
        actions.banner = { banner }
        actions.page = pages
        let model = TabbedMenuModel(tabs: tabs, actions: actions)
        model.picture = true
        func shoot(_ name: String) {
            for dark in [false, true] {
                let root = TabbedMenuView(model: model).padding(24).background(Color(white: dark ? 0.3 : 0.7))
                let window = OffscreenSnapshot.window(root, size: nil, dark: dark)
                OffscreenSnapshot.write(window, to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
                window.orderOut(nil)
            }
        }
        for index in tabs.indices {
            model.select(index)
            tabs[index].refresh()
            shoot("menu-\(tabs[index].title.lowercased())")
            // Its Help, from the ? beside its name.
            let help = TabbedMenuPage.help(for: tabs[index].title)
            if pages(help) != nil {
                model.open(help)
                shoot("menu-\(help)")
                model.back(to: 0)
            }
            // The tool's own pages named in `toolPages` (`menu-<page>-…`).
            for name in toolPages where tabs[index].subpage(name) != nil {
                model.open(name)
                shoot("menu-\(name)")
                model.back(to: 0)
            }
        }
        model.open(TabbedMenuPage.settings)
        shoot("menu-settings")
        for name in fromSettings {
            model.open(name)
            shoot("menu-settings-\(name)")
            model.back(to: 1)
        }
        model.back(to: 0)
    }
}

/// Development only: any view drawn in an offscreen window and written as a PNG.
public enum OffscreenSnapshot {
    /// `view` in a borderless window off the screen, at `size` (nil: the view's own), drawn as the
    /// front window draws its controls.
    @MainActor public static func window<V: View>(_ view: V, size: CGSize?, dark: Bool) -> NSWindow {
        let root = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key)
        let host = NSHostingView(rootView: root)
        let size = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    @MainActor public static func write(_ window: NSWindow, to url: URL) {
        guard let host = window.contentView else { return }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
