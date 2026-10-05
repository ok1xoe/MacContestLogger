@testable import MCLCore
import Testing

/// The texts and input rules of the radio tool windows (`RotatorWindow.kt`, `CwReaderWindow.kt`,
/// `WaterfallWindow.kt`, `DigitalInterfaceWindow.kt`).
@Suite struct RadioWindowTextsTests {

    /// `filter { it.isDigit() }.take(n)` keeps Unicode decimal digits by UTF-16 unit.
    @Test func digitsFilter() {
        #expect(RadioWindowTexts.digits("12a3 4", limit: 3) == "123")
        #expect(RadioWindowTexts.digits("٣٠٠x", limit: 4) == "٣٠٠")
        #expect(RadioWindowTexts.digits("abc", limit: 4) == "")
        #expect(RadioWindowTexts.digits("12345", limit: 4) == "1234")
    }

    /// The reader tone applies only in 200…3000 (`toIntOrNull` accepts Unicode digits, as `Character.digit`).
    @Test func readerTone() {
        #expect(RadioWindowTexts.readerTone("200") == 200)
        #expect(RadioWindowTexts.readerTone("3000") == 3000)
        #expect(RadioWindowTexts.readerTone("199") == nil)
        #expect(RadioWindowTexts.readerTone("3001") == nil)
        #expect(RadioWindowTexts.readerTone("") == nil)
        #expect(RadioWindowTexts.readerTone("٦٠٠") == 600)
    }

    /// The rotator's field: `toDoubleOrNull` (ASCII digits only).
    @Test func rotatorField() {
        #expect(RadioWindowTexts.rotatorFieldAzimuth("270") == 270)
        #expect(RadioWindowTexts.rotatorFieldAzimuth("") == nil)
        #expect(RadioWindowTexts.rotatorFieldAzimuth("٣") == nil)
    }

    @Test func rotatorTexts() {
        #expect(RadioWindowTexts.rotatorAzimuth(nil as Double?) == "—")
        #expect(RadioWindowTexts.rotatorAzimuth(271.9) == "271°")
        #expect(RadioWindowTexts.rotatorAzimuth(-0.5) == "0°")
        #expect(RadioWindowTexts.rotatorAzimuth(Double.nan) == "0°")
        #expect(RadioWindowTexts.rotatorCallLine(call: "", target: nil).czech == "Volačka z pole: —")
        #expect(RadioWindowTexts.rotatorCallLine(call: " ", target: 10).czech == "Volačka z pole: —")
        #expect(RadioWindowTexts.rotatorCallLine(call: "DL1ABC", target: 45).czech == "DL1ABC: 45°")
        #expect(RadioWindowTexts.rotatorCallLine(call: "DL1ABC", target: nil).czech == "DL1ABC: azimut neznámý")
    }

    @Test func readerTexts() {
        #expect(RadioWindowTexts.readerWpm(0) == "~0 WPM")
        #expect(RadioWindowTexts.readerWpm(28) == "~28 WPM")
        #expect(RadioWindowTexts.readerPlaceholder("600").czech
            == "Čekám na CW na 600 Hz… (zdroj zvuku: Nastavení → Audio → Příjem)")
        #expect(RadioWindowTexts.readerAudioError("busy") == "Zvuk: busy")
    }

    /// `String.format(Locale.US, "audio %.0f Hz → %.2f kHz", …)` with Java's HALF_UP.
    @Test func waterfallTexts() {
        #expect(RadioWindowTexts.waterfallHover(audioHz: 600.5, rfHz: 14_025_005)
            == "audio 601 Hz → 14025.01 kHz")
        #expect(RadioWindowTexts.waterfallHover(audioHz: 0, rfHz: 0) == "audio 0 Hz → 0.00 kHz")
        #expect(RadioWindowTexts.waterfallInfo(rawMode: " ", pitchHz: 600).czech
            == "0–3 kHz audia přijímače · mód ? · CW tón 600 Hz")
        #expect(RadioWindowTexts.waterfallInfo(rawMode: "CWR", pitchHz: 550).czech
            == "0–3 kHz audia přijímače · mód CWR · CW tón 550 Hz")
        #expect(RadioWindowTexts.waterfallError("busy").czech
            == "Zvukový vstup: busy (Nastavení → Audio → Vstup přijímače)")
        #expect(RadioWindowTexts.showsPitchLine(rawMode: "cw"))
        #expect(RadioWindowTexts.showsPitchLine(rawMode: "CWR"))
        #expect(!RadioWindowTexts.showsPitchLine(rawMode: "USB"))
        #expect(!RadioWindowTexts.showsPitchLine(rawMode: ""))
    }

    @Test func digitalTexts() {
        #expect(RadioWindowTexts.digitalNoModem.czech
            == "Modem není nastavený — Nastavení → Digitální módy → Modem pro RTTY / PSK.")
        #expect(RadioWindowTexts.fldigiUnavailable(host: "127.0.0.1", port: 7362, message: nil).czech
            == "fldigi nedostupné (127.0.0.1:7362): null")
        #expect(RadioWindowTexts.fldigiUnavailable(host: "h", port: 1, message: "Connection refused").czech
            == "fldigi nedostupné (h:1): Connection refused")
        #expect(RadioWindowTexts.digitalStatus(modem: "RTTY", trx: "RX") == "RTTY · RX")
    }
}
