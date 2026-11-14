import Foundation

/// The executable's commands for scripts and agents, answered before the app starts:
///
///     mac-plus-plus macspane path            where config.json is
///     mac-plus-plus macspane check [file]    each problem with its line; exits 1 if there's an error
///     mac-plus-plus macspane schema          the JSON Schema the file follows
public enum MacsPaneConfigCommand {
    /// The command `arguments` name (without the program's own path or "macspane"), or nil when
    /// they name none.
    public static func run(_ arguments: [String], defaultURL: URL) -> (output: String, status: Int32)? {
        switch arguments.first {
        case "path":
            return (defaultURL.path, 0)
        case "schema":
            return (MacsPaneSchema.text, 0)
        case "check":
            let url = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : defaultURL
            guard let data = try? Data(contentsOf: url) else { return ("\(url.path): can't be read.", 1) }
            let reading = MacsPaneConfigFile.read(data)
            guard !reading.issues.isEmpty else { return ("\(url.path): no problems.", 0) }
            let lines = reading.issues.map { issue in
                "\(url.path)\(issue.line.map { ":\($0)" } ?? ""): \(issue.isWarning ? "warning" : "error"): \(issue.message)"
            }
            return (lines.joined(separator: "\n"), reading.errors.isEmpty ? 0 : 1)
        default:
            return nil
        }
    }
}
