#if canImport(AppKit)
import Combine
import SwiftUI

/// One app's page in mac++'s menu-bar dropdown (`TabbedMenuController`). The dropdown draws the
/// bubble and the switcher along its top; the page draws everything under that, from its own name
/// and main switch down to its footer.
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
}
#endif
