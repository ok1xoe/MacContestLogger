import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `MultiplierKindTest` (1 case), extended to a table over all 22 supplied
/// contests measured on Java (maintainer-only probe).
@Suite struct MultiplierKindTests {

    static func kinds(_ contestId: String) throws -> [(String?, MultiplierKind)] {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let def = try SessionFixture.definition("@\(contestId).yaml")
        return try (def.multipliers ?? []).compactMap { $0 }.map {
            ($0.id, MultiplierKind.classify(def, $0, try registry.get($0.set)))
        }
    }

    static func kind(_ contestId: String, _ bindingId: String) throws -> MultiplierKind? {
        try kinds(contestId).first { $0.0 == bindingId }?.1
    }

    @Test func classifiesShippedContests() throws {
        let ww = try Self.kinds("cq-ww-cw")
        #expect(ww.map(\.0) == ["zones", "countries"])
        #expect(ww.map(\.1) == [.cq, .dxcc])
        #expect(try Self.kinds("ok-om-dx-cw").map(\.1).first { $0 != .dxcc } == .districts)
        #expect(try Self.kind("cq-ww-rtty", "states") == .sections)
        #expect(try Self.kind("iaru-hf", "hq") == .other)
        #expect(try Self.kinds("cq-wpx-cw").first?.1 == .other, "WPX prefixy")
        #expect(MultiplierKind.districts.key == "districts")
    }

    /// All 22 supplied contests: binding → window, as Java measured them (`-` = no multipliers).
    static let shipped: [(String, String)] = [
        ("arrl-dx-cw", "areas=sections"), ("arrl-dx-ssb", "areas=sections"),
        ("cq-160-cw", "areas=sections;countries=dxcc"), ("cq-160-ssb", "areas=sections;countries=dxcc"),
        ("cq-wpx-cw", "prefixes=other"), ("cq-wpx-rtty", "prefixes=other"), ("cq-wpx-ssb", "prefixes=other"),
        ("cq-ww-cw", "zones=cq;countries=dxcc"), ("cq-ww-rtty", "zones=cq;countries=dxcc;states=sections"),
        ("cq-ww-ssb", "zones=cq;countries=dxcc"), ("dx", "-"), ("iaru-hf", "zones=itu;hq=other"),
        ("iaru-r1-uhf", "-"), ("iaru-r1-vhf", "-"), ("marconi-memorial", "-"),
        ("ok-om-dx-cw", "districts=districts;countries=dxcc"), ("ok-om-dx-ssb", "districts=districts;countries=dxcc"),
        ("rdxc", "oblasts=other;countries=dxcc"), ("sp-dx", "provinces=districts"),
        ("wae-cw", "countries=dxcc"), ("wae-ssb", "countries=dxcc"), ("ww-digi", "grids=grid"),
    ]

    @Test func everyShippedContestMatchesJava() throws {
        let dir = try SessionFixture.contestData().appendingPathComponent("contests")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".yaml") }
        #expect(files.count == 22)
        #expect(Self.shipped.count == 22)
        for (id, expected) in Self.shipped {
            let kinds = try Self.kinds(id)
            let actual = kinds.isEmpty ? "-" : kinds.map { ($0.0 ?? "~") + "=" + $0.1.key }.joined(separator: ";")
            #expect(actual == expected, "\(id)")
        }
    }

    /// Order and keys of the windows = the Java enum (`name().toLowerCase(ROOT)`).
    @Test func keysInDeclarationOrder() {
        #expect(MultiplierKind.allCases.map(\.key) == ["dxcc", "grid", "itu", "cq", "districts", "sections", "other"])
        #expect(MultiplierKind.allCases.map(\.rawValue) == ["DXCC", "GRID", "ITU", "CQ", "DISTRICTS", "SECTIONS", "OTHER"])
    }
}
