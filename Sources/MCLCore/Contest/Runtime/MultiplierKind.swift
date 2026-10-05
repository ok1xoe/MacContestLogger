import Foundation

/// The multiplier window a binding belongs to (N1MM Multipliers window: DXCC, zones,
/// counties, sections/states, others). Decided by the set type and the type of the received field the
/// multiplier comes from — not by the contest id.
///
/// Port of Java `contest/runtime/MultiplierKind.java`; `rawValue` is the name of the Java
/// constant, the case order is the declaration order.
public enum MultiplierKind: String, CaseIterable, Sendable {
    case dxcc = "DXCC"
    case grid = "GRID"
    case itu = "ITU"
    case cq = "CQ"
    case districts = "DISTRICTS"
    case sections = "SECTIONS"
    case other = "OTHER"

    /// Window key (`dxcc`, `districts`…) — identical to the id in the menu `mult.<key>`
    /// (Java `name().toLowerCase(Locale.ROOT)`).
    public var key: String {
        rawValue.lowercased()
    }

    /// Java decision order: DXCC set → set id `grid_fields`/`itu_zones`/`cq_zones`
    /// (exactly, by UTF-16) → type of the received field the binding takes its value from (`from`,
    /// by UTF-16, first match) and the set id in lower case (`district`, `section`, `na_areas`).
    ///
    /// Where Java fails with an NPE, Swift is lenient (a deliberate divergence from Java v1.1.1): a set without an id
    /// is taken as "id does not match" (the field type decides), a `nil` element of `received` is skipped
    /// and a field without a type "has no type".
    public static func classify(_ def: ContestDefinition, _ binding: ContestDefinition.MultiplierBinding,
                                _ set: any MultiplierSet) -> MultiplierKind {
        if set is DxccMultiplierSet {
            return .dxcc
        }
        let setId = set.id ?? ""
        if JavaText.equals("grid_fields", setId) {
            return .grid
        }
        if JavaText.equals("itu_zones", setId) {
            return .itu
        }
        if JavaText.equals("cq_zones", setId) {
            return .cq
        }
        var type: ContestDefinition.FieldType?
        if let received = def.exchange?.received {
            type = received.first { field in
                guard let id = field?.id, let from = binding.from else { return false }
                return JavaText.equals(id, from)
            }??.type
        }
        let id = Array(setId.lowercased().utf16)
        // After simple statements: a chain of four `||` over an optional enum an older compiler
        // in CI cannot type-check in time.
        let isDistrictType: Bool = type == .DISTRICT
        if isDistrictType || contains(id, "district") {
            return .districts
        }
        let isStateType: Bool = type == .STATE
        let isProvinceType: Bool = type == .PROVINCE
        if isStateType || isProvinceType {
            return .sections
        }
        if contains(id, "section") || id.elementsEqual("na_areas".utf16) {
            return .sections
        }
        return .other
    }

    /// Java `String.contains` by UTF-16 units (Swift `contains` compares canonically).
    private static func contains(_ text: [UInt16], _ part: String) -> Bool {
        let needle = Array(part.utf16)
        guard needle.count <= text.count else { return false }
        for start in 0...(text.count - needle.count) where text[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }
}
