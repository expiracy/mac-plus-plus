#if canImport(AppKit)
import AppKit
import SwiftUI

/// The one way mac++ opens a window of its own (onboarding, MacsBored's editor): a
/// titled window with a see-through title bar that the content runs under, centred, in front. An app
/// that lives in the menu bar has no Dock icon; `showsInDock` gives it one while the window is open (as
/// onboarding does, so it can be found with ⌘⇥), and the app goes back to the menu bar once no such
/// window is left.
public final class AppWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var showsInDock = false
    /// The window closed, by its close button or `close()`.
    public var onClose: () -> Void = {}

    public override init() {
        super.init()
    }

    public var isShown: Bool { window != nil }

    /// A window of `size`, or, with `fitsContent`, one that takes the content's own size and follows it
    /// as it grows and shrinks. One already open is replaced.
    public func show<Content: View>(title: String, size: CGSize, fitsContent: Bool = false, showsInDock: Bool = false,
                                    @ViewBuilder content: () -> Content) {
        close()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: content())
        if fitsContent {
            host.sizingOptions = [.preferredContentSize]
            // The content draws its own title row under the window's buttons, so the window's size is
            // exactly the content's, with no room kept for a title bar.
            host.safeAreaRegions = []
        } else {
            // Left to size it, the controller adds the title bar's height on top of content that
            // already runs under the title bar, leaving a blank strip along the bottom.
            host.sizingOptions = []
        }
        window.contentViewController = host
        if !fitsContent { window.setContentSize(size) }
        window.center()
        window.delegate = self
        self.window = window
        self.showsInDock = showsInDock
        if showsInDock { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Bring the open window to the front.
    public func front() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func close() {
        guard let window else { return }
        window.close()   // `windowWillClose` tidies up
    }

    public func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        window?.delegate = nil
        window = nil
        if showsInDock {
            showsInDock = false
            let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeKey && $0.styleMask.contains(.titled) }
            if !others { NSApp.setActivationPolicy(.accessory) }
        }
        onClose()
    }
}
#endif
