/// Port of Java `contest/category/CategoryCatalog.java`: the category catalog for the New
/// Contest window — a fixed set of standard Cabrillo categories (the same for all contests) and derivation
/// of the Band/Mode options and sent fields from the contest definition. Pure logic, no UI.
///
/// `nil` elements in definition lists (YAML `bands: [20m, ~]`) make Java fail with an NPE; Swift
/// skips them (a deliberate divergence from Java v1.1.1).
public enum CategoryCatalog {

    public struct CategoryDim: Equatable, Sendable {
        public var key: String
        public var label: String
        public var options: [String]

        public init(key: String, label: String, options: [String]) {
            self.key = key
            self.label = label
            self.options = options
        }
    }

    /// Fixed Cabrillo categories (without Band/Mode — those come from the definition).
    public static func fixed() -> [CategoryDim] {
        [
            CategoryDim(key: "OPERATOR", label: "Operátor", options: ["SINGLE-OP", "MULTI-OP", "CHECKLOG"]),
            CategoryDim(key: "POWER", label: "Výkon", options: ["HIGH", "LOW", "QRP"]),
            CategoryDim(key: "OVERLAY", label: "Overlay",
                        options: ["N/A", "CLASSIC", "ROOKIE", "TB-WIRES", "YOUTH", "YL"]),
            CategoryDim(key: "STATION", label: "Stanice",
                        options: ["FIXED", "MOBILE", "PORTABLE", "ROVER", "EXPEDITION", "HQ", "SCHOOL"]),
            CategoryDim(key: "ASSISTED", label: "Asistovaně", options: ["NON-ASSISTED", "ASSISTED"]),
            CategoryDim(key: "TRANSMITTER", label: "Vysílače",
                        options: ["ONE", "TWO", "LIMITED", "UNLIMITED", "SWL"]),
            CategoryDim(key: "TIME", label: "Časová kat.", options: ["N/A", "6-HOURS", "12-HOURS", "24-HOURS"]),
        ]
    }

    /// Band options: „ALL" + the definition's bands in upper case (no trimming, no deduplication).
    public static func bandOptions(_ definition: ContestDefinition) -> [String] {
        var out = ["ALL"]
        for band in definition.bands ?? [] {
            if let band { out.append(band.uppercased()) }
        }
        return out
    }

    /// Mode options: the definition's modes in upper case (+ „MIXED" if there is more than one).
    public static func modeOptions(_ definition: ContestDefinition) -> [String] {
        var out: [String] = []
        for mode in definition.modes ?? [] {
            if let mode { out.append(mode.uppercased()) }
        }
        if out.count > 1 {
            out.append("MIXED")
        }
        return out
    }

    /// Sent exchange fields to display (entered by the operator: `FROM_STATION` / `MANUAL`).
    public static func sentFields(_ definition: ContestDefinition) -> [ContestDefinition.ExchangeField] {
        var out: [ContestDefinition.ExchangeField] = []
        for field in definition.exchange?.sent ?? [] {
            if let field, field.source == .FROM_STATION || field.source == .MANUAL {
                out.append(field)
            }
        }
        return out
    }
}
