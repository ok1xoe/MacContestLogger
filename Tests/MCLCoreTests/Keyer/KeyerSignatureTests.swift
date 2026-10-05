import Testing
@testable import MCLCore

/// `KeyerSignature` (`AS:1471-1490`, `AS:1554-1562`) and `KeyerTexts` (`tr` vs. verbatim as Kotlin).
@Suite struct KeyerSignatureTests {

    @Test func signatureIsMethodAndPortWithoutTheSpeed() {
        #expect(KeyerSignature.of(method: .winkeyer, port: "/dev/cu.fake") == "WINKEYER|/dev/cu.fake")
        #expect(KeyerSignature.of(method: .cat, port: "") == "CAT|")
        #expect(KeyerSignature.of(method: .none, port: "x") == "NONE|x")
        #expect(KeyerSignature.of(method: .cat, port: "a") != KeyerSignature.of(method: .cat, port: "b"))
        #expect(KeyerSignature.fldigi(host: "127.0.0.1", port: 7362) == "127.0.0.1:7362")
    }

    @Test func keyerTexts() {
        #expect(KeyerTexts.cwFailure("CW přes CAT: TRX není připojený")
                == .verbatim("CW: CW přes CAT: TRX není připojený"))
        #expect(KeyerTexts.fldigiFailure(nil, host: "localhost", port: 7362).czech
                == "fldigi: nedostupné (běží fldigi s XML-RPC na localhost:7362?)")
        #expect(KeyerTexts.fldigiFailure(nil, host: "h", port: 1).parts[1] == ContestMessage("nedostupné", parts: []))
        #expect(KeyerTexts.fldigiFailure("Connection refused", host: "h", port: 1)
                == .verbatim("fldigi: ").appending(.verbatim("Connection refused"))
                    .appending(.verbatim(" (běží fldigi s XML-RPC na h:1?)")))
        #expect(KeyerTexts.repeatLabel(2.25) == "2.3 s")
        #expect(KeyerTexts.cqRepeat(true, seconds: 1.8).czech
                == "Opakování CQ po 1.8 s (Esc nebo psaní volačky zastaví, Ctrl+R změní)")
        #expect(KeyerTexts.cqRepeat(false, seconds: 1.8) == .tr("Opakování CQ vypnuto"))
        #expect(KeyerTexts.repeatPause(2.5) == .verbatim("Pauza mezi CQ 2.5 s"))
        #expect(KeyerTexts.postContest.czech == "Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
        // `String.format(Locale.US, "%.0f", hz / 1000.0)`: Java's HALF_UP.
        #expect(KeyerTexts.moveKHz(14_025_400) == "14025")
        #expect(KeyerTexts.moveKHz(14_025_500) == "14026")
        #expect(KeyerTexts.moveKHz(7_012_500) == "7013")
    }
}
