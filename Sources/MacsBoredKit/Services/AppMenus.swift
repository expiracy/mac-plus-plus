#if canImport(AppKit)
import AppKit
import ApplicationServices
import MacsBoredCore

/// An app's menus as Accessibility sees them: read a level at a time for the editor to pick from, and
/// an item chosen by its titles as a click would choose it. The app needn't be in front to be read.
@MainActor
enum AppMenus {
    /// One entry of a menu: its title, and whether it opens a submenu.
    struct Entry: Hashable {
        let title: String
        let hasSubmenu: Bool
    }

    /// What `path` leads to in the app's menus: the menu bar's titles for an empty path, else the
    /// entries of the submenu it names. Nil when the app can't be read (not running, no Accessibility)
    /// or the path leads nowhere.
    static func entries(at path: [String], pid: pid_t) -> [Entry]? {
        guard var menu = menuBar(pid) else { return nil }
        for title in path {
            guard let item = child(of: menu, titled: title), let submenu = children(item).first else { return nil }
            menu = submenu
        }
        return children(menu).compactMap { item in
            let title = string(item, kAXTitleAttribute) ?? ""
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }   // separators
            return Entry(title: title, hasSubmenu: !children(item).isEmpty)
        }
    }

    /// Chooses the item `path` names in the app in front, as clicking it would. False when it isn't
    /// there, or can't be chosen now (greyed out).
    @discardableResult
    static func choose(_ path: MenuPath, pid: pid_t) -> Bool {
        guard path.isComplete, var menu = menuBar(pid) else { return false }
        for (index, title) in path.titles.enumerated() {
            guard let item = child(of: menu, titled: title) else { return false }
            if index == path.titles.count - 1 {
                guard bool(item, kAXEnabledAttribute) != false else { return false }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            guard let submenu = children(item).first else { return false }
            menu = submenu
        }
        return false
    }

    // MARK: - Accessibility

    private static func menuBar(_ pid: pid_t) -> AXUIElement? {
        element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute)
    }

    private static func child(of menu: AXUIElement, titled title: String) -> AXUIElement? {
        children(menu).first { MenuPath.matches(title, string($0, kAXTitleAttribute) ?? "") }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
#endif
