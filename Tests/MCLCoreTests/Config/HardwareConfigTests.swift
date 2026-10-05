import Foundation
import Testing
@testable import MCLCore

@Suite struct HardwareConfigTests {

    // MARK: - An empty JSON gives the same values as init()

    @Test func emptyJsonEqualsDefaults() throws {
        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(RigConfig.self, from: empty) == RigConfig())
        #expect(try JSONDecoder().decode(CwKeyerConfig.self, from: empty) == CwKeyerConfig())
        #expect(try JSONDecoder().decode(VoiceKeyerConfig.self, from: empty) == VoiceKeyerConfig())
        #expect(try JSONDecoder().decode(DigitalConfig.self, from: empty) == DigitalConfig())
    }

    // MARK: - CwKeyerConfigTest

    @Test func cwDefaultsFollowN1mmCwMessages() {
        let c = CwKeyerConfig()
        #expect(c.method == .cat)
        #expect(c.runMessages[0].text == "cq test {MYCALL} {MYCALL} test")
        #expect(c.spMessages[0].text == "qrl? de {MYCALL}")
        #expect(c.runMessages[11].text == "{WIPE}")
        #expect(c.spMessages.count == VoiceKeyerConfig.keyCount)
    }

    /// Replaces the Java `roundTripThroughConfigStore`: `ConfigStore`/`AppConfig`
    /// already exist in Swift (`cwKeyer` is one of the nested configurations
    /// `AppConfig` — see `ConfigStoreTests` and `RealConfigCompatibilityTests`),
    /// this test nevertheless stays as a lower-level check directly over
    /// `CwKeyerConfig` itself, without going through the whole `AppConfig`.
    @Test func cwRoundTripsThroughJson() throws {
        var c = CwKeyerConfig()
        c.method = .winkeyer
        c.winkeyerPort = "/dev/cu.usbserial-A10"
        c.speed = 32
        c.cutNumbers = true

        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(CwKeyerConfig.self, from: data)

        #expect(back.method == .winkeyer)
        #expect(back.winkeyerPort == "/dev/cu.usbserial-A10")
        #expect(back.speed == 32)
        #expect(back.cutNumbers == true)
    }

    @Test func cwSpeedIsClampedAndListsPadded() {
        var c = CwKeyerConfig()
        c.speed = 200
        c.runMessages = [FunctionKeyMessage(label: "CQ", text: "cq")]

        #expect(c.speed == CwKeyerConfig.maxWpm)
        #expect(c.runMessages.count == VoiceKeyerConfig.keyCount)
    }

    // MARK: - VoiceKeyerConfigTest

    @Test func voiceDefaultsFollowN1mmSsbMessages() {
        let c = VoiceKeyerConfig()
        #expect(c.runMessages.count == VoiceKeyerConfig.keyCount)
        #expect(c.spMessages.count == VoiceKeyerConfig.keyCount)
        #expect(c.runMessages[0].text == "{OPERATOR}/CQ.wav")
        #expect(c.runMessages[3].label == "{MYCALL}")
    }

    @Test func voiceRoundTripsThroughJson() throws {
        var c = VoiceKeyerConfig()
        c.outputDevice = "USB Audio CODEC"
        c.pttViaCat = false
        c.pttDelayMs = 80
        c.runMessages[4] = FunctionKeyMessage(label: "His Call", text: "!")

        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(VoiceKeyerConfig.self, from: data)

        #expect(back.outputDevice == "USB Audio CODEC")
        #expect(back.pttViaCat == false)
        #expect(back.pttDelayMs == 80)
        #expect(back.runMessages[4].text == "!")
    }

    @Test func voiceShortOrMissingListsArePaddedToTwelve() throws {
        var c = VoiceKeyerConfig()
        c.runMessages = [FunctionKeyMessage(label: "CQ", text: "cq.wav")]
        #expect(c.runMessages.count == VoiceKeyerConfig.keyCount)
        #expect(c.runMessages[0].text == "cq.wav")

        // Java `setSpMessages(null)` has no direct equivalent in Swift (the field
        // is not Optional) — the same behaviour (a missing/`null` list → the default)
        // is verified by decoding `null` from JSON.
        let json = Data(#"{"spMessages": null}"#.utf8)
        let decoded = try JSONDecoder().decode(VoiceKeyerConfig.self, from: json)
        #expect(decoded.spMessages.count == VoiceKeyerConfig.keyCount)
    }

    @Test func voiceValuesAreClamped() {
        var c = VoiceKeyerConfig()
        c.pttDelayMs = -5
        c.maxRecordSeconds = 0
        c.lettersPath = " "

        #expect(c.pttDelayMs == 0)
        #expect(c.maxRecordSeconds == 1)
        #expect(c.lettersPath == VoiceKeyerConfig.defaultLettersPath)
    }

    // MARK: - DigitalConfigTest

    @Test func digitalDefaultsAndNormalization() throws {
        var c = DigitalConfig()
        #expect(c.engine == .none)
        #expect(c.fldigiPort == 7362)
        #expect(c.runMessages.count == 12)

        c.runMessages = [FunctionKeyMessage(label: "Cq", text: "CQ")]
        #expect(c.runMessages.count == 12)
        #expect(c.runMessages[0].text == "CQ")

        let json = Data(#"{"spMessages": null}"#.utf8)
        let decoded = try JSONDecoder().decode(DigitalConfig.self, from: json)
        #expect(decoded.spMessages[0].text == DigitalConfig.defaultSp()[0].text)

        c.fldigiPort = 0
        c.fldigiHost = " "
        #expect(c.fldigiPort == 7362)
        #expect(c.fldigiHost == "127.0.0.1")
    }

    // MARK: - CutStyleTest
    //
    // `CutStyle` (`Sources/MCLCore/Keyer/CutStyle.swift`) mirrors the Java
    // `keyer.CutStyle` — a required dependency of `CwKeyerConfig.cutStyle`, even though
    // nothing else pulls it in. `n1mmExamples` and
    // `leadingStylesKeepLoneZero` are a verbatim port of `CutStyleTest.java`
    // (same inputs, same expected outputs). `builderUsesConfiguredStyle` is
    // ported with `CwMessageBuilder`.

    @Test func n1mmExamples() {
        #expect(CutStyle.leadingT.apply("007") == "TT7")
        #expect(CutStyle.leadingT.apply("030") == "T30")
        #expect(CutStyle.leadingO.apply("007") == "OO7")
        #expect(CutStyle.leadingO.apply("030") == "O30")
        #expect(CutStyle.allT.apply("007") == "TT7")
        #expect(CutStyle.allT.apply("030") == "T3T")
        #expect(CutStyle.allO.apply("030") == "O3O")
        #expect(CutStyle.tn.apply("097") == "TN7")
        #expect(CutStyle.tn.apply("090") == "TNT")
        #expect(CutStyle.on.apply("097") == "ON7")
        #expect(CutStyle.on.apply("090") == "ONO")
        #expect(CutStyle.tan.apply("091") == "TNA")
        #expect(CutStyle.tan.apply("190") == "ANT")
        #expect(CutStyle.taen.apply("091") == "TNA")
        #expect(CutStyle.taen.apply("1590") == "AENT")
        #expect(CutStyle.tauedn.apply("012589") == "TAUEDN")
    }

    @Test func leadingStylesKeepLoneZero() {
        #expect(CutStyle.leadingT.apply("0") == "0")
        #expect(CutStyle.leadingT.apply("10") == "10")
    }

    @Test func builderUsesConfiguredStyle() {
        let ctx = CwMessageBuilder.Context(
            myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 190, rst: "599", exchange: "",
            cutNumbers: true, leadingZeros: false, roverQth: "", countyLine: [], cutStyle: .tan)

        #expect(CwMessageBuilder.build("#", ctx).plainText() == "ANT")
    }

    /// Measurement of `CUT.apply` (maintainer-only probe, no Java ancestor): all styles × 14 inputs
    /// including non-digits, Arabic digits and a combining character after a zero (Java goes by UTF-16 units:
    /// `0\u{0301}` → `T\u{0301}`). Fingerprint = `grep '^CUT.apply' out-en_US.tsv | shasum -a 256`.
    @Test func measuredCutStyleApply() {
        let inputs = ["", "0", "00", "007", "030", "097", "100", "0a0", "a00", "-07", "\u{0660}\u{0667}", "0\u{0301}",
                      "9999", "0000"]
        var rows: [String] = []
        for style in CutStyle.allCases {
            for input in inputs {
                rows.append(ProbeText.row("CUT.apply", [style.rawValue, ProbeText.esc(input),
                                                          ProbeText.esc(style.apply(input))]))
            }
        }
        #expect(rows.count == 126)
        #expect(ProbeText.digest(rows) == "f9e609878c5b48e2bf5d9496fe0ccaa64d4ca0071e979473b76319ae6a73daea")
        #expect(CutStyle.leadingT.apply("0\u{0301}") == "T\u{0301}")
    }

    /// No Java ancestor — guards the wire format (Jackson serialises by
    /// constant name, `CutStyle` in Java has no `@JsonValue`).
    @Test func cutStyleRawValueMatchesJavaConstantName() throws {
        let data = try JSONEncoder().encode(CutStyle.tn)
        #expect(String(data: data, encoding: .utf8) == "\"TN\"")
    }
}
