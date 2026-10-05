import Foundation

/// The hamlib rig list entry under a name that does not clash with the app's `RigModel` (the rig sessions): a module
/// that imports both refers to this one as `HamlibRigModel`.
public typealias HamlibRigModel = RigModel

/// Entry in the list of rigs supported by hamlib (Java record `cat/RigModel`).
public struct RigModel: Equatable, Sendable, CustomStringConvertible {
    /// Model number (the `-m` option for `rigctld`).
    public let number: Int
    /// Manufacturer (Kenwood, Yaesu, Icom…).
    public let mfg: String
    /// Model designation (TS-570, IC-7300…).
    public let model: String

    public init(number: Int, mfg: String, model: String) {
        self.number = number
        self.mfg = mfg
        self.model = model
    }

    /// Java `toString()`: `2037 — Kenwood TS-590SG` (dash U+2014).
    public var description: String {
        "\(number) \u{2014} \(mfg) \(model)"
    }
}

/// List of rigs supported by hamlib (`rigctl -l`) — Java `cat/HamlibRigList`. Here only the pure line
/// parsing; launching `rigctl` and the fallback list (`list()`) are in `HamlibRigList+List.swift`.
public enum HamlibRigList {

    /// `\d+(\.\d+)+.*|\d{6,}` — the token that starts the version (ends the model name). Java dialect:
    /// `\d` is ASCII only, `.` does not match line terminators (U+0085, U+2028…).
    private static let versionLike: JavaRegex = {
        do {
            return try JavaRegex("\\d+(\\.\\d+)+.*|\\d{6,}")
        } catch {
            preconditionFailure("vzor verze hamlibu je pevný a platný: \(error)")
        }
    }()

    /// Words of the `Status` column (exact case, Java `Set.of(...).contains`).
    private static let statusWords: Set<String> = ["Alpha", "Beta", "Stable", "Untested", "Buggy", "New"]

    /// Parses a line of `rigctl -l` output (`  2011  Kenwood  TS-570  20231210.0  Stable  rig`).
    ///
    /// Java `line.trim().split("\\s+")`: trims characters ≤ U+0020, splits on ASCII whitespace only
    /// (`[ \t\n\u{0B}\f\r]`); fewer than three tokens or a number that `Integer.parseInt` rejects (header,
    /// `int` overflow) → `nil`. Model = tokens from the third up to the first that looks like a version or is
    /// a status word (the manufacturer is always just the second token — `N2ADR James Ahlstrom` splits as in Java).
    public static func parseLine(_ line: String) -> RigModel? {
        let tokens = splitOnAsciiSpace(JavaText.trim(line))
        guard tokens.count >= 3, let number = JavaInteger.parseInt(tokens[0]) else {
            return nil
        }
        var model: [String] = []
        for token in tokens[2...] {
            if versionLike.matches(token) || statusWords.contains(token) {
                break
            }
            model.append(token)
        }
        return RigModel(number: Int(number), mfg: tokens[1], model: model.joined(separator: " "))
    }

    /// Java `split("\\s+")` over already trimmed text: there is no whitespace at the start or end, so
    /// an empty token arises only from empty input (`[""]`, as in Java).
    private static func splitOnAsciiSpace(_ text: String) -> [String] {
        var tokens: [String] = []
        var current: [UInt16] = []
        var inSpace = false
        for unit in text.utf16 {
            if JavaChar.isRegexSpace(unit) {
                if !inSpace {
                    tokens.append(JavaChar.string(current))
                    current.removeAll(keepingCapacity: true)
                }
                inSpace = true
            } else {
                current.append(unit)
                inSpace = false
            }
        }
        tokens.append(JavaChar.string(current))
        return tokens
    }
}

/// Pure rig-selection logic for the TCVR Settings dialog (Java `cat/RigModelFilter`): the list of manufacturers
/// and filtering of models by manufacturer and search text.
///
/// Ordering is Java `String.CASE_INSENSITIVE_ORDER` (`JavaText.caseInsensitiveOrder`: `ß` < `É`, `[` < `_`),
/// search is Java `toLowerCase()` + `contains` over UTF-16 (`İ` → `i̇`). The default `tr_TR` locale is not
/// emulated — there `İ` would also find `hamlib`.
public enum RigModelFilter {

    /// Sorted list of unique manufacturers, case-insensitive (Java `TreeSet` —
    /// on a tie the first occurrence stays).
    public static func manufacturers(_ all: [RigModel]) -> [String] {
        var sorted: [String] = []
        for m in all {
            var low = 0
            var high = sorted.count
            var found = false
            while low < high {
                let mid = (low + high) / 2
                let order = JavaText.caseInsensitiveOrder(sorted[mid], m.mfg)
                if order == 0 {
                    found = true
                    break
                }
                if order < 0 {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            if !found {
                sorted.insert(m.mfg, at: low)
            }
        }
        return sorted
    }

    /// Filters and sorts models (stable by manufacturer, then model). If `query` is non-empty after trimming,
    /// it searches globally in the text „manufacturer model" and the manufacturer filter is ignored; otherwise it filters by
    /// manufacturer (`nil`/empty = all, `equalsIgnoreCase` after trimming).
    public static func filter(_ all: [RigModel], manufacturer: String?, query: String?) -> [RigModel] {
        let q: [UInt16] = Array(JavaText.toLowerCase(JavaText.trim(query ?? "")).utf16)
        let mfg = JavaText.trim(manufacturer ?? "")
        var result: [(index: Int, model: RigModel)] = []
        for (index, m) in all.enumerated() {
            let match: Bool
            if !q.isEmpty {
                let haystack: [UInt16] = Array(JavaText.toLowerCase(m.mfg + " " + m.model).utf16)
                match = JavaText.indexOf(haystack, q) >= 0
            } else {
                match = mfg.isEmpty || JavaChar.equalsIgnoreCase(m.mfg, mfg)
            }
            if match {
                result.append((index, m))
            }
        }
        // Java `List.sort` is stable (TimSort); Swift `sort` does not guarantee that → index as the last key.
        result.sort { a, b in
            let byMfg = JavaText.caseInsensitiveOrder(a.model.mfg, b.model.mfg)
            if byMfg != 0 { return byMfg < 0 }
            let byModel = JavaText.caseInsensitiveOrder(a.model.model, b.model.model)
            if byModel != 0 { return byModel < 0 }
            return a.index < b.index
        }
        return result.map(\.model)
    }
}

/// Experimental rig autodetection (Java `cat/RigScanner`). Here only the pure assembly of the candidate order;
/// the scan itself (launches `rigctld` on ports 4600+) is in `RigScanner+Scan.swift`.
public enum RigScanner {

    /// One tried combination (model, baud).
    public struct Candidate: Equatable, Sendable {
        public let model: Int
        public let label: String
        public let baud: Int

        public init(model: Int, label: String, baud: Int) {
            self.model = model
            self.label = label
            self.baud = baud
        }
    }

    /// Common models to try (matched as a substring of the `toLowerCase` text „manufacturer model").
    static let common: [String] = [
        "TS-590", "TS-480", "TS-2000", "TS-570", "TS-890", "TS-990",
        "IC-7300", "IC-7610", "IC-705", "IC-7100", "IC-9700", "IC-746",
        "FT-991", "FTDX10", "FTDX-10", "FT-857", "FT-897", "FT-950", "FTDX3000",
        "K3", "K4",
    ]

    /// Candidate order: first the selected model across all bauds (with its description), then common models
    /// in hamlib list order (description = `RigModel.description`). Deduplicated by (model, baud).
    public static func buildCandidates(selectedModel: Int, selectedLabel: String, all: [RigModel],
                                       bauds: [Int]) -> [Candidate] {
        var out: [Candidate] = []
        var seen: Set<String> = []
        func addUnique(_ model: Int, _ label: String, _ baud: Int) {
            if seen.insert("\(model)@\(baud)").inserted {
                out.append(Candidate(model: model, label: label, baud: baud))
            }
        }
        for baud in bauds {
            addUnique(selectedModel, selectedLabel, baud)
        }
        for m in curated(all) {
            for baud in bauds {
                addUnique(m.number, m.description, baud)
            }
        }
        return out
    }

    private static func curated(_ all: [RigModel]) -> [RigModel] {
        let names: [[UInt16]] = common.map { Array(JavaText.toLowerCase($0).utf16) }
        return all.filter { m in
            let label: [UInt16] = Array(JavaText.toLowerCase(m.mfg + " " + m.model).utf16)
            return names.contains { JavaText.indexOf(label, $0) >= 0 }
        }
    }
}

/// Serial-line parameters passed to `rigctld` via `--set-conf` (Java record `cat/SerialParams`).
/// Values are already in the form hamlib expects ("None", "Even", "Hardware", "ON", "OFF", "Unset");
/// `nil` corresponds to Java `null`.
public struct SerialParams: Equatable, Sendable {
    public let dataBits: Int
    public let stopBits: Int
    public let parity: String?
    public let handshake: String?
    public let rts: String?
    public let dtr: String?

    public init(dataBits: Int, stopBits: Int, parity: String?, handshake: String?, rts: String?, dtr: String?) {
        self.dataBits = dataBits
        self.stopBits = stopBits
        self.parity = parity
        self.handshake = handshake
        self.rts = rts
        self.dtr = dtr
    }

    /// Value for `rigctld --set-conf=...`. `serial_handshake` is omitted when `nil` or empty
    /// (`isBlank` — do not force it, forcing it breaks e.g. the TS-590SG over USB); `rts_state`/`dtr_state`
    /// when `nil` or `Unset`, case-insensitive. A `nil` parity is printed as `null` (Java).
    public func toSetConf() -> String {
        var sb = "data_bits=\(dataBits)"
        sb += ",stop_bits=\(stopBits)"
        sb += ",serial_parity=" + (parity ?? "null")
        if let handshake, !JavaText.isBlank(handshake) {
            sb += ",serial_handshake=" + handshake
        }
        if let rts, !JavaChar.equalsIgnoreCase(rts, "Unset") {
            sb += ",rts_state=" + rts
        }
        if let dtr, !JavaChar.equalsIgnoreCase(dtr, "Unset") {
            sb += ",dtr_state=" + dtr
        }
        return sb
    }
}
