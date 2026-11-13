#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI

/// Which page the dropdown shows, and where its nub points. Main thread only.
final class TabbedMenuModel: ObservableObject {
    let tabs: [MenuTab]
    @Published var selected: Int
    /// Where the menu-bar icon sits along the bubble's top edge, so its nub points at it.
    @Published var nubX: CGFloat?

    private static let selectedKey = "MacPlusPlusMenuTab"

    init(tabs: [MenuTab]) {
        self.tabs = tabs
        let remembered = UserDefaults.standard.string(forKey: Self.selectedKey)
        selected = tabs.firstIndex { $0.title == remembered } ?? 0
    }

    var current: MenuTab { tabs[selected] }

    func select(_ index: Int) {
        guard tabs.indices.contains(index), index != selected else { return }
        current.willHide()
        selected = index
        UserDefaults.standard.set(current.title, forKey: Self.selectedKey)
        current.refresh()
    }
}

/// Hangs the dropdown under the menu-bar icon in its own borderless panel, a bubble whose nub points
/// at the icon, and gives it a menu's manners: a click on the icon opens and closes it, a click
/// anywhere else or `esc` closes it, ⌘1, ⌘2… switch pages and ⌘Q quits. The panel takes the keyboard
/// without activating the app, so the app you were in stays in front.
public final class TabbedMenuController: NSObject, NSWindowDelegate {
    private let model: TabbedMenuModel
    private let onQuit: () -> Void
    private weak var button: NSStatusBarButton?
    private var panel: TabbedMenuPanel?
    private var monitors: [Any] = []
    private var resize: AnyCancellable?
    private var tick: Timer?

    /// The gap between the menu bar and the nub's tip, and the least distance from a screen edge.
    private static let gap: CGFloat = 3
    private static let screenMargin: CGFloat = 8

    public init(button: NSStatusBarButton, tabs: [MenuTab], onQuit: @escaping () -> Void) {
        precondition(!tabs.isEmpty, "The dropdown needs a page to show")
        model = TabbedMenuModel(tabs: tabs)
        self.onQuit = onQuit
        self.button = button
        super.init()
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        for tab in tabs { tab.onClose = { [weak self] in self?.close() } }
    }

    @objc private func toggle() {
        if panel == nil { open() } else { close() }
    }

    /// Open the dropdown, as a click on the icon does, on the page at `tab` (nil keeps the last one).
    public func show(tab: Int? = nil) {
        if let tab { model.select(tab) }
        if panel == nil { open() }
    }

    private func open() {
        guard let button, let buttonWindow = button.window else { return }
        model.current.refresh()
        // The view draws its own bubble; the panel around it is clear, and its shadow follows the bubble.
        let host = NSHostingView(rootView: TabbedMenuView(model: model))
        let panel = TabbedMenuPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
        place(panel, under: buttonWindow.frame, on: buttonWindow.screen)
        panel.makeKeyAndOrderFront(nil)
        // The button drops its highlight on mouse-up; put it back once that has happened.
        DispatchQueue.main.async { [weak self] in
            if self?.panel != nil { button.highlight(true) }
        }
        installMonitors(ignoring: buttonWindow)
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.model.current.refresh()
        }
        // A page changing, or another page chosen, changes the height: refit, holding the top edge
        // under the icon. Read after SwiftUI has laid the change out.
        let pages = Publishers.MergeMany(model.tabs.map(\.changes))
        let switches = model.$selected.dropFirst().map { _ in () }
        resize = pages.merge(with: switches).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, let panel = self.panel, let window = self.button?.window else { return }
            self.place(panel, under: window.frame, on: window.screen)
        }
    }

    public func close() {
        guard let panel else { return }
        model.current.willHide()
        self.panel = nil
        resize = nil
        tick?.invalidate()
        tick = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.delegate = nil
        panel.orderOut(nil)
        button?.highlight(false)
    }

    /// Centred under the icon, pulled in from a screen edge when the icon sits close to it; the nub
    /// still points at the icon.
    private func place(_ panel: NSPanel, under anchor: NSRect, on screen: NSScreen?) {
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        var x = anchor.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(x, visible.maxX - size.width - Self.screenMargin)
            x = max(x, visible.minX + Self.screenMargin)
        }
        if model.nubX != anchor.midX - x { model.nubX = anchor.midX - x }
        panel.setFrame(NSRect(x: x, y: anchor.minY - Self.gap - size.height, width: size.width, height: size.height),
                       display: true)
        panel.invalidateShadow()
    }

    private func installMonitors(ignoring buttonWindow: NSWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Another app's window, the desktop, another menu-bar item.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        // One of our own windows. The icon's own click is left to `toggle`.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            if let self, event.window !== self.panel, event.window !== buttonWindow { self.close() }
            return event
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.panel != nil else { return event }
            return self.handle(event) ? nil : event
        }) { monitors.append(keys) }
    }

    private func handle(_ key: NSEvent) -> Bool {
        let command = key.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        switch (key.keyCode, key.charactersIgnoringModifiers) {
        case (53, _):
            if !model.current.escape() { close() }
        case (_, "q"?) where command:
            onQuit()
        case let (_, digit?) where command:
            guard let number = Int(digit), model.tabs.indices.contains(number - 1) else { return false }
            model.select(number - 1)
        default:
            return false
        }
        return true
    }

    public func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// The dropdown: a bubble whose nub points up at the menu-bar icon, the switcher across its top
/// (each app's mark and name, the page showing picked out), then that app's page.
struct TabbedMenuView: View {
    @ObservedObject var model: TabbedMenuModel
    @State private var hovered: Int?

    private enum Metric {
        static let width: CGFloat = 372
        static let edge: CGFloat = 12
        static let corner: CGFloat = 10
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.tabs.count > 1 {
                switcher
                    .padding(.horizontal, Metric.edge)
                    .padding(.top, Metric.edge)
            }
            model.current.page()
                .id(model.selected)
        }
        .padding(.top, SpeechBubbleShape.standardNub.height)
        .frame(width: Metric.width)
        .background(SpeechBubbleShape(nubX: model.nubX).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: model.nubX).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.tabs.enumerated()), id: \.offset) { index, tab in
                let chosen = index == model.selected
                Button { model.select(index) } label: {
                    HStack(spacing: 6) {
                        tab.icon().frame(width: 16, height: 16)
                        Text(tab.title)
                            .font(.callout.weight(chosen ? .semibold : .regular))
                            .foregroundStyle(chosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background {
                        RoundedRectangle(cornerRadius: Metric.corner - 3, style: .continuous)
                            .fill(Color.primary.opacity(chosen ? 0.1 : hovered == index ? 0.05 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .help("\(tab.title) (⌘\(index + 1))")
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Borderless panels refuse the keyboard by default; this one needs `esc`, ⌘1… and ⌘Q.
private final class TabbedMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
#endif
