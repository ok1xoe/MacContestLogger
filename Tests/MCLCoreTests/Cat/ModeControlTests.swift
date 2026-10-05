import Testing
@testable import MCLCore

/// Port of `cat/ModeControlTest` + `MC.loggedMode` measurements (192 combinations, a maintainer-only probe).
@Suite struct ModeControlTests {

    @Test func loggedModeRules() {
        #expect(ModeControl.loggedMode(.radio, radio: .ssb, bandplan: .cw, always: .rtty) == .ssb)
        #expect(ModeControl.loggedMode(.bandplan, radio: .ssb, bandplan: .cw, always: nil) == .cw)
        #expect(ModeControl.loggedMode(.bandplan, radio: .ft8, bandplan: .digi, always: nil) == .ft8)
        #expect(ModeControl.loggedMode(.bandplan, radio: .ssb, bandplan: .digi, always: nil) == .digital)
        #expect(ModeControl.loggedMode(.bandplan, radio: .ssb, bandplan: nil, always: nil) == .ssb, "outside the band plan = rig")
        #expect(ModeControl.loggedMode(.always, radio: .ssb, bandplan: nil, always: .rtty) == .rtty)
    }

    /// Java switches the global `HamlibModes.configure` and restores it in `@AfterEach`; Swift takes the value of
    /// `HamlibModeMapping`, so no cleanup is needed.
    @Test func dataModeAndRttyAfsk() {
        let ft8Afsk = HamlibModeMapping(dataMode: .ft8, rttyAfsk: true)
        #expect(ft8Afsk.toMode("PKTUSB") == .ft8)
        #expect(ft8Afsk.toHamlib(.rtty, freqHz: 14_080_000) == "PKTLSB")
        let ssbFsk = HamlibModeMapping(dataMode: .ssb, rttyAfsk: false)
        #expect(ssbFsk.toMode("PKTUSB") == .digital, "a non-data mode is not accepted")
        #expect(ssbFsk.toHamlib(.rtty, freqHz: 14_080_000) == "RTTY")
    }

    /// Rows of `MC.loggedMode` by rules (`null`, RADIO, BANDPLAN, ALWAYS); inside the rig
    /// `{null, SSB, CW, FT8, RTTY, DIGITAL}` × band plan `{null, CW, PHONE, DIGI}` × always `{null, RTTY}`.
    @Test func measuredAllCombinations() {
        let radioRow = "null null null null null null null null SSB SSB SSB SSB SSB SSB SSB SSB CW CW CW CW CW CW CW CW "
            + "FT8 FT8 FT8 FT8 FT8 FT8 FT8 FT8 RTTY RTTY RTTY RTTY RTTY RTTY RTTY RTTY "
            + "DIGITAL DIGITAL DIGITAL DIGITAL DIGITAL DIGITAL DIGITAL DIGITAL"
        let bandplanRow = "null null CW CW SSB SSB DIGITAL DIGITAL SSB SSB CW CW SSB SSB DIGITAL DIGITAL "
            + "CW CW CW CW SSB SSB DIGITAL DIGITAL FT8 FT8 CW CW SSB SSB FT8 FT8 RTTY RTTY CW CW SSB SSB RTTY RTTY "
            + "DIGITAL DIGITAL CW CW SSB SSB DIGITAL DIGITAL"
        let alwaysRow = "null RTTY null RTTY null RTTY null RTTY SSB RTTY SSB RTTY SSB RTTY SSB RTTY "
            + "CW RTTY CW RTTY CW RTTY CW RTTY FT8 RTTY FT8 RTTY FT8 RTTY FT8 RTTY "
            + "RTTY RTTY RTTY RTTY RTTY RTTY RTTY RTTY DIGITAL RTTY DIGITAL RTTY DIGITAL RTTY DIGITAL RTTY"
        let rows: [(ModeControl.Rule?, String)] = [
            (nil, radioRow), (.radio, radioRow), (.bandplan, bandplanRow), (.always, alwaysRow),
        ]
        let radios: [Mode?] = [nil, .ssb, .cw, .ft8, .rtty, .digital]
        let categories: [BandPlan.ModeCategory?] = [nil, .cw, .phone, .digi]
        let always: [Mode?] = [nil, .rtty]
        for (rule, expected) in rows {
            var results: [String] = []
            for radio in radios {
                for category in categories {
                    for fixed in always {
                        let mode = ModeControl.loggedMode(rule, radio: radio, bandplan: category, always: fixed)
                        results.append(mode?.rawValue ?? "null")
                    }
                }
            }
            #expect(results.joined(separator: " ") == expected, "\(String(describing: rule))")
        }
    }

    /// Rule names as the Java enum (in `config.json` as `modeRule`).
    @Test func ruleNames() {
        #expect(ModeControl.Rule.allCases.map(\.rawValue) == ["RADIO", "BANDPLAN", "ALWAYS"])
    }
}
