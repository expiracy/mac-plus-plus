import Foundation

/// Where MacsPane keeps its file: its own folder in Application Support.
public enum MacsPanePaths {
    public static let folderName = "MacsPane"

    public static func configURL(_ fm: FileManager = .default) throws -> URL {
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }
}

/// Loads, persists and publishes `MacsPaneConfig` as `config.json` (`MacsPaneConfigFile`), with its
/// schema written beside it. A first run writes `seed()` or the defaults. The file can be edited by
/// hand, by a script or by an AI agent while MacsPane runs: `reload()` takes the edit in. A file that
/// isn't JSON is never written over, so an edit in progress is never lost; the last good settings keep
/// running until it's fixed. Writes are atomic.
public final class MacsPaneConfigStore {
    public let url: URL
    public private(set) var config: MacsPaneConfig
    /// What's wrong with the file as it is on disk (errors and warnings).
    public private(set) var issues: [MacsPaneConfigFile.Issue] = []
    /// The most recent persistence error; the in-memory config stays usable.
    public private(set) var lastWriteError: Error?
    /// Invoked after any change, made here or in the file, so the menu and the notch can refresh.
    public var onChange: ((MacsPaneConfig) -> Void)?
    /// The file as last read or written, so a reload of our own write does nothing.
    private var lastData: Data?
    /// The file on disk isn't JSON: until it is, nothing is written over it.
    private var fileIsBroken = false

    public var errors: [MacsPaneConfigFile.Issue] { issues.filter { !$0.isWarning } }
    public var schemaURL: URL { url.deletingLastPathComponent().appendingPathComponent(MacsPaneConfigFile.schemaName) }

    public init(url: URL, seed: () -> MacsPaneConfig? = { nil }) {
        self.url = url
        self.config = .default
        try? Data(MacsPaneSchema.text.utf8).write(to: schemaURL, options: .atomic)
        if let data = try? Data(contentsOf: url) {
            apply(data)
            // Bring an older file up to today's shape (text keys, $schema), unless it can't be read.
            if !fileIsBroken, Data(MacsPaneConfigFile.write(config).utf8) != data { persist() }
        } else {
            config = seed() ?? .default
            persist()
        }
    }

    /// Reads the file again. Returns true when the settings or what's wrong with them changed.
    @discardableResult
    public func reload() -> Bool {
        guard let data = try? Data(contentsOf: url), data != lastData else { return false }
        let before = (config, issues)
        apply(data)
        guard before.0 != config || before.1 != issues else { return false }
        if before.0 != config { onChange?(config) }
        return true
    }

    /// Mutate the config in place, persist it, and notify observers. A failed write, or a file that
    /// isn't JSON (someone is mid-edit), rolls back.
    public func update(_ transform: (inout MacsPaneConfig) -> Void) {
        reload()
        let previous = config
        transform(&config)
        guard config != previous else { return }
        guard !fileIsBroken else {
            config = previous
            lastWriteError = BrokenFile(issues: errors)
            return
        }
        do {
            try write(config)
            lastWriteError = nil
            onChange?(config)
        } catch {
            config = previous
            lastWriteError = error
        }
    }

    /// The file on disk isn't JSON, so a change made in the app wasn't saved over it.
    public struct BrokenFile: Error {
        public let issues: [MacsPaneConfigFile.Issue]
    }

    private func apply(_ data: Data) {
        lastData = data
        let reading = MacsPaneConfigFile.read(data)
        issues = reading.issues
        fileIsBroken = reading.config == nil
        if let read = reading.config { config = read }
    }

    private func persist() {
        do { try write(config) } catch { lastWriteError = error }
    }

    private func write(_ config: MacsPaneConfig) throws {
        let data = Data(MacsPaneConfigFile.write(config).utf8)
        try data.write(to: url, options: [.atomic])
        lastData = data
        issues = []
    }
}
