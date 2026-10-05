import Testing
@testable import MCLCore

/// Port of `esm/EsmProgressTest` (4) + callsign normalisation per the Java source.
@Suite struct EsmProgressTests {

    private static let opts = EsmEngine.Options(spCallOnce: false, workDupes: false)

    @Test func sentKeysUpdateFlags() {
        let p = EsmProgress.empty.afterSent([EsmEngine.f5, EsmEngine.f2], "dl6a")

        #expect(p.exchangeSent)
        #expect(!p.myCallSent)
        #expect(p.sentCall == "DL6A")
        #expect(p.afterSent([EsmEngine.f4], "DL6A").myCallSent)
    }

    @Test func correctedCallIsDetected() {
        let p = EsmProgress.empty.afterSent([EsmEngine.f5, EsmEngine.f2], "DL6A")

        #expect(!p.callCorrected("dl6a "))
        #expect(p.callCorrected("DL6ABC"))
        #expect(!EsmProgress.empty.callCorrected("DL6ABC"))
    }

    /// A whole Run QSO: three Enters (N1MM: "type a callsign, hit Enter 3 times, and you've logged a QSO").
    @Test func wholeRunQsoWithThreeEnters() {
        var p = EsmProgress.empty

        let cq = EsmEngine.decide(p.state(run: true, call: "", dupe: false, exchangeValid: false), Self.opts)
        #expect(cq.keys == [EsmEngine.f1])
        p = p.afterSent(cq.keys, "")

        let exch = EsmEngine.decide(p.state(run: true, call: "DL6ABC", dupe: false, exchangeValid: false), Self.opts)
        #expect(exch.keys == [EsmEngine.f5, EsmEngine.f2])
        p = p.afterSent(exch.keys, "DL6ABC")

        let tu = EsmEngine.decide(p.state(run: true, call: "DL6ABC", dupe: false, exchangeValid: true), Self.opts)
        #expect(tu.keys == [EsmEngine.f3])
        #expect(tu.log)
    }

    @Test func phoneLiveExchangeThenEnterSendsTuAndLogs() {
        // Run phone: the callsign and exchange were said live, space into the exchange, Enter = TU + log.
        let p = EsmProgress.empty.withExchangeSent()

        let step = EsmEngine.decide(p.state(run: true, call: "W8QZR", dupe: false, exchangeValid: true), Self.opts)

        #expect(step.keys == [EsmEngine.f3])
        #expect(step.log)
    }

    // MARK: - Beyond the Java tests (Java source `J:esm/EsmProgress.java`)

    /// `trim()` (≤ U+0020, not U+00A0), `toUpperCase(ROOT)` (`ß` → `SS`), `isBlank` per
    /// `Character.isWhitespace` and `equals` by UTF-16 units.
    @Test func normalizationFollowsJavaStringSemantics() {
        let tab = EsmProgress.empty.afterSent([EsmEngine.f5], "\u{01}ok1ß\t")
        #expect(tab.sentCall == "OK1SS")
        let nbsp = EsmProgress.empty.afterSent([EsmEngine.f5], "ok1a\u{A0}")
        #expect(nbsp.sentCall == "OK1A\u{A0}")
        #expect(EsmProgress.empty.afterSent([EsmEngine.f5], nil).sentCall == "")

        // Å (U+00C5) and A + U+030A are canonically equal, in Java not.
        let composed = EsmProgress.empty.afterSent([EsmEngine.f5], "\u{C5}")
        #expect(composed.callCorrected("A\u{30A}"))
        #expect(composed != EsmProgress.empty.afterSent([EsmEngine.f5], "A\u{30A}"))

        // U+3000 is white in Java (isBlank), U+00A0 not.
        #expect(EsmProgress.empty.state(run: true, call: "\u{3000}", dupe: false, exchangeValid: false).callEmpty)
        #expect(!EsmProgress.empty.state(run: true, call: "\u{A0}", dupe: false, exchangeValid: false).callEmpty)
        #expect(EsmProgress.empty.state(run: true, call: nil, dupe: false, exchangeValid: false).callEmpty)
    }
}
