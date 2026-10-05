import Foundation

/// Error while working with DXCC data.
///
/// Port of the Java `dxcc/DxccException.java` (`extends RuntimeException`, constructor
/// `(String message, Throwable cause)`). Naming follows the port convention
/// (`YamlError`, `LogbookError`), content follows Java: a Czech message and a cause.
/// The cause is kept as text so the type stays `Sendable`/`Equatable` -- the Java
/// `Throwable` is never read outside, it is only shown to the user.
///
/// **Mind the `kind`.** The Java `dxcc/` package is not consistent in its errors, and that
/// inconsistency is part of the behaviour:
/// - `DxccResolver.fromStream` and `DxccCodeIndex.fromStream` both throw `DxccException`
///   on `IOException` (broken/empty JSON) -> `kind == .parse`.
/// - On some inputs, however, they fail with a `NullPointerException`, i.e. a different
///   exception type than `DxccException` (measured on Java v1.1.1):
///   - `DxccResolver` on JSON **without the `dxcc` field** or with `"dxcc": null`
///     (`Cannot invoke "java.util.List.iterator()" because ... RawFile.dxcc() is null`);
///     `DxccCodeIndex` on the same input, by contrast, processes it as an empty index,
///   - **both** on a `null` element in the `dxcc` array (`{"dxcc":[null]}` ->
///     `Cannot invoke "... RawEntity.deleted()" because "e" is null`).
/// Swift has no `NullPointerException`; so that these situations can be told apart from
/// broken JSON just like in Java, they have `kind == .nullPointer`. It is **one** kind
/// for both places, because Java does not distinguish between them either -- it throws the same
/// exception.
/// (The sibling `CtyDxccResolver` throws `UncheckedIOException` -- but that is its
/// own type and does not belong here.)
public struct DxccError: Error, Equatable, Sendable, CustomStringConvertible {

    /// Kind of error -- see the note on the type.
    public enum Kind: String, Sendable, Equatable {
        /// Equivalent of the Java `DxccException`: the input could not be parsed.
        case parse
        /// Equivalent of the Java `NullPointerException`: the JSON is valid, but the `dxcc`
        /// field is missing / is `null` (`DxccResolver` only), or a `null` is an element of
        /// that array (both types).
        case nullPointer
    }

    public let kind: Kind
    /// Message in Czech -- the same as in Java.
    public let message: String
    /// Description of the cause (the Java `cause`), or `nil`.
    public let cause: String?

    public init(kind: Kind = .parse, message: String, cause: String? = nil) {
        self.kind = kind
        self.message = message
        self.cause = cause
    }

    public var description: String {
        guard let cause else { return message }
        return "\(message): \(cause)"
    }
}
