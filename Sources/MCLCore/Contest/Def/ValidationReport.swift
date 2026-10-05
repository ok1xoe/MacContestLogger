/// Result of validating a contest definition — a list of findings with severity in the order
/// the validator added them.
///
/// Port of Java `contest/def/ValidationReport.java`. Java has a mutable class
/// with `error`/`warning`; here a value type with `mutating` methods.
public struct ValidationReport: Equatable, Sendable, CustomStringConvertible {

    /// Java `Severity`; `description` = the Java constant name (`toString`).
    public enum Severity: Equatable, Sendable, CustomStringConvertible {
        case warning
        case error

        public var description: String {
            switch self {
            case .warning: "WARNING"
            case .error: "ERROR"
            }
        }
    }

    /// Java record `Issue(severity, message)`.
    public struct Issue: Equatable, Sendable {
        public let severity: Severity
        public let message: String

        public init(severity: Severity, message: String) {
            self.severity = severity
            self.message = message
        }
    }

    /// Findings in insertion order (Java `issues()`).
    public private(set) var issues: [Issue] = []

    public init() {}

    public mutating func error(_ message: String) {
        issues.append(Issue(severity: .error, message: message))
    }

    public mutating func warning(_ message: String) {
        issues.append(Issue(severity: .warning, message: message))
    }

    /// Contains at least one ERROR.
    public var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    /// Without ERRORs (WARNINGs do not invalidate).
    public var isValid: Bool {
        !hasErrors
    }

    /// Only the ERROR messages, in order.
    public var errors: [String] {
        issues.filter { $0.severity == .error }.map(\.message)
    }

    /// Java `toString`: „OK (bez nálezů)", otherwise a line „[SEVERITY] zpráva\n"
    /// for every finding (also after the last one).
    public var description: String {
        if issues.isEmpty {
            return "OK (bez nálezů)"
        }
        var text = ""
        for issue in issues {
            text += "[\(issue.severity)] \(issue.message)\n"
        }
        return text
    }
}
