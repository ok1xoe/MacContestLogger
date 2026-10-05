import CoreGraphics
import Foundation
import Testing
@testable import MCLCore

@Suite struct EntriesTests {

    // MARK: - An empty JSON gives the same values as init()

    @Test func emptyJsonEqualsDefaults() throws {
        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(WindowGeometry.self, from: empty) == WindowGeometry())
        #expect(try JSONDecoder().decode(AntennaEntry.self, from: empty) == AntennaEntry())
        #expect(try JSONDecoder().decode(TransverterEntry.self, from: empty) == TransverterEntry())
        #expect(try JSONDecoder().decode(BandNote.self, from: empty) == BandNote())
        #expect(try JSONDecoder().decode(BlacklistEntry.self, from: empty) == BlacklistEntry())
        #expect(try JSONDecoder().decode(FunctionKeyMessage.self, from: empty) == FunctionKeyMessage())
        #expect(try JSONDecoder().decode(DxClusterFavorite.self, from: empty) == DxClusterFavorite())
        #expect(try JSONDecoder().decode(DxClusterCommand.self, from: empty) == DxClusterCommand())
        // WindowPlacement is deliberately missing: it is a stateless utility (a caseless enum),
        // not a data record — it has no fields or Codable conformance to decode.
    }

    /// `SkedEntry.id` is generated randomly in Java (`UUID.randomUUID()`) when missing —
    /// just like for a fresh `SkedEntry()`. Two independently generated UUIDs
    /// never equal each other, so `id` is compared separately (only for non-emptiness) and
    /// the other fields by full equality.
    @Test func emptyJsonEqualsDefaultsForSkedEntryExceptId() throws {
        let empty = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(SkedEntry.self, from: empty)
        let fresh = SkedEntry()
        #expect(!decoded.id.isEmpty)
        #expect(!fresh.id.isEmpty)
        #expect(decoded.call == fresh.call)
        #expect(decoded.freqHz == fresh.freqHz)
        #expect(decoded.mode == fresh.mode)
        #expect(decoded.atUtc == fresh.atUtc)
        #expect(decoded.note == fresh.note)
    }

    /// Regression test: the `didSet` normalisation of `call` (trim+uppercase) does not run
    /// on the first assignment inside the type's own init (Swift does not call observers
    /// during initialisation of its own type) — both initialisations must therefore
    /// normalise explicitly.
    @Test func decodingNormalizesCall() throws {
        let json = Data(#"{"call":"  ok1xoe  "}"#.utf8)
        let decoded = try JSONDecoder().decode(SkedEntry.self, from: json)
        #expect(decoded.call == "OK1XOE")
    }

    @Test func memberwiseInitNormalizesCall() {
        let entry = SkedEntry(call: "  ok1xoe  ", freqHz: 0, mode: "", atUtc: "", note: "")
        #expect(entry.call == "OK1XOE")
    }

    // MARK: - WindowGeometryTest

    @Test func freshGeometryHasNoSize() {
        #expect(WindowGeometry().hasSize() == false)
    }

    @Test func fullConstructorStoresValues() {
        let g = WindowGeometry(x: 10, y: 20, width: 300, height: 400)
        #expect(g.x == 10)
        #expect(g.y == 20)
        #expect(g.width == 300)
        #expect(g.height == 400)
        #expect(g.hasSize() == true)
    }

    @Test func zeroOrNegativeSizeIsNotValid() {
        #expect(WindowGeometry(x: 0, y: 0, width: 0, height: 400).hasSize() == false)
        #expect(WindowGeometry(x: 0, y: 0, width: 300, height: 0).hasSize() == false)
        #expect(WindowGeometry(x: 0, y: 0, width: -5, height: -5).hasSize() == false)
    }

    // MARK: - WindowPlacementTest

    private static let primary: [CGRect] = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]

    @Test func fullyOnScreenKeepsPosition() {
        let r = WindowPlacement.clampToScreens(x: 100, y: 100, width: 320, height: 640, screens: Self.primary)
        #expect(r?.x == 100)
        #expect(r?.y == 100)
    }

    @Test func offScreenRightGetsClampedInside() {
        // x=1900 + w=320 = 2220 > 1920 → x is reduced to 1920-320 = 1600
        let r = WindowPlacement.clampToScreens(x: 1900, y: 100, width: 320, height: 640, screens: Self.primary)
        #expect(r?.x == 1600)
        #expect(r?.y == 100)
    }

    @Test func negativeYGetsClampedToTop() {
        let r = WindowPlacement.clampToScreens(x: 100, y: -300, width: 320, height: 640, screens: Self.primary)
        #expect(r?.x == 100)
        #expect(r?.y == 0)
    }

    @Test func fullyOffScreenReturnsNil() {
        let r = WindowPlacement.clampToScreens(x: 99999, y: 99999, width: 320, height: 640, screens: Self.primary)
        #expect(r == nil)
    }

    @Test func emptyScreensReturnsNil() {
        let r = WindowPlacement.clampToScreens(x: 100, y: 100, width: 320, height: 640, screens: [])
        #expect(r == nil)
    }

    @Test func windowLargerThanScreenAlignsTopLeft() {
        let r = WindowPlacement.clampToScreens(x: 50, y: 50, width: 3000, height: 2000, screens: Self.primary)
        #expect(r?.x == 0)
        #expect(r?.y == 0)
    }

    @Test func keepsWindowOnSecondaryScreen() {
        let two: [CGRect] = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let r = WindowPlacement.clampToScreens(x: 2200, y: 100, width: 320, height: 640, screens: two)
        #expect(r?.x == 2200)
        #expect(r?.y == 100)
    }

    // MARK: - MenuStateTest

    @Test func parsesLowercase() throws {
        let decoded = try JSONDecoder().decode(MenuState.self, from: Data(#""disable""#.utf8))
        #expect(decoded == .disable)
    }

    @Test func caseInsensitive() throws {
        let decoded = try JSONDecoder().decode(MenuState.self, from: Data(#""Hidden""#.utf8))
        #expect(decoded == .hidden)
    }

    @Test func nullDefaultsEnable() throws {
        let decoded = try JSONDecoder().decode(MenuState.self, from: Data("null".utf8))
        #expect(decoded == .enable)
    }

    @Test func unknownDefaultsEnable() throws {
        let decoded = try JSONDecoder().decode(MenuState.self, from: Data(#""wat""#.utf8))
        #expect(decoded == .enable)
    }

    @Test func jsonValueLowercase() throws {
        let data = try JSONEncoder().encode(MenuState.hidden)
        #expect(String(data: data, encoding: .utf8) == "\"hidden\"")
    }
}

// MARK: - `SkedEntry`: callsign normalisation and emptiness of `id`

/// `SkedEntry.java` has **two different** whitespace sets on two fields:
/// - `setCall`: `call.trim().toUpperCase()` — characters ≤ U+0020; U+00A0, U+2007
///   nor DEL (U+007F) are dropped,
/// - `setId`: `id == null || id.isBlank()` → a new UUID — that is
///   `Character.isWhitespace`, where U+00A0 is **not** white, but U+3000 is.
///
/// The Java tests mention only the `normalizeCall` row; `setId` in Java
/// runs on `isBlank()`, so it had to be fixed too — Java decides.
///
/// Measured on Java v1.1.1 (JDK 21, `-Duser.language=en`):
/// | input | `setCall` | `setId` → new UUID? |
/// |---|---|---|
/// | `ok1xoe` | `OK1XOE` | no |
/// | `\u{0001}OK1XOE` | `OK1XOE` | no |
/// | `\tOK1XOE` | `OK1XOE` | no |
/// | `OK1XOE  ` | `OK1XOE` | no |
/// | `\u{00A0}OK1XOE` | `\u{00A0}OK1XOE` | no |
/// | `\u{2007}OK1XOE` | `\u{2007}OK1XOE` | no |
/// | `\u{007F}OK1XOE` | `\u{007F}OK1XOE` | no |
/// | `\u{00A0}` | `\u{00A0}` | **no** |
/// | `   ` | `` (empty) | yes |
/// | `` | `` (empty) | yes |
@Suite struct SkedEntryNormalizationTests {

    private func sked(_ call: String) -> SkedEntry {
        SkedEntry(call: call, freqHz: 14_025_000, mode: "CW", atUtc: "2026-11-28T14:00:00Z", note: "")
    }

    @Test func callsignIsTrimmedWithJavaTrim() {
        #expect(sked("ok1xoe").call == "OK1XOE")
        #expect(sked("\u{0001}OK1XOE").call == "OK1XOE")
        #expect(sked("\tOK1XOE").call == "OK1XOE")
        #expect(sked("OK1XOE  ").call == "OK1XOE")
        #expect(sked("   ").call == "")
        // Non-breaking spaces and DEL are not dropped by Java `trim()`.
        #expect(sked("\u{00A0}OK1XOE").call == "\u{00A0}OK1XOE")
        #expect(sked("OK1XOE\u{00A0}").call == "OK1XOE\u{00A0}")
        #expect(sked("\u{2007}OK1XOE").call == "\u{2007}OK1XOE")
        #expect(sked("\u{007F}OK1XOE").call == "\u{007F}OK1XOE")
        #expect(sked("\u{00A0}").call == "\u{00A0}")
    }

    /// The normalisation also applies on later mutation (`didSet`).
    @Test func callsignIsNormalizedOnMutationToo() {
        var s = SkedEntry()
        s.call = "\u{0001}ok1xoe"
        #expect(s.call == "OK1XOE")
        s.call = "\u{00A0}ok1xoe"
        #expect(s.call == "\u{00A0}OK1XOE")
    }

    /// `id` from JSON: a new UUID only where Java `isBlank()` returns `true`.
    @Test func idIsRegeneratedPerJavaIsBlank() throws {
        func decodedId(_ json: String) throws -> String {
            try JSONDecoder().decode(SkedEntry.self, from: Data(json.utf8)).id
        }
        // `isBlank()` = false → the id stays exactly as it came.
        #expect(try decodedId(#"{"id":" "}"#) == "\u{00A0}")
        #expect(try decodedId(#"{"id":"\u0001"}"#) == "\u{0001}")
        #expect(try decodedId(#"{"id":"\u007f"}"#) == "\u{007F}")
        #expect(try decodedId(#"{"id":" "}"#) == "\u{2007}")
        #expect(try decodedId(#"{"id":" abc "}"#) == " abc ")
        // `isBlank()` = true → a new UUID (36 characters, different from the input).
        for blank in [#"{"id":""}"#, #"{"id":"   "}"#, #"{"id":"　"}"#, #"{"id":"\t\n"}"#, "{}"] {
            let id = try decodedId(blank)
            #expect(id.count == 36, "\(blank) should have produced a new UUID, produced \(id)")
        }
    }

    /// A callsign from JSON is normalised the same as in init.
    @Test func callsignFromJson() throws {
        func decodedCall(_ json: String) throws -> String {
            try JSONDecoder().decode(SkedEntry.self, from: Data(json.utf8)).call
        }
        #expect(try decodedCall(#"{"call":"\u0001ok1xoe"}"#) == "OK1XOE")
        #expect(try decodedCall(#"{"call":" ok1xoe"}"#) == "\u{00A0}OK1XOE")
    }
}
