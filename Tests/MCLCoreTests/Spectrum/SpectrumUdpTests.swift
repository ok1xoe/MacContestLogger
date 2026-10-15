import Foundation
import os
import Testing
@testable import MCLCore

/// N1MM's spectrum datagram (UDP 13064): parsing the documented layout, writing it back, the relay's levels, the
/// external source and the listener on a loopback ephemeral port. Synthetic spectra only.
@Suite struct SpectrumUdpTests {

    /// The layout of the N1MM documentation (tabs, a line break and spaces inside the data).
    static let documented = """
        <?xml version="1.0" encoding="utf-8"?>
        <Spectrum>
        \t<app>WaterfallBandmap</app>
        \t<Name>NlMM SDR1</Name>
        \t<LowScopeFrequency>14000</LowScopeFrequency>
        \t<HighScopeFrequency>14055</HighScopeFrequency>
        \t<ScalingFactor>0.3125</ScalingFactor>
        \t<DataCount>12</DataCount>
        \t<SpectrumData>0,0,0,1,0,0,
        \t0,19,25,0, 0,4
        \t</SpectrumData>
        </Spectrum>
        """

    @Test func theDocumentedPacketIsRead() throws {
        let packet: SpectrumPacket = try #require(SpectrumXml.parse(Array(Self.documented.utf8)))
        #expect(packet.app == "WaterfallBandmap")
        #expect(packet.name == "NlMM SDR1")
        #expect(packet.lowKHz == 14_000)
        #expect(packet.highKHz == 14_055)
        #expect(packet.scalingFactor == 0.3125)
        #expect(packet.levels == [0, 0, 0, 1, 0, 0, 0, 19, 25, 0, 0, 4])
        let frame: SpectrumFrame = packet.frame
        #expect(frame.startHz == 14_000_000)
        #expect(frame.stepHz == 5_000)
        #expect(frame.highHz == 14_055_000)
        #expect(frame.levelsDb[8] == 25 * 0.3125)
    }

    @Test func badDatagramsAreDroppedAndOddLevelsClamped() throws {
        #expect(SpectrumXml.parse(Array("<contactinfo/>".utf8)) == nil)
        #expect(SpectrumXml.parse(Array("<Spectrum><LowScopeFrequency>7000</LowScopeFrequency></Spectrum>".utf8))
            == nil)
        let noData = "<Spectrum><LowScopeFrequency>7000</LowScopeFrequency>"
            + "<HighScopeFrequency>7010</HighScopeFrequency><SpectrumData> </SpectrumData></Spectrum>"
        #expect(SpectrumXml.parse(Array(noData.utf8)) == nil)
        let odd = "<Spectrum><Name>A&amp;B</Name><LowScopeFrequency>7000</LowScopeFrequency>"
            + "<HighScopeFrequency>7010</HighScopeFrequency><DataCount>99</DataCount>"
            + "<SpectrumData>-5,70000,x,12.6,</SpectrumData></Spectrum>"
        let packet: SpectrumPacket = try #require(SpectrumXml.parse(Array(odd.utf8)))
        #expect(packet.name == "A&B")
        #expect(packet.levels == [0, 65_535, 0, 13])
        // No ScalingFactor: the levels are dB.
        #expect(packet.scalingFactor == 1)
        #expect(packet.app == "")
    }

    @Test func aPacketIsWrittenInTheDocumentedLayoutAndReadBack() throws {
        let packet = SpectrumPacket(app: "MacContestLogger", name: "OK1 <SDR>", lowKHz: 14_000, highKHz: 14_025.5,
                                    scalingFactor: 0.25, levels: [0, 3, 65_535])
        let text = String(decoding: SpectrumXml.serialize(packet), as: UTF8.self)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Spectrum>\n"))
        #expect(text.contains("<Name>OK1 &lt;SDR&gt;</Name>"))
        #expect(text.contains("<LowScopeFrequency>14000</LowScopeFrequency>"))
        #expect(text.contains("<HighScopeFrequency>14025.5</HighScopeFrequency>"))
        #expect(text.contains("<ScalingFactor>0.25</ScalingFactor>"))
        #expect(text.contains("<DataCount>3</DataCount>"))
        #expect(text.contains("<SpectrumData>0,3,65535</SpectrumData>"))
        #expect(SpectrumXml.parse(SpectrumXml.serialize(packet)) == packet)
    }

    @Test func theRelaySendsAscendingRelativeLevels() {
        // A downward frame (receiver audio in LSB): the relay sends it from the low frequency up.
        let frame = SpectrumFrame(startHz: 7_100_000, stepHz: -1_000, levelsDb: [-100, -90, -100.4, -60])
        let packet: SpectrumPacket = SpectrumPacket.relay(frame, name: "MCL")
        #expect(packet.lowKHz == 7_097)
        #expect(packet.highKHz == 7_100)
        #expect(packet.scalingFactor == 0.25)
        // The base is the lowest level rounded down (−101 dB); 0.25 dB per unit.
        #expect(packet.levels == [164, 2, 44, 4])
        let back: SpectrumFrame = packet.frame
        #expect(back.startHz == 7_097_000)
        #expect(back.stepHz == 1_000)
        #expect(back.levelsDb[0] - back.levelsDb[2] == 30)
    }

    @Test func theExternalSourceFollowsThePickedName() {
        let source = ExternalSpectrumSource()
        let tuning = SpectrumTuning(dialHz: 0, rawMode: "", cwPitch: 600)
        #expect(source.latestFrame(tuning: tuning) == nil)
        let skimmer = SpectrumPacket(app: "", name: "CW Skimmer", lowKHz: 7_000, highKHz: 7_001, scalingFactor: 1,
                                     levels: [10, 50, 10])
        let flex = SpectrumPacket(app: "", name: "Flex", lowKHz: 14_000, highKHz: 14_001, scalingFactor: 1,
                                  levels: [1, 2, 3, 4])
        // Empty name: the first one heard.
        source.accept(skimmer)
        source.accept(flex)
        #expect(source.heardNames == ["CW Skimmer", "Flex"])
        #expect(source.currentName == "CW Skimmer")
        #expect(source.latestFrame(tuning: tuning)?.serial == 1)
        #expect(source.latestFrame(tuning: tuning)?.frame.startHz == 7_000_000)
        let rows: [[Float]] = source.waterfallRows()
        #expect(rows == [[0, 1, 0]])
        source.select("Flex")
        #expect(source.latestFrame(tuning: tuning) == nil)
        source.accept(skimmer)
        source.accept(flex)
        #expect(source.latestFrame(tuning: tuning)?.frame.count == 4)
        #expect(source.waterfallRows().count == 1)
        source.accept(flex)
        #expect(source.waterfallRows().count == 2)
        #expect(source.secondsPerFrame > 0)
    }

    @Test func theListenerReceivesOnALoopbackPort() async throws {
        let received = OSAllocatedUnfairLock<[SpectrumPacket]>(initialState: [])
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let listener = try SpectrumUdpListener(bindHost: "127.0.0.1", bindPort: 0) { packet in
            received.withLock { $0.append(packet) }
            continuation.yield()
        }
        listener.start()
        let port: Int = listener.boundPort
        #expect(port > 0)
        try UdpSender.send(Array("not a spectrum".utf8), host: "127.0.0.1", port: port)
        let packet = SpectrumPacket(app: "test", name: "Loop", lowKHz: 3_500, highKHz: 3_502, scalingFactor: 0.5,
                                    levels: [1, 2, 3])
        try UdpSender.send(SpectrumXml.serialize(packet), host: "127.0.0.1", port: port)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(received.withLock { $0 } == [packet])
        listener.close()
        await listener.waitUntilStopped()
    }

    @Test func theNetworkOptions() {
        var setup = SpectrumSetup()
        #expect(setup.source == .audio)
        #expect(!setup.flag(.udpReceive))
        #expect(!setup.flag(.relayEnabled))
        #expect(setup.text(.udpBind) == "0.0.0.0:13064")
        #expect(setup.udpBindAddress?.host == "0.0.0.0")
        #expect(setup.udpBindAddress?.port == 13_064)
        #expect(setup.text(.relayName) == "MCL")
        setup.set(.udpBind, ":13070")
        #expect(setup.udpBindAddress?.host == "0.0.0.0")
        #expect(setup.udpBindAddress?.port == 13_070)
        setup.set(.udpBind, "127.0.0.1:99999")
        #expect(setup.udpBindAddress == nil)
        setup.set(.udpBind, "nonsense")
        #expect(setup.udpBindAddress == nil)
    }
}
