import Foundation

/// A colour the user can change (N1MM Configurer › Colors): its stored key (the name of the app's dynamic colour),
/// the Czech label key and the built-in light and dark colours (`0xRRGGBB`). An override replaces both.
public enum ColorSlot: String, CaseIterable, Sendable {
    case callNew = "mcl.callNew"
    case callMult = "mcl.callMult"
    case callDoubleMult = "mcl.callDoubleMult"
    case dupe = "mcl.dupe"
    case multiplier = "mcl.multiplier"
    case quickEdit = "mcl.quickEdit"
    case entryFocus = "mcl.entryFocus"
    case spotGood = "mcl.spot.good"
    case spotOneMult = "mcl.spot.one"
    case spotMultiMult = "mcl.spot.multi"
    case spotDupe = "mcl.spot.dupe"
    case planCw = "mcl.plan.cw"
    case planDigi = "mcl.plan.digi"
    case planPhone = "mcl.plan.phone"
    case bandNote = "mcl.bandNote"
    case catConnected = "mcl.catConnected"

    /// The group the Settings list shows the slot in.
    public enum Group: String, CaseIterable, Sendable {
        case entry
        case bandmap
    }

    public var group: Group {
        switch self {
        case .callNew, .callMult, .callDoubleMult, .dupe, .multiplier, .quickEdit, .entryFocus, .catConnected:
            return .entry
        case .spotGood, .spotOneMult, .spotMultiMult, .spotDupe, .planCw, .planDigi, .planPhone, .bandNote:
            return .bandmap
        }
    }

    /// The Czech text of the Settings row (a `tr` key).
    public var labelKey: String {
        switch self {
        case .callNew: return "Volačka — nové QSO"
        case .callMult: return "Volačka — násobič"
        case .callDoubleMult: return "Volačka — dvojitý násobič"
        case .dupe: return "Dupe a chyba"
        case .multiplier: return "Násobič (informační pruh)"
        case .quickEdit: return "Pozadí polí při QuickEdit"
        case .entryFocus: return "Pozadí pole s kurzorem"
        case .catConnected: return "Připojený TRX (CAT)"
        case .spotGood: return "Spot — nové QSO"
        case .spotOneMult: return "Spot — násobič"
        case .spotMultiMult: return "Spot — dva a více násobičů"
        case .spotDupe: return "Spot — dupe"
        case .planCw: return "Pásmový plán — CW"
        case .planDigi: return "Pásmový plán — DIGI"
        case .planPhone: return "Pásmový plán — fone"
        case .bandNote: return "Poznámka v pásmu"
        }
    }

    /// The built-in colour in the light appearance; `nil` = none (the entry focus colour is off by default).
    public var defaultLight: Int? {
        switch self {
        case .callNew: return 0x1565C0
        case .callMult: return 0xD32F2F
        case .callDoubleMult: return 0x2E7D32
        case .dupe: return 0xC62828
        case .multiplier: return 0x9A6200
        case .quickEdit: return 0xD6EBFF
        case .entryFocus: return nil
        case .catConnected: return 0x2E7D32
        case .spotGood: return 0x1E88E5
        case .spotOneMult: return 0xE53935
        case .spotMultiMult: return 0x43A047
        case .spotDupe: return 0x9E9E9E
        case .planCw: return 0x5C6BC0
        case .planDigi: return 0xFFB300
        case .planPhone: return 0x26A69A
        case .bandNote: return 0x8E24AA
        }
    }
}

/// `#RRGGBB` text of a colour override.
public enum ColorHex {

    /// `#RRGGBB` or `RRGGBB` (any case, surrounding blanks ignored) → `0xRRGGBB`; anything else `nil`.
    public static func parse(_ text: String) -> Int? {
        var body: Substring = Substring(text.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("#") {
            body = body.dropFirst()
        }
        guard body.count == 6, body.allSatisfy(\.isHexDigit) else { return nil }
        return Int(body, radix: 16)
    }

    /// `0xRRGGBB` → `#RRGGBB` (upper case).
    public static func format(_ rgb: Int) -> String {
        let digits = String(rgb & 0xFF_FFFF, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// The overrides as stored: known slots with a valid colour, normalised to `#RRGGBB`.
    public static func sanitized(_ overrides: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in overrides {
            guard ColorSlot(rawValue: key) != nil, let rgb = parse(value) else { continue }
            out[key] = format(rgb)
        }
        return out
    }
}

/// A skin (N1MM `.SKIN` file): the look as one unit — the appearance, the accent, the colour overrides and the font
/// families. Built-in skins ship with the app; a skin is saved to and loaded from a JSON file (`.mclskin`).
public struct Skin: Codable, Equatable, Sendable {
    public var name: String
    public var themeMode: String
    public var themeAccent: String
    public var colors: [String: String]
    public var fontFamily: String
    public var fixedFontFamily: String

    /// The file extension of a saved skin.
    public static let fileExtension = "mclskin"

    public init(name: String, themeMode: String = "SYSTEM", themeAccent: String = "TEAL",
                colors: [String: String] = [:], fontFamily: String = "", fixedFontFamily: String = "") {
        self.name = name
        self.themeMode = themeMode
        self.themeAccent = themeAccent
        self.colors = colors
        self.fontFamily = fontFamily
        self.fixedFontFamily = fixedFontFamily
    }

    enum CodingKeys: String, CodingKey {
        case name, themeMode, themeAccent, colors, fontFamily, fixedFontFamily
    }

    /// Lenient like the configuration: a missing key keeps the default, unknown slots and bad colours are dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Skin(name: "")
        name = c.value(.name, default: d.name)
        themeMode = c.value(.themeMode, default: d.themeMode)
        themeAccent = c.value(.themeAccent, default: d.themeAccent)
        colors = ColorHex.sanitized(c.value(.colors, default: d.colors))
        fontFamily = c.value(.fontFamily, default: d.fontFamily)
        fixedFontFamily = c.value(.fixedFontFamily, default: d.fixedFontFamily)
    }

    /// The skin of a Settings draft (what „Uložit skin" writes).
    public static func from(_ draft: ConfigurerDraft, name: String) -> Skin {
        Skin(name: name, themeMode: draft.themeMode, themeAccent: draft.themeAccent,
             colors: ColorHex.sanitized(draft.colorOverrides), fontFamily: draft.fontFamily,
             fixedFontFamily: draft.fixedFontFamily)
    }

    /// Puts the skin into a Settings draft (saved with the other settings).
    public func apply(to draft: inout ConfigurerDraft) {
        draft.themeMode = themeMode
        draft.themeAccent = themeAccent
        draft.colorOverrides = ColorHex.sanitized(colors)
        draft.fontFamily = fontFamily
        draft.fixedFontFamily = fixedFontFamily
    }

    /// The bytes of a skin file (pretty, sorted keys).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// A skin file's bytes; a file that is not a JSON object throws.
    public static func decode(_ data: Data) throws -> Skin {
        try JSONDecoder().decode(Skin.self, from: data)
    }

    /// The skins that ship with the app (names are `tr` keys).
    public static let builtIns: [Skin] = [
        Skin(name: "Výchozí"),
        Skin(name: "Klasický N1MM", themeMode: "LIGHT", themeAccent: "BLUE", colors: [
            ColorSlot.callNew.rawValue: "#0000FF", ColorSlot.callMult.rawValue: "#FF0000",
            ColorSlot.callDoubleMult.rawValue: "#008000", ColorSlot.spotGood.rawValue: "#0000FF",
            ColorSlot.spotOneMult.rawValue: "#FF0000", ColorSlot.spotMultiMult.rawValue: "#008000",
            ColorSlot.spotDupe.rawValue: "#808080", ColorSlot.entryFocus.rawValue: "#FFFFC0",
        ]),
        Skin(name: "Noční provoz", themeMode: "DARK", themeAccent: "ORANGE", colors: [
            ColorSlot.entryFocus.rawValue: "#3A2A00",
        ]),
        Skin(name: "Vysoký kontrast", themeMode: "DARK", themeAccent: "CONTRAST", colors: [
            ColorSlot.callNew.rawValue: "#00E5FF", ColorSlot.callMult.rawValue: "#FF5252",
            ColorSlot.callDoubleMult.rawValue: "#69F0AE", ColorSlot.spotGood.rawValue: "#00E5FF",
            ColorSlot.spotOneMult.rawValue: "#FF5252", ColorSlot.spotMultiMult.rawValue: "#69F0AE",
            ColorSlot.entryFocus.rawValue: "#333300",
        ]),
    ]
}
