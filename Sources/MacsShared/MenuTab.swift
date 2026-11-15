#if canImport(AppKit)
import Combine
import SwiftUI

/// One tool's page in mac++'s menu-bar dropdown (`TabbedMenuController`). The dropdown draws the
/// bubble, the switcher along its top and the app's footer; the page draws everything between, from
/// its own name and main switch down. `MenuPageTab` is the one every tool uses.
public protocol MenuTab: AnyObject {
    /// The page's name in the switcher.
    var title: String { get }
    /// The page's mark in the switcher, about 16 pt square.
    func icon() -> AnyView
    /// Everything under the switcher, drawn without a bubble of its own.
    func page() -> AnyView
    /// Read state again: on open, on switching to the page, and once a second while it shows.
    func refresh()
    /// Fires whenever the page may have changed height, so the dropdown refits.
    var changes: AnyPublisher<Void, Never> { get }
    /// Set by the dropdown: the page calls it to close the dropdown before a command acts.
    var onClose: () -> Void { get set }
    /// `esc` while the page shows. True when the page used it (closing a row's choices, cancelling
    /// a rename); false lets the dropdown close.
    func escape() -> Bool
    /// The dropdown is closing, or switching to another page.
    func willHide()
    /// The tool's Help, opened by the ? beside its name: how it works and its keys.
    var help: HelpContent { get }
    /// A page of the tool's own that the dropdown opens over its page in the same space ("New
    /// shortcut"), by name; nil for a name it doesn't know.
    func subpage(_ name: String) -> TabbedMenuSubpage?
    /// Set by the dropdown: the page calls it to open one of its `subpage`s.
    var onOpenPage: (String) -> Void { get set }
    /// The `subpage` holding the tool's settings, listed in the app's Settings; nil for none.
    var settingsPage: String? { get }
}

extension MenuTab {
    public var settingsPage: String? { nil }
}
#endif
