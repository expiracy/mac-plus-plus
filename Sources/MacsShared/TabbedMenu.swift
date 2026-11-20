#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI

/// Something wrong with the whole app, shown above every page with its one fix
/// ("mac++ needs Accessibility" · Grant).
public struct TabbedMenuBanner: Equatable {
    public var title: String
    public var detail: String?
    public var actionTitle: String

    public init(title: String, detail: String? = nil, actionTitle: String) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
    }
}

/// A page the dropdown opens over a tool's page, in the same space: its title (in the navigation
/// bar, and on the back button of a page opened from it), what it draws, how to read it again (once a
/// second while it shows), and when it changes height.
public struct TabbedMenuSubpage {
    public var title: String
    public var content: AnyView
    public var refresh: () -> Void
    public var changes: AnyPublisher<Void, Never>
    /// A key pressed while the page is on top, before the dropdown's own keys (esc, ⌘1…): true when
    /// the page used it (a shortcut being recorded).
    public var keyDown: ((NSEvent) -> Bool)?
    /// True while the page's own controls take every key (a key recorder listening): the dropdown
    /// then leaves keys alone, esc included.
    public var ownsKeys: () -> Bool
    /// A bar kept in view under the page however far it scrolls (an editor's Cancel and Save).
    public var bar: AnyView?

    public init(title: String, content: AnyView, refresh: @escaping () -> Void = {},
                changes: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
                keyDown: ((NSEvent) -> Bool)? = nil, ownsKeys: @escaping () -> Bool = { false },
                bar: AnyView? = nil) {
        self.title = title
        self.content = content
        self.refresh = refresh
        self.changes = changes
        self.keyDown = keyDown
        self.ownsKeys = ownsKeys
        self.bar = bar
    }
}



/// How big the dropdown is drawn, everything in it scaled alike (Settings' Size).
public enum MenuSize: Int, CaseIterable, Sendable {
    case small, standard, large, larger

    public var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    public var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        }
    }

    private static let key = "MacPlusPlusMenuSize"

    /// The size chosen, remembered across launches.
    public static var current: MenuSize {
        get { (UserDefaults.standard.object(forKey: key) as? Int).flatMap(MenuSize.init(rawValue:)) ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// What the dropdown's app-wide parts do: the footer's Settings and Quit, and the banner.
public struct TabbedMenuActions {
    /// The page of this name, drawn in the dropdown: `TabbedMenuPage.settings` is the one the footer's
    /// Settings opens; `TabbedMenuPage.help(for:)` names each Help.
    public var page: (String) -> TabbedMenuSubpage?
    public var quit: () -> Void
    /// The app-wide problem to show now, if any; read whenever the pages are.
    public var banner: () -> TabbedMenuBanner?
    public var fixBanner: () -> Void

    public init(page: @escaping (String) -> TabbedMenuSubpage?, quit: @escaping () -> Void,
                banner: @escaping () -> TabbedMenuBanner? = { nil }, fixBanner: @escaping () -> Void = {}) {
        self.page = page
        self.quit = quit
        self.banner = banner
        self.fixBanner = fixBanner
    }

    /// Actions that do nothing, for a picture of the dropdown.
    static var inert: TabbedMenuActions {
        TabbedMenuActions(page: { _ in nil }, quit: {})
    }
}

/// A page opened over a tool's page (Settings, or a Help), in the stack of pages over it.
public struct TabbedMenuPage: Identifiable {
    /// The name of the page the footer's Settings opens.
    public static let settings = "settings"

    /// The name of the Help page of the tool called `tool` (the ? beside its name on its page), or
    /// with nil, of mac++ itself (the ? beside mac++ in Settings).
    public static func help(for tool: String?) -> String {
        tool.map { "help-\($0.lowercased())" } ?? "help"
    }

    public let id = UUID()
    let name: String
    let subpage: TabbedMenuSubpage
    var title: String { subpage.title }
}

/// Which page the dropdown shows, and where its nub points. Main thread only.
final class TabbedMenuModel: ObservableObject {
    let tabs: [MenuTab]
    var actions: TabbedMenuActions
    @Published var selected: Int
    /// Where the menu-bar icon sits along the bubble's top edge, so its nub points at it.
    @Published var nubX: CGFloat?
    @Published private(set) var banner: TabbedMenuBanner?
    /// Pages opened over the tool's page, deepest last; empty shows the tool's page itself.
    @Published private(set) var stack: [TabbedMenuPage] = []
    /// Drawn as a picture (onboarding's): nothing in it is remembered or acts.
    var picture = false
    /// How much the dropdown is scaled by (`MenuSize`); the view lays out at 1 and the panel scales it.
    @Published var scale: CGFloat = MenuSize.current.scale
    /// The height of the page on top of the stack, as last laid out, so the dropdown refits as it
    /// grows and shrinks.
    @Published var subpageHeight: CGFloat = 0
    /// The whole dropdown's size, as last laid out (at the Size chosen): the panel is fitted to it,
    /// and anything that changes it refits the panel. Zero until it is first laid out.
    @Published var contentSize: CGSize = .zero
    /// Runs something that leaves the dropdown for a moment (a file chooser) with the dropdown out of
    /// its way, and brings it back after; set by the controller.
    var stepAway: (() -> Void) -> Void = { $0() }

    private static let selectedKey = "MacPlusPlusMenuTab"

    init(tabs: [MenuTab], actions: TabbedMenuActions) {
        self.tabs = tabs
        self.actions = actions
        let remembered = UserDefaults.standard.string(forKey: Self.selectedKey)
        selected = tabs.firstIndex { $0.title == remembered } ?? 0
        banner = actions.banner()
    }

    var current: MenuTab { tabs[selected] }

    /// Read the page showing and the banner again.
    func refresh() {
        if let top = stack.last { top.subpage.refresh() } else { current.refresh() }
        let now = actions.banner()
        if now != banner { banner = now }
    }

    /// Open the page called `name` over what shows now: the showing tool's own, another tool's (its
    /// settings, from Settings) or the app's; one already open under it is gone back to instead.
    func open(_ name: String) {
        if let index = stack.firstIndex(where: { $0.name == name }) { back(to: index + 1); return }
        guard let subpage = current.subpage(name) ?? tabs.lazy.compactMap({ $0.subpage(name) }).first
                ?? actions.page(name) else { return }
        if stack.isEmpty { current.willHide() }
        subpage.refresh()
        stack.append(TabbedMenuPage(name: name, subpage: subpage))
    }

    /// Back to the page at `depth` (0 is the tool's page).
    func back(to depth: Int) {
        guard depth < stack.count else { return }
        stack = Array(stack.prefix(max(0, depth)))
        if stack.isEmpty { current.refresh() } else { stack.last?.subpage.refresh() }
    }

    func select(_ index: Int) {
        if !stack.isEmpty { back(to: 0) }
        guard tabs.indices.contains(index), index != selected else { return }
        current.willHide()
        selected = index
        if !picture { UserDefaults.standard.set(current.title, forKey: Self.selectedKey) }
        current.refresh()
    }
}

/// Hangs the dropdown under the menu-bar icon in its own borderless panel, a bubble whose nub points
/// at the icon, and gives it a menu's manners: a click on the icon opens and closes it, a click
/// anywhere else or `esc` closes it (or goes back, on a page opened over a tool's), ⌘1, ⌘2… switch
/// pages, ⌘, opens Settings and ⌘Q quits. Settings and Help open in the dropdown itself, over
/// the tool's page, with a back button. The panel takes the keyboard without activating the app, so the
/// app you were in stays in front.
public final class TabbedMenuController: NSObject, NSWindowDelegate {
    private let model: TabbedMenuModel
    private weak var button: NSStatusBarButton?
    private var panel: TabbedMenuPanel?
    /// The dropdown's view, the panel's content view.
    private var host: NSView?
    private var monitors: [Any] = []
    private var resize: AnyCancellable?
    private var pageResize: AnyCancellable?
    /// Retakes the panel's shadow while the bubble animates (`followShadow`).
    private var shadowTimer: Timer?
    private var tick: Timer?

    /// The gap between the menu bar and the nub's tip, and the least distance from a screen edge.
    private static let gap: CGFloat = 3
    private static let screenMargin: CGFloat = 8

    public init(button: NSStatusBarButton, tabs: [MenuTab], actions: TabbedMenuActions) {
        precondition(!tabs.isEmpty, "The dropdown needs a page to show")
        var actions = actions
        // What leaves the dropdown (System Settings) closes it first.
        let fix = actions.fixBanner
        model = TabbedMenuModel(tabs: tabs, actions: actions)
        self.button = button
        super.init()
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        for tab in tabs {
            tab.onClose = { [weak self] in self?.close() }
            tab.onOpenPage = { [weak self] in self?.model.open($0) }
        }
        model.stepAway = { [weak self] work in self?.stepAway(work) ?? work() }
        actions.fixBanner = { [weak self] in self?.close(); fix() }
        model.actions = actions
    }

    /// The page showing now.
    public var selectedTab: Int { model.selected }

    /// Draw the dropdown at `size` from now on, refitting it if it is open.
    public func setSize(_ size: MenuSize) {
        MenuSize.current = size
        model.scale = size.scale
        refit()
    }

    @objc private func toggle() {
        if panel == nil { open() } else { close() }
    }

    /// Open the dropdown, as a click on the icon does, on the page at `tab` (nil keeps the last one).
    public func show(tab: Int? = nil) {
        if let tab { model.select(tab) }
        if panel == nil { open() }
    }

    /// Open the dropdown on mac++'s Settings, or on the page called `page` with Settings under it.
    public func showSettings(_ page: String? = nil) {
        if panel == nil { open() }
        model.open(TabbedMenuPage.settings)
        if let page { model.open(page) }
    }

    /// Open the page called `name` (a Help) over the page showing.
    public func openPage(_ name: String) {
        model.open(name)
    }

    private func open() {
        guard let button, let buttonWindow = button.window else { return }
        model.refresh()
        // The view draws its own bubble; the panel around it is clear, and its shadow follows the bubble.
        model.contentSize = .zero
        let host = NSHostingView(rootView: ScaledMenuView(model: model))
        let panel = TabbedMenuPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        self.host = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel
        place(panel, under: buttonWindow.frame, on: buttonWindow.screen)
        // From here the panel is sized and placed only by `place`. Left to the hosting view, a change
        // of height would resize it from its bottom edge, moving the bubble.
        host.sizingOptions = []
        panel.makeKeyAndOrderFront(nil)
        // The button drops its highlight on mouse-up; put it back once that has happened.
        DispatchQueue.main.async { [weak self] in
            if self?.panel != nil { button.highlight(true) }
        }
        installMonitors(ignoring: buttonWindow)
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
        // A page changing, or another page chosen, changes the height: refit, holding the top edge
        // under the icon. Read after SwiftUI has laid the change out.
        let pages = Publishers.MergeMany(model.tabs.map(\.changes))
            .merge(with: model.$subpageHeight.removeDuplicates().dropFirst().map { _ in () })
            .merge(with: model.$contentSize.removeDuplicates().dropFirst().map { _ in () })
        let switches = model.$selected.dropFirst().map { _ in () }
        let banners = model.$banner.dropFirst().map { _ in () }
        let stack = model.$stack.dropFirst().map { [weak self] stack -> Void in
            // Follow the page on top of the stack as well, for as long as it is there.
            self?.pageResize = stack.last?.subpage.changes.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.refit()
            }
        }
        resize = pages.merge(with: switches, banners, stack).receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refit()
        }
    }

    private func refit() {
        guard let panel, let window = button?.window else { return }
        place(panel, under: window.frame, on: window.screen)
    }

    public func close() {
        guard let panel else { return }
        if model.stack.isEmpty { model.current.willHide() }
        self.panel = nil
        host = nil
        resize = nil
        pageResize = nil
        shadowTimer?.invalidate()
        shadowTimer = nil
        // Opened again, the dropdown shows the tool's page, not a page left open over it.
        model.back(to: 0)
        tick?.invalidate()
        tick = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.delegate = nil
        panel.orderOut(nil)
        button?.highlight(false)
    }

    /// Centred under the icon, pulled in from a screen edge when the icon sits close to it; the nub
    /// still points at the icon. The panel runs from under the icon to the foot of the screen,
    /// clear below the bubble, so it keeps its place and size as the bubble grows and shrinks inside
    /// it: the bubble's top never moves. It changes only if the bubble gets wider (the Size chosen)
    /// or taller than the screen.
    private func place(_ panel: NSPanel, under anchor: NSRect, on screen: NSScreen?) {
        guard let host else { return }
        // Already at the Size chosen (`ScaledMenuView`). As SwiftUI last laid it out; before that
        // (opening), as the hosting view measures it.
        let size = model.contentSize == .zero ? host.fittingSize : model.contentSize
        let scale = model.scale
        var x = anchor.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(x, visible.maxX - size.width - Self.screenMargin)
            x = max(x, visible.minX + Self.screenMargin)
        }
        // The nub is drawn in the view's own (unscaled) points.
        let nub = (anchor.midX - x) / scale
        if model.nubX != nub { model.nubX = nub }
        let top = anchor.minY - Self.gap
        let room = screen.map { top - $0.visibleFrame.minY } ?? size.height
        let height = max(size.height, room)
        let frame = NSRect(x: x, y: top - height, width: size.width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        followShadow(panel)
    }

    /// The panel's shadow is taken from what it draws, so it is taken again each frame while the
    /// bubble animates to its new size.
    private func followShadow(_ panel: NSPanel) {
        shadowTimer?.invalidate()
        panel.invalidateShadow()
        let until = Date().addingTimeInterval(0.4)
        shadowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak panel] timer in
            panel?.invalidateShadow()
            if Date() > until { timer.invalidate() }
        }
    }

    /// Whether a click in the panel fell on its clear part, under the bubble.
    private func isUnderBubble(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel, model.contentSize != .zero else { return false }
        return event.locationInWindow.y < panel.frame.height - model.contentSize.height
    }

    private func installMonitors(ignoring buttonWindow: NSWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Another app's window, the desktop, another menu-bar item.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        // One of our own windows. The icon's own click is left to `toggle`.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            // The panel's clear part under the bubble counts as outside it.
            if let self, !self.away, event.window !== buttonWindow,
               event.window !== self.panel || self.isUnderBubble(event) { self.close() }
            return event
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.panel != nil, !self.away else { return event }
            if self.model.stack.last?.subpage.ownsKeys() == true { return event }
            return self.handle(event) ? nil : event
        }) { monitors.append(keys) }
    }

    /// Out of the way of a file chooser, say: hidden, and not closed by the chooser taking the
    /// keyboard or its clicks. The dropdown comes back as it was once `work` (modal) is done.
    private var away = false

    private func stepAway(_ work: () -> Void) {
        guard let panel, !away else { return work() }
        away = true
        panel.orderOut(nil)
        work()
        away = false
        guard self.panel === panel else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    private func handle(_ key: NSEvent) -> Bool {
        if model.stack.last?.subpage.keyDown?(key) == true { return true }
        let command = key.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        switch (key.keyCode, key.charactersIgnoringModifiers) {
        case (53, _):
            if !model.stack.isEmpty { model.back(to: model.stack.count - 1) }
            else if !model.current.escape() { close() }
        case (_, "q"?) where command:
            model.actions.quit()
        case (_, ","?) where command:
            model.open(TabbedMenuPage.settings)
        case let (_, digit?) where command:
            guard let number = Int(digit), model.tabs.indices.contains(number - 1) else { return false }
            model.select(number - 1)
        default:
            return false
        }
        return true
    }


    public func windowDidResignKey(_ notification: Notification) {
        if !away { close() }
    }
}

/// The dropdown at the Size chosen: laid out at its own size, then drawn (and clicked) scaled from its
/// top-left corner, taking the scaled size.
struct ScaledMenuView: View {
    @ObservedObject var model: TabbedMenuModel

    var body: some View {
        ScaledLayout(scale: model.scale) {
            TabbedMenuView(model: model).scaleEffect(model.scale, anchor: .topLeading)
        }
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                if model.contentSize != size { model.contentSize = size }
            }
        })
        // Held to the panel's top, under the icon: the panel runs to the foot of the screen, clear
        // below the bubble.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Its one child at the child's own size, reporting that size times `scale`.
private struct ScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(child.sizeThatFits(.unspecified)))
    }
}

/// The dropdown: a bubble whose nub points up at the menu-bar icon, the switcher across its top
/// (each tool's mark and name, the page showing picked out), any app-wide warning, that tool's page,
/// then the footer that belongs to the whole app: Settings and Quit mac++.
/// Settings, Help and a tool's own pages open in the same space, a navigation bar in the switcher's
/// place and no footer: back is the way out, and ⌘, and ⌘Q still work.
struct TabbedMenuView: View {
    @ObservedObject var model: TabbedMenuModel
    @State private var hovered: Int?

    private enum Metric {
        static let width: CGFloat = 440
        static let edge: CGFloat = 12
        static let corner: CGFloat = 10
        /// The band across the top (the tabs, or the navigation bar) and the gap over it: one
        /// height for both, so its hairline stays put as the pages change.
        static let barHeight: CGFloat = 38
        static let barTop: CGFloat = 6
    }

    /// The tallest a page opened over a tool's page draws before it scrolls: the screen's height,
    /// less the navigation bar and page header (about 110 pt), the nub and a margin, in the view's own
    /// points at the Size chosen.
    private var subpageMaxHeight: CGFloat {
        max(300, ((NSScreen.main?.visibleFrame.height ?? 800) - 165) / model.scale)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let top = model.stack.last {
                topBar { subpageHeader(top) }
                // Drawn edge to edge, as a tool's page is: each page keeps its own margin. Its own
                // height, until that would run the dropdown off the screen; then it scrolls.
                ScrollView {
                    top.subpage.content
                        .environment(\.closePage) { model.back(to: model.stack.count - 1) }
                        .environment(\.stepAway, model.stepAway)
                        .background(GeometryReader { proxy in
                            Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                                model.subpageHeight = height
                            }
                        })
                }
                    .scrollBounceBehavior(.basedOnSize)
                    // A page's bar takes its room from the page's.
                    .frame(maxHeight: subpageMaxHeight - (top.subpage.bar == nil ? 0 : 60))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(top.id)
                if let bar = top.subpage.bar {
                    Divider()
                    bar
                        .environment(\.closePage) { model.back(to: model.stack.count - 1) }
                        .padding(Metric.edge)
                }
            } else {
                masthead
                if let banner = model.banner {
                    bannerCard(banner)
                        .padding(.horizontal, Metric.edge)
                        .padding(.top, Metric.edge)
                }
                model.current.page()
                    .environment(\.openHelp) { model.open(TabbedMenuPage.help(for: model.current.title)) }
                    .id(model.selected)
                    // Over the footer, so a row's choices bubble that runs past the page isn't drawn under it.
                    .zIndex(1)
                footer
            }
        }
        .padding(.top, SpeechBubbleShape.standardNub.height)
        .frame(width: Metric.width)
        .background(SpeechBubbleShape(nubX: model.nubX).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(SpeechBubbleShape(nubX: model.nubX).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    /// The band across the top of the bubble, the tabs over a tool's page or the navigation bar over
    /// Settings and Help, its content standing on a hairline the bubble's width. Both are the same
    /// height, so the hairline is in one place whichever shows.
    private func topBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: Metric.barHeight, alignment: .bottom)
            .padding(.horizontal, Metric.edge)
            .padding(.top, Metric.barTop)
            .overlay(alignment: .bottom) { Divider() }
    }

    /// The app-wide problem, drawn as a page's warnings are: orange, with its one fix.
    private func bannerCard(_ banner: TabbedMenuBanner) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "exclamationmark.triangle.fill", tint: .orange, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title).font(.callout.weight(.medium))
                if let detail = banner.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Button(banner.actionTitle) { if !model.picture { model.actions.fixBanner() } }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    /// A page opened over a tool's page has a navigation bar, as in System Settings: back, named for
    /// the page it goes to (`esc` does the same), and the page's title in the middle.
    private func subpageHeader(_ top: TabbedMenuPage) -> some View {
        let previous = model.stack.count > 1 ? model.stack[model.stack.count - 2].title : model.current.shownTitle
        return ZStack {
            Text(top.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 90)
                .accessibilityAddTraits(.isHeader)
            HStack {
                NavigationBackPill(title: previous) { model.back(to: model.stack.count - 1) }
                Spacer()
            }
        }
        .frame(height: 28)
        .padding(.bottom, 5)
    }

    /// The whole app's buttons, under a hairline that runs the bubble's width so they read as apart
    /// from the page above: Settings and Quit mac++. Settings is tinted while it, or a page opened
    /// from it, shows.
    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Settings", symbol: "gearshape", help: "mac++ settings (⌘,)",
                         on: model.stack.first?.name == TabbedMenuPage.settings) {
                model.open(TabbedMenuPage.settings)
            }
            footerButton("Quit mac++", symbol: "power", help: "Quit mac++ and both tools (⌘Q)", on: false) {
                model.actions.quit()
            }
        }
        .padding(.horizontal, Metric.edge)
        .padding(.top, 4)
        .padding(.bottom, Metric.edge)
    }

    private func footerButton(_ title: String, symbol: String, help: String, on: Bool,
                              action: @escaping () -> Void) -> some View {
        Button { if !model.picture { action() } } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title).lineLimit(1)
            }
        }
        .buttonStyle(FooterButtonStyle(on: on))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The top of a tool's page, drawn as Settings' navigation bar is (the same height, on the same
    /// hairline): the tools' tabs across it, each its symbol alone (its name is on the page under
    /// it), the one showing in the accent with a line under it, on the hairline.
    private var masthead: some View {
        topBar {
            HStack(spacing: 0) {
                ForEach(Array(model.tabs.enumerated()), id: \.offset) { index, tab in
                    let chosen = index == model.selected
                    Button { model.select(index) } label: {
                        tab.icon()
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(chosen ? AnyShapeStyle(Color.accentColor)
                                             : AnyShapeStyle(hovered == index ? .primary : .secondary))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .bottom) {
                                Capsule().fill(chosen ? Color.accentColor : .clear).frame(width: 44, height: 2.5)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                    .help("\(tab.shownTitle) (⌘\(index + 1))")
                    .accessibilityLabel(tab.shownTitle)
                    .accessibilityAddTraits(chosen ? [.isSelected] : [])
                }
            }
            .frame(height: Metric.barHeight)
        }
    }
}

/// Back one page: a pill named for the page it goes back to.
private struct NavigationBackPill: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text(title).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Back to \(title) (esc)")
        .accessibilityLabel("Back to \(title)")
    }
}

/// The footer's buttons: a soft fill, and a tint of the accent on the one whose page is open.
private struct FooterButtonStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        FooterButtonBody(configuration: configuration, on: on)
    }

    private struct FooterButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let on: Bool
        @State private var hovering = false

        var body: some View {
            let fill = on ? Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.15)
                : Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.08 : 0.04)
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            configuration.label
                .font(.body.weight(on ? .semibold : .medium))
                .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(on ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.12)))
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

/// The dropdown as a picture, for onboarding's menu-bar step: `tabs` with the page at `selected`
/// showing and its nub at `nubX`. Nothing in it acts or is remembered.
public struct TabbedMenuPicture: View {
    @StateObject private var model: TabbedMenuModel

    public init(tabs: [MenuTab], selected: Int = 0, nubX: CGFloat? = nil, banner: TabbedMenuBanner? = nil) {
        _model = StateObject(wrappedValue: {
            var actions = TabbedMenuActions.inert
            actions.banner = { banner }
            let model = TabbedMenuModel(tabs: tabs, actions: actions)
            model.picture = true
            model.selected = selected
            model.nubX = nubX
            return model
        }())
    }

    public var body: some View {
        TabbedMenuView(model: model)
    }
}

/// Borderless panels refuse the keyboard by default; this one needs `esc`, ⌘1… and ⌘Q.
private final class TabbedMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// While typing in a field, the app's Edit menu (⌘A, ⌘C, ⌘V, ⌘X, ⌘Z) is asked from here, as the
    /// panel doesn't make mac++ the active app and so may not be offered its menu's shortcuts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard firstResponder is NSText else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
}
#endif
