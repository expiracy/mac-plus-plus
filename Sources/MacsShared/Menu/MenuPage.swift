#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI

/// A tool's page of the dropdown, sorted into the bands `MenuPageView` draws top to bottom: the name
/// with the tool's main switch, what is live now, any warnings, the general switches, then titled lists.
/// Both tools build one of these, so both pages are drawn by the same view.
public struct MenuPageContent {
    /// The tool's main switch, beside its name.
    public var primary: MenuEntry?
    /// What is happening now; empty draws the brand's quiet line, or no box at all.
    public var live: [MenuEntry] = []
    public var warnings: [MenuEntry] = []
    /// The tool's general switches and choices.
    public var toggles: [MenuEntry] = []
    /// Titled lists, in the order contributed. A long list scrolls in place.
    public var groups: [MenuGroup] = []
    /// A line under the name; nil shows the main switch's title.
    public var liveFact: String?
    /// The row whose name is being typed in place (it was just added); nil for none.
    public var renaming: String?

    public init() {}
}

/// A titled list on a page: its rows, which scroll once there are more than fit, then the commands
/// that always show under them ("New preset").
public struct MenuGroup: Identifiable {
    public let title: String
    public var rows: [MenuEntry]
    public var actions: [MenuEntry]
    /// The line shown in place of rows when there are none.
    public var empty: String?
    /// Set when the rows can be dragged into another order: moves the row at the first index so it
    /// ends up at the second.
    public var move: ((Int, Int) -> Void)?
    public var id: String { title }

    public init(title: String, rows: [MenuEntry], actions: [MenuEntry] = [], empty: String? = nil,
                move: ((Int, Int) -> Void)? = nil) {
        self.title = title
        self.rows = rows
        self.actions = actions
        self.empty = empty
        self.move = move
    }
}

/// One line of a page (`MenuPageView` draws them).
public struct MenuEntry: Identifiable {
    public enum Kind {
        /// A text-only title over the rows beneath it.
        case section
        /// What is happening now: what it is, one fact about it, and the one thing you would do to it
        /// from here (`accent` for the action that is the point of the line). The dropdown stays open
        /// and re-reads state after the click.
        case live(fact: String, actionTitle: String?, accent: Bool)
        /// A setting with a few named values, shown side by side; `selected` indexes `options`.
        case choice(options: [String], selected: Int)
        /// A setting that stays put: the row's switch is its one target and the dropdown stays open.
        /// A switch that cannot act now is `disabled` and keeps its row, so nothing below it moves.
        /// `primary` is the tool's main switch, which sits in the name band instead of the rows.
        case toggle(isOn: Bool, disabled: Bool, primary: Bool)
        /// Something done once; the dropdown closes. `danger` is a last-resort command.
        case command(danger: Bool)
        /// A feature that is on but cannot run, with the one click that fixes it (nil = nothing to click).
        case warning(actionTitle: String?)
    }

    /// What a row leads with.
    public enum Leading {
        /// `symbol` in a tinted tile.
        case symbol
        /// An app's own icon.
        case appIcon(NSImage)
        /// A drawing of the tool's own (MacsPane's layout shapes), `width` wide.
        case drawing(AnyView, width: CGFloat)
    }

    public let title: String
    public var symbol: String?
    public let kind: Kind
    public var action: (() -> Void)?
    /// A live line's click anywhere but its button: show its detail elsewhere. The dropdown closes first.
    public var open: (() -> Void)?
    /// A choice's pick, by index into its options.
    public var select: ((Int) -> Void)?
    /// A row's second button, at its end (the pencil). The dropdown closes first.
    public var secondary: (symbol: String, help: String, action: () -> Void)?
    /// A row's trash button, beside its second button: deletes once a second click confirms it. The
    /// dropdown stays open.
    public var trash: (help: String, action: () -> Void)?
    public var leading: Leading = .symbol
    /// Identity when titles can repeat; nil uses the title.
    public var key: String?
    /// Takes the name typed while this row is `MenuPageContent.renaming`: the text, or nil to keep the
    /// title it has.
    public var rename: ((String?) -> Void)?
    /// A command that leaves the dropdown open, such as one that adds a row to name in place.
    public var keepsOpen = false
    /// Quiet text at the row's end: its keys ("⌃⌥P") or a count.
    public var trailing: String?
    /// What `trailing` is, for VoiceOver ("Shortcut").
    public var trailingLabel: String?
    /// A command that offers a choice: clicking it opens these as a small menu, and each runs as a row would.
    public var submenu: [MenuEntry] = []

    public var id: String { key ?? title }

    init(title: String, symbol: String? = nil, kind: Kind, action: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.kind = kind
        self.action = action
    }

    public static func section(_ title: String) -> MenuEntry {
        MenuEntry(title: title, kind: .section)
    }

    public static func live(_ title: String, symbol: String, fact: String, actionTitle: String? = nil,
                            accent: Bool = false, key: String? = nil, action: (() -> Void)? = nil) -> MenuEntry {
        var entry = MenuEntry(title: title, symbol: symbol, kind: .live(fact: fact, actionTitle: actionTitle, accent: accent),
                              action: action)
        entry.key = key
        return entry
    }

    public static func choice(_ title: String, symbol: String, options: [String], selected: Int,
                              select: @escaping (Int) -> Void) -> MenuEntry {
        var entry = MenuEntry(title: title, symbol: symbol, kind: .choice(options: options, selected: selected))
        entry.select = select
        return entry
    }

    public static func toggle(_ title: String, symbol: String, isOn: Bool, disabled: Bool = false, primary: Bool = false,
                              key: String? = nil,
                              secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                              trash: (help: String, action: () -> Void)? = nil,
                              rename: ((String?) -> Void)? = nil,
                              action: @escaping () -> Void) -> MenuEntry {
        var entry = MenuEntry(title: title, symbol: symbol, kind: .toggle(isOn: isOn, disabled: disabled, primary: primary),
                              action: action)
        entry.key = key
        entry.secondary = secondary
        entry.trash = trash
        entry.rename = rename
        return entry
    }

    public static func command(_ title: String, symbol: String, danger: Bool = false, key: String? = nil,
                               keepsOpen: Bool = false,
                               secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                               trash: (help: String, action: () -> Void)? = nil,
                               rename: ((String?) -> Void)? = nil,
                               action: @escaping () -> Void) -> MenuEntry {
        var entry = MenuEntry(title: title, symbol: symbol, kind: .command(danger: danger), action: action)
        entry.key = key
        entry.keepsOpen = keepsOpen
        entry.secondary = secondary
        entry.trash = trash
        entry.rename = rename
        return entry
    }

    /// A command that opens a small menu of `items` ("New preset" → from the desktop, or drawn).
    public static func submenu(_ title: String, symbol: String, key: String? = nil,
                               items: [MenuEntry]) -> MenuEntry {
        var entry = MenuEntry(title: title, symbol: symbol, kind: .command(danger: false))
        entry.key = key
        entry.submenu = items
        return entry
    }

    public static func warning(_ title: String, actionTitle: String? = nil,
                               action: (() -> Void)? = nil) -> MenuEntry {
        MenuEntry(title: title, symbol: "exclamationmark.triangle", kind: .warning(actionTitle: actionTitle), action: action)
    }
}

/// A page's name, mark and section titles.
public struct MenuPageBrand {
    public var name: String
    /// The tool's mark, drawn at `size` beside its name and in the dropdown's switcher.
    public var logo: (CGFloat) -> AnyView
    /// The title over the box of what is live.
    public var liveTitle: String
    /// The box's line when nothing is live; nil leaves the box out until something is.
    public var emptyLive: String?
    /// The title over the switches.
    public var togglesTitle: String

    public init(name: String, logo: @escaping (CGFloat) -> AnyView, liveTitle: String = "Now",
                emptyLive: String? = nil, togglesTitle: String = "General") {
        self.name = name
        self.logo = logo
        self.liveTitle = liveTitle
        self.emptyLive = emptyLive
        self.togglesTitle = togglesTitle
    }
}

/// What a page shows and does. Rebuilt on open, after every click that leaves the dropdown open, and
/// once a second while it is open.
public final class MenuPageModel: ObservableObject {
    @Published public private(set) var content = MenuPageContent()
    /// What is typed in the row being named in place (`MenuPageContent.renaming`).
    @Published public var renameDraft = ""
    /// The row whose trash was clicked once: its bin is now a red "bin?" pill and a second click deletes.
    @Published public var confirmingTrash: String?
    /// The row whose choices hang under it in a small bubble.
    @Published public var openSubmenu: String?
    public let brand: MenuPageBrand
    /// Set by the dropdown; commands close it before they act.
    public var onClose: () -> Void = {}
    private let assemble: () -> MenuPageContent

    public init(brand: MenuPageBrand, assemble: @escaping () -> MenuPageContent) {
        self.brand = brand
        self.assemble = assemble
        refresh()
    }

    public func refresh() {
        content = assemble()
    }

    func pick(_ entry: MenuEntry, index: Int) {
        entry.select?(index)
        refresh()
    }

    /// A live line clicked off its button: close, then show its detail.
    func open(_ entry: MenuEntry) {
        guard let open = entry.open else { return }
        onClose()
        open()
    }

    /// A row of a list dragged to a new place.
    func move(_ group: MenuGroup, from source: Int, to destination: Int) {
        group.move?(source, destination)
        refresh()
    }

    /// A row's trash button: the first click asks, the second deletes. The dropdown stays open.
    func runTrash(_ entry: MenuEntry) {
        guard confirmingTrash == entry.id else { confirmingTrash = entry.id; return }
        confirmingTrash = nil
        entry.trash?.action()
        refresh()
    }

    /// The pointer left a row that was asking to delete: it asks no more.
    func cancelTrash(_ entry: MenuEntry) {
        if confirmingTrash == entry.id { confirmingTrash = nil }
    }

    /// The row being named in place takes what was typed (Return, a click away, the dropdown closing),
    /// or keeps its name (`cancel`, esc).
    public func finishRename(cancel: Bool = false) {
        guard let id = content.renaming,
              let entry = content.groups.flatMap(\.rows).first(where: { $0.id == id }) else { return }
        entry.rename?(cancel ? nil : renameDraft)
        refresh()
    }

    /// A row's second button. The dropdown closes first, unless the row `keepsOpen` (a button that
    /// opens another page of the dropdown).
    func runSecondary(_ entry: MenuEntry) {
        guard let secondary = entry.secondary else { return }
        if !entry.keepsOpen { onClose() }
        secondary.action()
    }

    /// A row with choices clicked: its bubble opens, or closes if it was open.
    func toggleSubmenu(_ entry: MenuEntry) {
        openSubmenu = openSubmenu == entry.id ? nil : entry.id
    }

    func run(_ entry: MenuEntry) {
        openSubmenu = nil
        guard let action = entry.action else { return }
        switch entry.kind {
        case .toggle, .live, .choice:
            action()
            refresh()
            // An owner that settles a beat later is read again once it has.
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        case .command where entry.keepsOpen:
            action()
            refresh()
        case .command, .warning, .section:
            onClose()
            action()
        }
    }
}

/// A tool's page of mac++'s dropdown: its `MenuPageModel` drawn by `MenuPageView`, and its Help.
public final class MenuPageTab: MenuTab {
    public let model: MenuPageModel
    public let help: HelpContent

    public init(model: MenuPageModel, help: HelpContent) {
        self.model = model
        self.help = help
    }

    public var title: String { model.brand.name }
    public func icon() -> AnyView { model.brand.logo(16) }
    public func page() -> AnyView { AnyView(MenuPageView(model: model)) }
    public func refresh() { model.refresh() }
    public var changes: AnyPublisher<Void, Never> {
        model.$content.dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    public var onClose: () -> Void {
        get { model.onClose }
        set { model.onClose = newValue }
    }

    /// `esc`: cancels a name being typed, then closes an open small menu; otherwise the dropdown closes.
    public func escape() -> Bool {
        if model.content.renaming != nil {
            model.finishRename(cancel: true)
        } else if model.openSubmenu != nil {
            model.openSubmenu = nil
        } else {
            return false
        }
        return true
    }

    public func willHide() {
        model.finishRename()   // a name being typed in place is kept
        model.openSubmenu = nil
        model.confirmingTrash = nil
    }
}
#endif
