import Testing
@testable import MCLCore

/// Port of `audio/AudioToRfTest` (1 test, same name).
@Suite struct AudioToRfTests {

    @Test func mapsByMode() {
        #expect(AudioToRf.rfHz(dialHz: 14_025_000, rawMode: "CW", audioHz: 600, cwPitch: 600) == 14_025_000,
                "tón na pitchi = displej")
        #expect(AudioToRf.rfHz(dialHz: 14_025_000, rawMode: "CW", audioHz: 800, cwPitch: 600) == 14_025_200)
        #expect(AudioToRf.rfHz(dialHz: 14_025_000, rawMode: "CWR", audioHz: 800, cwPitch: 600) == 14_024_800)
        #expect(AudioToRf.rfHz(dialHz: 14_200_000, rawMode: "USB", audioHz: 1500, cwPitch: 600) == 14_201_500)
        #expect(AudioToRf.rfHz(dialHz: 7_100_000, rawMode: "LSB", audioHz: 1500, cwPitch: 600) == 7_098_500)
    }
}
