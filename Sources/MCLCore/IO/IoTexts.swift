import Foundation

/// Status texts of import, merge, the EDI and other exports and printing (`AS` = `ui/AppState.kt` of v1.1.1).
/// Keys are the Czech originals translated where they are shown; the Kotlin strings without `tr` are `verbatim`.
public enum IoTexts {

    /// Kotlin string template of an exception message: `"${it.message}"` prints `null` for a missing one.
    public static func template(_ message: String?) -> String {
        message ?? "null"
    }

    // MARK: - import, merge (`AS:4115-4180`)

    /// `AS:4178` — `tr("Importováno %s QSO (%s) z %s", count, "ADIF"|"Cabrillo", fileName)`.
    public static func imported(count: Int, format: LogImporter.Format, file: String) -> ContestMessage {
        ContestMessage("Importováno %s QSO (%s) z %s", .int(count), .string(format.label), .string(file))
    }

    /// `AS:4156` — the file cannot be read (and, the reader failed: nothing was inserted).
    public static func unreadable(file: String) -> ContestMessage {
        ContestMessage("Nelze přečíst soubor: %s", .string(file))
    }

    /// `AS:4151`.
    public static func merged(file: String, added: Int, skipped: Int) -> ContestMessage {
        ContestMessage("Sloučeno z %s: přidáno %s QSO, přeskočeno %s duplicit",
                       .string(file), .int(added), .int(skipped))
    }

    /// `AS:4135` — `tr("Sloučení: nelze přečíst %s (%s)", path.fileName, it.message)`.
    public static func mergeUnreadable(file: String, message: String?) -> ContestMessage {
        ContestMessage("Sloučení: nelze přečíst %s (%s)", .string(file), .string(template(message)))
    }

    // MARK: - EDI (`AS:4055-4074`)

    /// `AS:4056`.
    public static let ediNoContest = ContestMessage("EDI: není aktivní závod")
    /// `AS:4058`.
    public static let ediNoLocator = ContestMessage("EDI: doplň 6místný lokátor stanice (Nastavení → Stanice)")
    /// `AS:4061`.
    public static let ediEmpty = ContestMessage("EDI: deník je prázdný")

    /// `AS:4073` — `tr("EDI: zapsáno %s do %s", names.joinToString(", "), dir)`.
    public static func ediWritten(names: [String], dir: String) -> ContestMessage {
        ContestMessage("EDI: zapsáno %s do %s", .string(names.joined(separator: ", ")), .string(dir))
    }

    // MARK: - other exports (`AS:4038-4052`)

    /// `AS:4040` — the contest name without an active definition (`metadata.name ?: tr("Deník")`).
    public static let defaultLogName = "Deník"

    /// `AS:4051` — `"Export: ${written.joinToString(", ")} do $dir"`, without `tr`.
    public static func otherWritten(names: [String], dir: String) -> ContestMessage {
        .verbatim("Export: " + names.joined(separator: ", ") + " do " + dir)
    }

    // MARK: - printing (`AS:4025-4035`)

    /// `AS:4032`.
    public static let printSent = ContestMessage("Deník odeslán na tiskárnu")
    /// `AS:4032`.
    public static let printCancelled = ContestMessage("Tisk zrušen")

    /// `AS:4032` — `"Tisk selhal: ${it.message}"`, without `tr`.
    public static func printFailed(message: String?) -> ContestMessage {
        .verbatim("Tisk selhal: " + template(message))
    }
}
