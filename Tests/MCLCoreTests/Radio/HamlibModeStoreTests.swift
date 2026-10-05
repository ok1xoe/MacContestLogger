import Testing
@testable import MCLCore

/// `HamlibModeStore`: one live mapping for both rigs, changed by `configure`.
@Suite struct HamlibModeStoreTests {

    @Test func startsWithTheJavaDefault() {
        #expect(HamlibModeStore().mapping == .default)
    }

    /// Two providers taken before the change (rig 1 and rig 2) both see the new mapping at once.
    @Test func configureChangesTheMappingOfBothRigsLive() {
        let store = HamlibModeStore()
        let rig1 = store.provider
        let rig2 = store.provider
        #expect(rig1().toMode("PKTUSB") == .digital)
        #expect(rig2().toHamlib(.rtty, freqHz: 14_080_000) == "RTTY")
        store.configure(dataMode: Mode.from(adif: "FT8"), rttyAfsk: true)
        #expect(rig1().toMode("PKTUSB") == .ft8)
        #expect(rig2().toMode("PKTLSB") == .ft8)
        #expect(rig1().toHamlib(.rtty, freqHz: 14_080_000) == "PKTLSB")
        #expect(rig2().rttyAfsk)
        // A non-data mode falls back to DIGITAL as Java `configure` does.
        store.configure(dataMode: .cw, rttyAfsk: false)
        #expect(rig2().dataMode == .digital)
        #expect(!rig1().rttyAfsk)
    }
}
