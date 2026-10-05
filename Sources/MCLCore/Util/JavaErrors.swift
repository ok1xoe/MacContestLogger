/// Java exceptions that Swift code imitates as errors (`getMessage()` literally). Exceptions of a single
/// area with their own semantics live next to it (`JavaInvalidPathError` at `JavaPath`, `JavaSocketError`
/// at `LineSocket`, `CatException` at `RigController`).

/// Java `IllegalArgumentException` (`getMessage()` literally).
public struct JavaIllegalArgumentError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Java `NoSuchElementException` (from `ArrayDeque.removeFirst` on an empty queue).
public struct JavaNoSuchElementError: Error, Equatable, Sendable {
    public init() {}
}

/// Java `IOException` or its subclass (`javaClass`, e.g. `java.net.ConnectException`,
/// `java.net.http.HttpTimeoutException`); `message` = `getMessage()` literally — may be missing (Java `null`,
/// e.g. `ConnectException` from `HttpClient` on a refused connection). Kotlin status lines show `message`.
public struct JavaIOError: Error, Equatable, Sendable, CustomStringConvertible {
    public let javaClass: String
    public let message: String?

    public init(_ message: String?, javaClass: String = "java.io.IOException") {
        self.javaClass = javaClass
        self.message = message
    }

    /// Java `Throwable.toString()`.
    public var description: String {
        guard let message else { return javaClass }
        return javaClass + ": " + message
    }
}

/// Java `ArithmeticException` (`getMessage()` literally, e.g. `Overflow` from `BigDecimal.longValueExact`
/// in `CallFieldCommands.parse`). Unchecked in Java and propagates up to the UI; what the UI does with it is decided by the UI layer.
public struct JavaArithmeticError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    /// Java `Throwable.toString()`.
    public var description: String {
        "java.lang.ArithmeticException: " + message
    }
}
