#if canImport(AppKit)
import AppKit
import SwiftUI

/// Development only: the dropdown drawn offscreen, one PNG per page in each appearance
/// (`menu-<page>-light.png`, `menu-<page>-dark.png`), to look at a change without the menu bar.
public enum TabbedMenuSnapshot {
    @MainActor public static func write(tabs: [MenuTab], into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = TabbedMenuModel(tabs: tabs)
        for index in tabs.indices {
            model.selected = index
            tabs[index].refresh()
            for dark in [false, true] {
                let root = TabbedMenuView(model: model)
                    .padding(24)
                    .background(Color(white: dark ? 0.3 : 0.7))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.controlActiveState, .key)   // the real dropdown is the key window
                let host = NSHostingView(rootView: root)
                let size = host.fittingSize
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let name = "menu-\(tabs[index].title.lowercased())-\(dark ? "dark" : "light").png"
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
                }
                window.orderOut(nil)
            }
        }
    }
}
#endif
