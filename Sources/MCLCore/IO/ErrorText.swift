import Foundation

/// The message of an error for status texts (Kotlin `it.message`): the core's errors describe themselves in Czech.
public enum ErrorText {
    public static func message(_ error: any Error) -> String {
        if error is any JavaThrowable {
            // Java `getMessage()` (the `IO/` errors, `LogbookError`, `JavaIOError`); `null` → "null".
            return JavaThrowables.message(error)
        }
        let bridged = error as NSError
        let system: Set<String> = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
        if system.contains(bridged.domain) {
            return bridged.localizedDescription
        }
        return String(describing: error)
    }
}
