import Foundation

/// Wraps a `DxccLookup` and applies DXCC exceptions that depend on the shape/length of the callsign
/// and that the prefix and regex data in `~/dxcc-json` cannot express.
///
/// Currently handles **KG4**: Guantanamo Bay is only `KG4` + exactly 2 characters
/// (KG4XX); `KG4` + 1 or 3+ characters is the USA. Without this correction the data classifies
/// all `KG4*` as Guantanamo, so QSOs with US stations count as a different
/// country and the score is inflated (observed at CQ WPX RTTY, +37 % median for KG4 logs).
///
/// Port of the Java `dxcc/DxccSpecialCases.java`. It is a **decorator** -- it can be
/// wrapped around `DxccResolver` and `CtyDxccResolver` alike and stays composable. The exceptions
/// live here, **not** in `PrefixExtractor`.
///
/// A `struct` suffices: no state of its own, just a reference to the delegate. The delegate is a
/// `DxccLookup`, hence `Sendable` -- and so is the decorator.
public struct DxccSpecialCases: DxccLookup {

    /// Representative US callsign for obtaining the USA entity from the underlying data.
    ///
    /// The correction is **not applied** when the delegate does not know this particular callsign --
    /// there is no hard-wired USA entity in Java and the port does not add one.
    private static let usaProbe = "W1AW"

    private let delegate: any DxccLookup

    public init(_ delegate: any DxccLookup) {
        self.delegate = delegate
    }

    /// Resolves the callsign and fixes KG4 where applicable.
    ///
    /// The order of steps copies Java: the delegate is **always** queried (even for an empty
    /// callsign), then the decision is made.
    public func resolve(_ callsign: String?) -> DxccEntity? {
        corrected(callsign) { delegate.resolve($0) }
    }

    /// The same correction over the delegate's dated lookup (Club Log data; the others ignore the date).
    public func resolve(_ callsign: String?, at date: Date?) -> DxccEntity? {
        corrected(callsign) { delegate.resolve($0, at: date) }
    }

    private func corrected(_ callsign: String?, _ lookup: (String?) -> DxccEntity?) -> DxccEntity? {
        let base = lookup(callsign)
        guard let callsign, !JavaText.isBlank(callsign) else {
            return base
        }
        let norm = DxccResolver.normalize(callsign)
        if norm.hasPrefix("KG4") && !Self.isGuantanamoKg4(norm) {
            // KG4 with a suffix other than two characters is the USA, not Guantanamo.
            let usa = lookup(Self.usaProbe)
            let baseAlreadyUsa = base != nil && usa != nil && base!.entityCode == usa!.entityCode
            if usa != nil && !baseAlreadyUsa {
                return usa
            }
        }
        return base
    }

    /// Guantanamo = `KG4` + exactly 2 alphanumeric characters (KG4AB, KG4NE).
    ///
    /// Both the length and the "alphanumericity" are measured in **UTF-16 units**, because Java's
    /// `suffix.length()` and `suffix.chars()` work exactly that way: an emoji after `KG4` has
    /// length 2, but both its halves are surrogates, hence not
    /// `Character.isLetterOrDigit` -> the result is the USA, not Guantanamo.
    private static func isGuantanamoKg4(_ norm: String) -> Bool {
        guard norm.hasPrefix("KG4") else {
            return false
        }
        let suffix = Array(norm.utf16).dropFirst(3)
        return suffix.count == 2 && suffix.allSatisfy(isJavaLetterOrDigit)
    }

    /// Equivalent of the Java `Character.isLetterOrDigit(int)`: letters of categories
    /// `Lu`, `Ll`, `Lt`, `Lm`, `Lo` and digits of category `Nd`. Superscripts (`²` is `No`,
    /// not `Nd`) and Roman numerals (`Nl`) do not count -- measured
    /// on Java v1.1.1.
    private static func isJavaLetterOrDigit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else {
            return false // lone surrogate unit
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
             .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// Pure delegate -- unchanged.
    public func entities() -> [DxccEntity] {
        delegate.entities()
    }
}
