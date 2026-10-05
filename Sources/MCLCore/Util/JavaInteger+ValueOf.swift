extension JavaInteger {

    /// Java `Integer.valueOf(String)` / `Integer.parseInt(String)` **with an exception**: where Java throws
    /// `NumberFormatException`, a `JavaNumberFormatError` is thrown here with the literal message
    /// `For input string: "<input>"` (also for empty input and overflow; JDK 21, radix 10 without suffix
    /// "under radix"). The algorithm is `parseInt` (sign, Unicode `Nd` digits by UTF-16 units).
    ///
    /// Needed by parsers where the exception in Java **propagates out** (`WwvMessage.parse`,
    /// `SelfSpot.detect` on a long number — kept, Swift `throws`).
    static func valueOf(_ text: String) throws(JavaNumberFormatError) -> Int32 {
        guard let value = parseInt(text) else {
            throw JavaNumberFormatError(message: "For input string: \"" + text + "\"")
        }
        return value
    }
}
