import Foundation
import Testing
@testable import MCLCore

/// Tests of `CtyDxccResolver`.
///
/// The first eight tests are a port of the Java `CtyDxccResolverTest` (7) and
/// `CtyDxccResolverLatLonTest` (1), including their fixture. The rest pins
/// behaviour **measured on Java v1.1.1**: the shape
/// of the `cty.dat` format, malformed and hostile inputs, Java number-parsing rules
/// and cutting the callsign by UTF-16 units.
@Suite struct CtyDxccResolverTests {

    /// Mini cty.dat (AD1C format): header of 8 fields + aliases, terminated by `;`.
    /// Same content as the Java fixture in `CtyDxccResolverTest`.
    static let ctySource = """
        Czech Republic:           15:  28:  EU:   49.81:    15.47:    -1.0:  OK:
            OK,OL;
        Slovak Republic:          15:  28:  EU:   48.67:    19.70:    -1.0:  OM:
            OM;
        Fed. Rep. of Germany:     14:  28:  EU:   51.00:    10.00:    -1.0:  DL:
            DA,DB,DC,DL,DK,DM;
        United States:            05:  08:  NA:   37.53:    91.67:     5.0:  K:
            K,N,W,AA,=W1AW;
        Turkey:                   20:  39:  AS:   39.00:   -35.00:    -2.0:  TA:
            TA,TB,TC;
        """

    /// dxcc.json for the mini cty.dat — Slovakia is named differently, the OM prefix links them.
    static let dxccJson = """
        { "dxcc": [
          { "entityCode": 504, "name": "Slovakia", "prefix": "OM", "deleted": false },
          { "entityCode": 230, "name": "Germany", "prefix": "DA,DL,DK", "deleted": false },
          { "entityCode": 218, "name": "Czechoslovakia", "prefix": "OK,OL,OM", "deleted": true }
        ] }
        """

    private let cty = CtyDxccResolver.parse(CtyDxccResolverTests.ctySource)

    private func codes() throws -> DxccCodeIndex {
        try DxccCodeIndex.fromData(Data(Self.dxccJson.utf8))
    }

    // MARK: - Port of the Java CtyDxccResolverTest

    @Test func resolvesCountryAndContinent() {
        #expect(cty.resolve("OK1XOE")?.countryCode == "OK")
        #expect(cty.resolve("OK1XOE")?.primaryContinent == "EU")
        #expect(cty.resolve("OM3XYZ")?.countryCode == "OM")
        #expect(cty.resolve("DL1ABC")?.countryCode == "DL")
        #expect(cty.resolve("W1AW")?.countryCode == "K")
        #expect(cty.resolve("K5ZD")?.primaryContinent == "NA")
    }

    @Test func exposesPrimaryPrefix() {
        #expect(cty.resolve("OK1XOE")?.primaryPrefix == "OK")
        #expect(cty.resolve("DL1ABC")?.primaryPrefix == "DL")
        #expect(cty.resolve("TC1A")?.primaryPrefix == "TA")
    }

    @Test func resolvesSpecialPrefixThatRegexMisses() throws {
        // TC = Turkey (special prefix on which prefixRegex used to fail)
        let tc = try #require(cty.resolve("TC1A"))
        #expect(tc.name?.contains("Turkey") == true)
        #expect(tc.primaryContinent == "AS")
        #expect(tc.cq?.first == 20)
    }

    @Test func dxccNumbersAreFilledFromJson() throws {
        let r = CtyDxccResolver.parse(Self.ctySource, codes: try codes())
        #expect(r.resolve("OM3XYZ")?.adifDxcc == 504)
        #expect(r.resolve("DL1ABC")?.adifDxcc == 230)
    }

    @Test func withoutJsonDxccNumberStaysUnknownAndOrderIsNotTakenFromFile() throws {
        // Previously the record order in cty.dat leaked out — the ADIF then had the wrong DXCC.
        let om = try #require(cty.resolve("OM3XYZ"))
        #expect(om.adifDxcc == nil)
        #expect(om.entityCode == 2, "internal identity is preserved")
    }

    @Test func entityUnknownInJsonGetsNoNumber() throws {
        let r = CtyDxccResolver.parse(Self.ctySource, codes: try codes())
        let tc = try #require(r.resolve("TC1A"))
        #expect(tc.adifDxcc == nil)
    }

    @Test func enumeratesBaseEntitiesAndUnknownIsEmpty() {
        #expect(cty.entities().count == 5)
        #expect(cty.resolve("QZ9ZZ") == nil)
    }

    // MARK: - Port of the Java CtyDxccResolverLatLonTest

    @Test func parsesLatLonFromInlineCty() throws {
        // Minimal cty.dat record: name:CQ:ITU:Cont:Lat:Lon:GMT:Prefix:prefixlist;
        let source = "Czech Republic:          15:  28:  EU:   49.80:   -15.50:  -1.0:  OK:\n"
            + "    OK,OL,OM;\n"
        let r = CtyDxccResolver.parse(source)
        let e = try #require(r.resolve("OK1XOE"))
        #expect(e.hasLatLon)
        #expect(e.lat > 49.0 && e.lat < 51.0)
        #expect(e.lon > 14.0 && e.lon < 16.0) // -(-15.5) = +15.5 (east)
    }

    // MARK: - Format shape: what is silently skipped

    @Test func badRecordsAreSilentlySkipped() {
        // Measured on Java: no exception, just continue.
        #expect(CtyDxccResolver.parse("").entities().isEmpty)
        #expect(CtyDxccResolver.parse(";;;;").entities().isEmpty)
        #expect(CtyDxccResolver.parse("   \r\n  ").entities().isEmpty)
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 0: 0: 0: XX").entities().isEmpty, "only 8 fields")
        #expect(CtyDxccResolver.parse("X: zz: 28: EU: 0: 0: 0: XX: A").entities().isEmpty, "unreadable CQ zone")
        #expect(CtyDxccResolver.parse("X: 15: 28: : 0: 0: 0: XX: A").entities().isEmpty, "empty continent")
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 0: 0: 0: : A").entities().isEmpty, "empty prefix")
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 0: 0: 0: *: A").entities().isEmpty,
                "a lone asterisk is trimmed to empty")
        // A malformed record does not kill the rest of the file and does not raise the entity counter.
        let mixed = CtyDxccResolver.parse(
            "Bad: zz: 28: EU: 0: 0: 0: BB: B;\nGood: 15: 28: EU: 0: 0: 0: GG: G;")
        #expect(mixed.entities().count == 1)
        #expect(mixed.resolve("G1X")?.name == "Good")
        #expect(mixed.resolve("G1X")?.entityCode == 1)
    }

    @Test func recordWithoutPrefixIsInEntitiesButCannotBeResolved() throws {
        let r = CtyDxccResolver.parse("X: 15: 28: EU: 0: 0: 0: XX:")
        #expect(r.entities().count == 1)
        #expect(r.resolve("XX1A") == nil)
        let e = try #require(r.entities().first)
        #expect(e.name == "X")
        #expect(e.countryCode == "XX")
        #expect(e.cq?.first == 15)
        #expect(e.itu?.first == 28)
    }

    @Test func tenthColonPartStaysInPrefixList() {
        // Java split(":", 9): the ninth part carries the whole rest including colons.
        let r = CtyDxccResolver.parse("X: 15: 28: EU: 0: 0: 0: XX: A:B,C")
        #expect(r.entities().count == 1)
        #expect(r.resolve("C1X")?.name == "X")
        #expect(r.resolve("A1X") == nil, "key is A:B, not A")
    }

    @Test func recordWithoutTrailingSemicolonAndJunkAfterIt() {
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 1: 1: 0: XX: A").entities().count == 1)
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 1: 1: 0: XX: A;\r\nGARBAGE").entities().count == 1)
    }

    @Test func asteriskOnPrimaryPrefixIsTrimmed() throws {
        let r = CtyDxccResolver.parse("Sicily: 15: 28: EU: 37.50: -14.00: -1.0: *IT9: IT9;")
        let e = try #require(r.resolve("IT9ABC"))
        #expect(e.countryCode == "IT9")
        #expect(e.primaryPrefix == "IT9")
    }

    // MARK: - Format shape: token cleanup and overrides

    /// A single table covering all paths of key cleanup and overrides.
    /// Expected values are measured on Java, not guessed.
    @Test func tokenCleanupAndOverrides() throws {
        let content = "T: 15: 28: EU: 1: 2: 0: TT: "
            + "TT,A(9),B[44],C{SA},D<x>,E~y~,F=G,=H1I,J(,K),L(abc),M(9)(8),N[1]{AF}(7),O(,P),,  ,Q()R;"
        let r = CtyDxccResolver.parse(content)
        #expect(r.entities().count == 1)

        #expect(r.resolve("TT1X")?.cq?.first == 15)
        #expect(r.resolve("A9X")?.cq?.first == 9, "round brackets override the CQ zone")
        #expect(r.resolve("B4X")?.itu?.first == 44, "square brackets override the ITU zone")
        #expect(r.resolve("C0X")?.primaryContinent == "SA", "curly brackets override the continent")
        #expect(r.resolve("D0X") != nil, "angle brackets are stripped from the key")
        #expect(r.resolve("E0X") != nil, "tildes are stripped from the key")
        #expect(r.resolve("FG1") != nil, "the equals sign is removed even mid-token")
        #expect(r.resolve("H1I") != nil, "a token with a leading equals sign is an exact callsign")
        // An unpaired bracket is not stripped — the key keeps it, hence unresolvable.
        #expect(r.resolve("J1") == nil)
        #expect(r.resolve("K1") == nil)
        #expect(r.resolve("JK1") == nil)
        #expect(r.resolve("L1X")?.cq?.first == 15, "a non-numeric override is ignored")
        #expect(r.resolve("M1X")?.cq?.first == 9, "the first group is taken")
        let n = try #require(r.resolve("N1X"))
        #expect(n.cq?.first == 7)
        #expect(n.itu?.first == 1)
        #expect(n.primaryContinent == "AF")
        #expect(r.resolve("O1") == nil)
        #expect(r.resolve("P1") == nil)
        #expect(r.resolve("QR1") != nil, "an empty group vanishes and the key is glued together")
        #expect(r.resolve("Q1") == nil)
    }

    @Test func overrideIsReadFromOriginalTokenNotCleanedKey() {
        // The equals sign is removed only when computing the key, so the override sees =9 and fails.
        let r = CtyDxccResolver.parse("T: 15: 28: EU: 1: 2: 0: TT: A(=9);")
        #expect(r.resolve("A1X") != nil, "key is A, the whole group vanishes")
        #expect(r.resolve("A1X")?.cq?.first == 15)
    }

    @Test func keyCleanupDoesNotCrossLineEnd() {
        // Regex `.` in Java does not match a line end, so the bracket stays in the key.
        let r = CtyDxccResolver.parse("T: 15: 28: EU: 1: 2: 0: TT: A(\n9)B;")
        #expect(r.entities().count == 1)
        #expect(r.resolve("A1X") == nil)
        #expect(r.resolve("AB1") == nil)
    }

    @Test func duplicateKeyLastOneWins() {
        let pfx = CtyDxccResolver.parse(
            "First: 1: 1: EU: 1: 1: 0: F1: AA;\nSecond: 2: 2: AS: 2: 2: 0: S1: AA;")
        #expect(pfx.resolve("AA1X")?.name == "Second")
        let exact = CtyDxccResolver.parse(
            "First: 1: 1: EU: 1: 1: 0: F1: =AA1X;\nSecond: 2: 2: AS: 2: 2: 0: S1: =AA1X;")
        #expect(exact.resolve("AA1X")?.name == "Second")
    }

    // MARK: - Lookup order

    @Test func exactCallIsTriedTwiceAndTakesPrecedenceOverPrefix() {
        let raw = CtyDxccResolver.parse(
            "Base: 1: 1: EU: 1: 1: 0: B1: AA;\nExact: 2: 2: AS: 2: 2: 0: E1: =AA1X/P;")
        #expect(raw.resolve("AA1X/P")?.name == "Exact", "match on the non-normalized callsign")
        #expect(raw.resolve("aa1x/p")?.name == "Exact", "upper-casing before lookup")

        let normalized = CtyDxccResolver.parse(
            "Base: 1: 1: EU: 1: 1: 0: B1: AA;\nExact: 2: 2: AS: 2: 2: 0: E1: =AA1X;")
        #expect(normalized.resolve("AA1X/P")?.name == "Exact", "second attempt after normalization")
        #expect(normalized.resolve("AA1X/QRP")?.name == "Exact")
        #expect(normalized.resolve("  AA1X  ")?.name == "Exact", "trimming before lookup")
    }

    @Test func longestPrefixWins() {
        let r = CtyDxccResolver.parse(
            "Short: 1: 1: EU: 1: 1: 0: S: A;\nLong: 2: 2: AS: 2: 2: 0: L: AB1;")
        #expect(r.resolve("AB1CD")?.name == "Long")
        #expect(r.resolve("AB2CD")?.name == "Short")
    }

    @Test func emptyCallsignAndMemoization() {
        let r = CtyDxccResolver.parse(Self.ctySource)
        #expect(r.resolve(nil) == nil)
        #expect(r.resolve("") == nil)
        #expect(r.resolve("   ") == nil)
        // A non-breaking space is not Java isBlank, so the guard passes and the lookup is
        // literal — the result is nothing anyway (measured).
        #expect(r.resolve("\u{00A0}") == nil)
        // The second call comes from the cache and must give the same result.
        #expect(r.resolve("OK1XOE")?.entityCode == 1)
        #expect(r.resolve("OK1XOE")?.entityCode == 1)
        #expect(r.resolve("QZ9ZZ") == nil)
        #expect(r.resolve("QZ9ZZ") == nil)
    }

    @Test func prefixCuttingGoesByUtf16UnitsNotGraphemes() {
        // Measured on Java: AA + combining diaeresis + 1X resolves via substring(0, 2)
        // =  "AA". Cutting by graphemes would give AÄ and resolve nothing.
        let r = CtyDxccResolver.parse("Base: 1: 1: EU: 1: 1: 0: B1: AA;")
        #expect(r.resolve("AA\u{0308}1X")?.name == "Base")
        // An emoji does not help — both its halves are surrogates.
        #expect(r.resolve("\u{1F388}1X") == nil)
    }

    // MARK: - Java number-parsing rules

    @Test func integersAreParsedLikeJavaInteger() {
        // 32-bit range: what Java rejects we must reject too, otherwise we would
        // load a record that Java drops.
        #expect(CtyDxccResolver.javaParseInt("2147483647") == 2_147_483_647)
        #expect(CtyDxccResolver.javaParseInt("2147483648") == nil)
        #expect(CtyDxccResolver.javaParseInt("-2147483648") == -2_147_483_648)
        #expect(CtyDxccResolver.javaParseInt("-2147483649") == nil)
        #expect(CtyDxccResolver.javaParseInt("+15") == 15)
        #expect(CtyDxccResolver.javaParseInt("015") == 15)
        #expect(CtyDxccResolver.javaParseInt("١٥") == 15, "Character.digit accepts all Nd digits")
        #expect(CtyDxccResolver.javaParseInt(" 15") == nil)
        #expect(CtyDxccResolver.javaParseInt("15 ") == nil)
        #expect(CtyDxccResolver.javaParseInt("") == nil)
        #expect(CtyDxccResolver.javaParseInt("+") == nil)
        #expect(CtyDxccResolver.javaParseInt("0x10") == nil)
        #expect(CtyDxccResolver.javaParseInt("1_0") == nil)
        #expect(CtyDxccResolver.javaParseInt("1.0") == nil)
        // And it really shows on the whole record.
        #expect(CtyDxccResolver.parse("X: 99999999999: 28: EU: 0: 0: 0: XX: A;").entities().isEmpty)
        #expect(CtyDxccResolver.parse("X: ١٥: 28: EU: 0: 0: 0: XX: A;").entities().count == 1)
    }

    @Test func decimalsAreParsedLikeJavaDouble() {
        // Java accepts, Swift's Double(String) does not by itself:
        #expect(CtyDxccResolver.javaParseDouble("1.0d") == 1.0)
        #expect(CtyDxccResolver.javaParseDouble("1f") == 1.0)
        #expect(CtyDxccResolver.javaParseDouble("0x1p3") == 8.0)
        #expect(CtyDxccResolver.javaParseDouble("0x1p3d") == 8.0)
        #expect(CtyDxccResolver.javaParseDouble("0x.1p3") == 0.5)
        #expect(CtyDxccResolver.javaParseDouble("0x1.p3") == 8.0)
        #expect(CtyDxccResolver.javaParseDouble("0x1.8p1") == 3.0)
        // Swift accepts, Java does not:
        #expect(CtyDxccResolver.javaParseDouble("nan") == nil)
        #expect(CtyDxccResolver.javaParseDouble("NAN") == nil)
        #expect(CtyDxccResolver.javaParseDouble("inf") == nil)
        #expect(CtyDxccResolver.javaParseDouble("infinity") == nil)
        #expect(CtyDxccResolver.javaParseDouble("nan(0x1)") == nil)
        #expect(CtyDxccResolver.javaParseDouble("0x10") == nil, "hex without p is an error in Java")
        #expect(CtyDxccResolver.javaParseDouble("NaNd") == nil, "NaN does not take a type suffix")
        #expect(CtyDxccResolver.javaParseDouble("Infinityf") == nil)
        // Both accept:
        #expect(CtyDxccResolver.javaParseDouble("NaN")?.isNaN == true)
        #expect(CtyDxccResolver.javaParseDouble("Infinity") == .infinity)
        #expect(CtyDxccResolver.javaParseDouble("-Infinity") == -.infinity)
        #expect(CtyDxccResolver.javaParseDouble(".5") == 0.5)
        #expect(CtyDxccResolver.javaParseDouble("5.") == 5.0)
        #expect(CtyDxccResolver.javaParseDouble("1e2") == 100.0)
        #expect(CtyDxccResolver.javaParseDouble("1E2") == 100.0)
        #expect(CtyDxccResolver.javaParseDouble("1e+2") == 100.0)
        #expect(CtyDxccResolver.javaParseDouble("+1.5") == 1.5)
        #expect(CtyDxccResolver.javaParseDouble("00.5") == 0.5)
        #expect(CtyDxccResolver.javaParseDouble("  2.5  ") == 2.5, "parseDouble trims its input itself")
        // Both reject:
        for bad in ["", "-", ".", "1..", "1.2.3", "1.5e", "1.5e+", "1_0", "1 0", "0x1p", "٥.٥", "--1"] {
            #expect(CtyDxccResolver.javaParseDouble(bad) == nil, "\(bad)")
        }
    }

    @Test func unreadableCoordinateIsNaN() throws {
        let r = CtyDxccResolver.parse("X: 15: 28: EU: 1_0: zz: 0: XX: A;")
        let e = try #require(r.resolve("A1B"))
        #expect(e.lat.isNaN)
        #expect(e.lon.isNaN)
        #expect(!e.hasLatLon)
    }

    @Test func westernLongitudeIsFlippedIncludingNegativeZero() throws {
        // Antarctica from the real cty.dat has lon 0.00, so -0.0 comes out.
        // DxccEntity distinguishes it from 0.0 in equality, so the sign is not cosmetic.
        let r = CtyDxccResolver.parse("Antarctica: 13: 74: SA: -90.00: 0.00: 0.0: CE9: CE9;")
        let e = try #require(r.resolve("CE9ABC"))
        #expect(e.lon.sign == .minus)
        #expect(e.lon == 0.0)
        #expect(e.lat == -90.0)
        // And the opposite direction: -35.00 in the file is +35.0 out.
        #expect(cty.resolve("TA1AA")?.lon == 35.0)
    }

    @Test func missingItuIsEmptyListNotNil() throws {
        let r = CtyDxccResolver.parse("X: 15: zz: EU: 1: 1: 0: XX: A;")
        let e = try #require(r.resolve("A1B"))
        #expect(e.itu == [], "Java List.of(), not null")
        #expect(e.cq == [15])
        #expect(e.continents == ["EU"])
    }

    // MARK: - Bytes and stream

    @Test func bytesAreDecodedLikeJavaNewStringUtf8() throws {
        // Invalid UTF-8 becomes U+FFFD, no exception (measured: name = two U+FFFD and X).
        var bytes: [UInt8] = [0xFF, 0xFE]
        bytes.append(contentsOf: Array("X: 15: 28: EU: 1: 1: 0: XX: A;".utf8))
        let r = CtyDxccResolver.fromData(Data(bytes))
        #expect(r.entities().count == 1)
        #expect(try #require(r.entities().first).name == "\u{FFFD}\u{FFFD}X")
        // BOM is not stripped — Java trim() drops only characters up to U+0020.
        let bom = CtyDxccResolver.fromData(Data(Array("\u{FEFF}X: 15: 28: EU: 1: 1: 0: XX: A;".utf8)))
        #expect(try #require(bom.entities().first).name == "\u{FEFF}X")
    }

    @Test func streamIsReadAndReadErrorIsReportedWithOwnType() throws {
        let ok = try CtyDxccResolver.fromStream(
            InputStream(data: Data("X: 15: 28: EU: 1: 1: 0: XX: A;".utf8)))
        #expect(ok.entities().count == 1)

        // Java UncheckedIOException("Nelze načíst cty.dat", e) — deliberately a different
        // type than DxccError, which DxccResolver and DxccCodeIndex use to report.
        let broken = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/cty.dat")
        let stream = try #require(InputStream(url: broken))
        do {
            _ = try CtyDxccResolver.fromStream(stream)
            Issue.record("reading an unreadable stream should have ended with an error")
        } catch let error as CtyDxccIOError {
            #expect(error.message == "Nelze načíst cty.dat")
            #expect(error.cause != nil)
        }
    }

    // MARK: - Hostile input

    @Test func hostileInputNeitherCrashesNorHangs() {
        // Measured on Java: 100 thousand **paired** brackets = 17 ms, 200 thousand
        // tokens = 247 ms, a hundred-thousand-character prefix does not lengthen the lookup
        // (the loop is bounded by the callsign length, not the key length).
        //
        // **Paired** brackets are linear, because the whole span is discarded
        // in one jump. Unpaired ones are not — see
        // `unpairedBracketsAreQuadraticSameAsInJava`.
        let deep = "X: 15: 28: EU: 1: 1: 0: XX: A"
            + String(repeating: "(", count: 20_000) + "9"
            + String(repeating: ")", count: 20_000) + ";"
        #expect(CtyDxccResolver.parse(deep).entities().count == 1)

        var many = "X: 15: 28: EU: 1: 1: 0: XX: "
        for i in 0..<20_000 {
            many += "P\(i),"
        }
        many += "ZZ;"
        let manyResolver = CtyDxccResolver.parse(many)
        #expect(manyResolver.entities().count == 1)
        #expect(manyResolver.resolve("P19999") != nil)

        let longPrefix = "X: 15: 28: EU: 1: 1: 0: XX: " + String(repeating: "Q", count: 100_000) + ";"
        let longResolver = CtyDxccResolver.parse(longPrefix)
        #expect(longResolver.resolve("ABC") == nil)
        #expect(longResolver.entities().count == 1)

        // Deeply nested records are unknown to the format, but let it be clear that many
        // records pass without recursion.
        let manyRecords = (0..<5_000).map { "N\($0): 15: 28: EU: 1: 1: 0: P\($0): P\($0);" }
            .joined(separator: "\n")
        #expect(CtyDxccResolver.parse(manyRecords).entities().count == 5_000)
    }

    /// An unpaired bracket in a token is **quadratic** — and it is so in Java too,
    /// so it is **deliberately not optimized**: a linear version would be a divergence.
    ///
    /// Measured (one token, N unpaired `(`), Java v1.1.1 / this port:
    /// 1 000 = 9 ms / 10 ms, 2 000 = 7 ms / 32 ms, 4 000 = 30 ms / 110 ms,
    /// 8,000 = 115 ms / 437 ms, 20,000 = 718 ms / 2.7 s. Both grow ×4 when
    /// the input doubles; we are about 4× slower, but of the same shape.
    /// **A corrupted `cty.dat` therefore hangs both applications** — 200,000 characters
    /// means minutes.
    ///
    /// The semantics must match down to the last case: an unpaired bracket
    /// is not stripped (the key stays unresolvable), but `~` is both opening
    /// and closing, so tildes are discarded in pairs, it is linear and the key
    /// is **glued together** (Java measured: `resolveA1X=true`, 1 ms).
    @Test func unpairedBracketsAreQuadraticSameAsInJava() {
        // 2,000 characters keep the test under 50 ms; larger numbers are in the documentation above.
        for open in ["(", "[", "<", "{"] {
            let content = "X: 15: 28: EU: 1: 1: 0: XX: A" + String(repeating: open, count: 2_000) + ";"
            let r = CtyDxccResolver.parse(content)
            #expect(r.entities().count == 1, "\(open)")
            #expect(r.resolve("A1X") == nil, "unpaired \(open) in the key remains")
        }
        // Tilde is both opening and closing → pairs are discarded and the key is glued together.
        let tilde = "X: 15: 28: EU: 1: 1: 0: XX: A" + String(repeating: "~", count: 5_000) + ";"
        #expect(CtyDxccResolver.parse(tilde).resolve("A1X") != nil)
        // An odd number of tildes leaves the last one in the key.
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 1: 1: 0: XX: A~~~;").resolve("A1X") == nil)
        // Semantic check on a small input: the reluctant match swallows even
        // the inner brackets if a closing one is found.
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 1: 1: 0: XX: A((((B);").resolve("A1X") != nil)
        #expect(CtyDxccResolver.parse("X: 15: 28: EU: 1: 1: 0: XX: A(((;").resolve("A1X") == nil)
    }
}
