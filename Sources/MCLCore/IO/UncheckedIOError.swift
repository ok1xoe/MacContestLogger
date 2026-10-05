/// Java `UncheckedIOException` from the file wrappers of the `io/` package (`readFile`,
/// `writeToFile`): `message` verbatim as in Java (`Nelze načíst ADIF: <path>`), `cause`
/// is the original error — `Utf8Text.MalformedInput` where Java reports
/// `MalformedInputException`, otherwise a Foundation error (missing file, permissions…).
public struct UncheckedIOError: Error {
    public let message: String
    public let cause: any Error
}
