/// A Java exception raised by the Jackson 2.22 port behind `ProfileMerge` (parser and data binding): the class,
/// the original message, the location and the reference chain, rendered like
/// `JsonProcessingException.getMessage()` / `JsonMappingException.getMessage()`.
struct JacksonFailure: Error, Equatable, Sendable {

    static let parseException = "com.fasterxml.jackson.core.JsonParseException"
    static let eofException = "com.fasterxml.jackson.core.io.JsonEOFException"
    static let inputCoercionException = "com.fasterxml.jackson.core.exc.InputCoercionException"
    static let streamConstraintsException = "com.fasterxml.jackson.core.exc.StreamConstraintsException"
    static let mappingException = "com.fasterxml.jackson.databind.JsonMappingException"
    static let mismatchedInputException = "com.fasterxml.jackson.databind.exc.MismatchedInputException"
    static let invalidFormatException = "com.fasterxml.jackson.databind.exc.InvalidFormatException"
    static let unrecognizedPropertyException = "com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException"

    /// The Java class of the exception.
    var javaClass: String
    /// `getOriginalMessage()`; `nil` is printed as `N/A`.
    var originalMessage: String?
    /// `getMessageSuffix()` (the known properties of `UnrecognizedPropertyException`).
    var suffix: String?
    /// The location (`nil` = none).
    var location: JacksonLocation?
    /// The reference chain, outermost first (`AppConfig["rig"]`, `java.util.ArrayList[0]`…).
    var path: [String] = []

    /// A `JsonMappingException` (or a subclass): it carries a reference chain; parser exceptions get wrapped.
    var isMapping: Bool {
        javaClass.hasPrefix("com.fasterxml.jackson.databind.")
    }

    /// `Throwable.getMessage()` — the text Kotlin prints after `"Profil: "`.
    var message: String {
        var text: String = originalMessage ?? "N/A"
        if let suffix {
            text += suffix
        }
        if let location {
            text += "\n at " + location.description
        }
        if !path.isEmpty {
            text += " (through reference chain: " + path.joined(separator: "->") + ")"
        }
        return text
    }

    /// `JsonMappingException.wrapWithPath(src, ref)`: a mapping exception gets the reference prepended, a parser
    /// exception is wrapped in a plain `JsonMappingException` with its original message and location.
    func wrapped(_ reference: String) -> JacksonFailure {
        var result: JacksonFailure = self
        if !isMapping {
            let original: String = originalMessage ?? ""
            let text: String = original.isEmpty ? "(was " + javaClass + ")" : original
            result = JacksonFailure(javaClass: Self.mappingException, originalMessage: text, suffix: nil,
                                    location: location, path: path)
        }
        result.path.insert(reference, at: 0)
        return result
    }

    /// `StreamReadConstraints.validateIntegerLength` / `validateFPLength` (default limit 1000, no location).
    static func numberLength(_ length: Int) -> JacksonFailure? {
        guard length > 1000 else { return nil }
        let message: String = "Number value length (" + String(length)
            + ") exceeds the maximum allowed (1000, from `StreamReadConstraints.getMaxNumberLength()`)"
        return JacksonFailure(javaClass: streamConstraintsException, originalMessage: message, location: nil)
    }

    /// `JsonMappingException.Reference.getDescription()` for a bean property or a map key.
    static func reference(_ className: String, field: String) -> String {
        className + "[\"" + field + "\"]"
    }

    /// `JsonMappingException.Reference.getDescription()` for a collection index.
    static func reference(_ className: String, index: Int) -> String {
        className + "[" + String(index) + "]"
    }
}

/// `JsonLocation` with the source redacted (Jackson 2.16+ default: `INCLUDE_SOURCE_IN_LOCATION` disabled), which
/// also makes the content "non-textual": a column ≤ 0 is left out.
struct JacksonLocation: Equatable, Sendable, CustomStringConvertible {
    var line: Int
    var column: Int

    var description: String {
        var text: String = "[Source: REDACTED (`StreamReadFeature.INCLUDE_SOURCE_IN_LOCATION` disabled); "
        if line > 0 {
            text += "line: " + String(line)
            if column > 0 {
                text += ", column: " + String(column)
            }
        } else {
            text += "byte offset: #UNKNOWN"
        }
        return text + "]"
    }
}
