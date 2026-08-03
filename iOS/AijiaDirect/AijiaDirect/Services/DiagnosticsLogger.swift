import Combine
import Foundation

/// Privacy-safe diagnostics that can be exported from the app.
///
/// The logger intentionally writes only to the app sandbox. Passwords, tokens,
/// signatures and URL query strings are removed before a line is persisted.
final class DiagnosticsLogger: ObservableObject {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.example.AijiaDirect.diagnostics", qos: .utility)
    private let fileManager = FileManager.default
    private let logFileURL: URL
    private var lines: [String]
    private let dateFormatter: ISO8601DateFormatter
    private let maxLines = 4_000
    @Published private(set) var visibleLines: [String] = []

    private init() {
        // Documents is intentionally used here so the live log is visible in
        // Files.app when UIFileSharingEnabled is enabled in Info.plist.
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        logFileURL = documentsDirectory.appendingPathComponent("aijia-direct-diagnostics.log")
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let data = try? Data(contentsOf: logFileURL),
           let text = String(data: data, encoding: .utf8) {
            lines = Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines))
                .map(String.init)
        } else {
            lines = []
        }
        visibleLines = lines
    }

    func debug(_ category: String, _ message: String) {
        append(level: .debug, category: category, message: message)
    }

    func info(_ category: String, _ message: String) {
        append(level: .info, category: category, message: message)
    }

    func warning(_ category: String, _ message: String) {
        append(level: .warning, category: category, message: message)
    }

    func error(_ category: String, _ message: String) {
        append(level: .error, category: category, message: message)
    }

    func export() throws -> URL {
        try queue.sync {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = "aijia-direct-diagnostics-\(formatter.string(from: Date())).log"
            let documentsDirectory = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            let destination = documentsDirectory.appendingPathComponent(name)
            let text = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
            try Data(text.utf8).write(to: destination, options: .atomic)
            return destination
        }
    }

    func clear() {
        let snapshot = queue.sync { () -> [String] in
            lines.removeAll(keepingCapacity: true)
            try? fileManager.removeItem(at: logFileURL)
            return lines
        }
        DispatchQueue.main.async { [weak self] in
            self?.visibleLines = snapshot
        }
    }

    static func maskPhone(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 7 else { return value.isEmpty ? "<empty>" : "<redacted>" }
        let prefix = digits.prefix(3)
        let suffix = digits.suffix(2)
        return "\(prefix)*****\(suffix)"
    }

    static func maskIdentifier(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        guard value.count > 6 else { return "<redacted>" }
        return "\(value.prefix(3))…\(value.suffix(3))"
    }

    static func redactedURL(_ url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return "<url>" }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        return "\(scheme)://\(host)\(port)\(path)"
    }

    /// Returns the shape of a JSON value without including any of its values.
    /// This is useful for diagnosing API schema changes without persisting
    /// account, device or stream credentials.
    static func jsonSummary(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "null" }

        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.sorted().joined(separator: ",")
            var details = ["objectKeys=\(keys.isEmpty ? "<none>" : keys)"]
            if let code = dictionary["code"] {
                details.append("code=\(String(describing: code))")
            }
            if let data = dictionary["data"], let dataDictionary = data as? [String: Any] {
                details.append("dataKeys=\(dataDictionary.keys.sorted().joined(separator: ","))")
            } else if let data = dictionary["data"], let dataArray = data as? [Any] {
                details.append("dataCount=\(dataArray.count)")
            }
            return details.joined(separator: " ")
        }

        if let array = value as? [Any] {
            return "arrayCount=\(array.count)"
        }
        if value is String { return "string" }
        if value is NSNumber { return "number" }
        return String(describing: type(of: value))
    }

    static func compact(_ value: String, maxLength: Int = 240) -> String {
        let oneLine = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > maxLength else { return oneLine }
        return String(oneLine.prefix(maxLength)) + "…"
    }

    private func append(level: Level, category: String, message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let timestamp = self.dateFormatter.string(from: Date())
            let safeCategory = Self.sanitize(category)
            let safeMessage = Self.sanitize(message)
            let line = "[\(timestamp)] [\(level.rawValue)] [\(safeCategory)] \(safeMessage)"
            self.lines.append(line)
            if self.lines.count > self.maxLines {
                self.lines = Array(self.lines.suffix(self.maxLines))
            }
            self.persistLocked()
            let snapshot = self.lines
            DispatchQueue.main.async { [weak self] in
                self?.visibleLines = snapshot
            }
        }
    }

    private func persistLocked() {
        let text = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? Data(text.utf8).write(to: logFileURL, options: .atomic)
    }

    private static func sanitize(_ message: String) -> String {
        var result = message

        let sensitiveKeyPattern = #"(?i)(password|authdata|virtualAuthdata|hjqtoken|token|jwtoken|authorization|authorizationtoken|authorizationjwtoken|cookie|set-cookie|accesskeyid|secret|sign|signature|passphrase)\s*[:=]\s*("[^"]*"|'[^']*'|[^,\s}]+)"#
        result = replacingMatches(
            in: result,
            pattern: sensitiveKeyPattern,
            replacement: { match, text in
                guard let range = Range(match.range(at: 2), in: text) else { return text }
                return text.replacingCharacters(in: range, with: "[redacted]")
            }
        )

        let urlPattern = #"https?://[^\s\]\)\"']+"#
        result = replacingMatches(
            in: result,
            pattern: urlPattern,
            replacement: { match, text in
                let raw = (text as NSString).substring(with: match.range)
                guard let url = URL(string: raw) else { return "[url]" }
                return redactedURL(url)
            }
        )

        let phonePattern = #"\b1\d{10}\b"#
        result = replacingMatches(
            in: result,
            pattern: phonePattern,
            replacement: { match, text in
                let raw = (text as NSString).substring(with: match.range)
                return maskPhone(raw)
            }
        )
        return result
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange).reversed()
        var result = text
        for match in matches {
            let replacementValue = replacement(match, result)
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacementValue)
        }
        return result
    }
}
