#if canImport(AppKit)
import AppKit
import MacsBoredCore
import MacsShared

extension AppIcons {
    /// The app's name as Finder shows it, for one the settings file names by bundle ID alone.
    static func name(_ app: AppRef) -> String {
        guard app.name.isEmpty || app.name == app.bundleID else { return app.name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return app.bundleID }
        let shown = FileManager.default.displayName(atPath: url.path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }

    /// The app with the name Finder shows for it.
    static func named(_ app: AppRef) -> AppRef { AppRef(bundleID: app.bundleID, name: name(app)) }
}
#endif
