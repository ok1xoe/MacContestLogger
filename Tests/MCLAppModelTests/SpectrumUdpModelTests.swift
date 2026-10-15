import Foundation
@testable import MCLAppModel
@testable import MCLCore
import os
import Testing

/// The spectrum display over UDP (N1MM+): an external source's datagrams on a loopback ephemeral port are shown
/// through the same pipeline (signals, picker of heard names), the relay sends the shown spectrum to a loopback
/// receiver under its name, and nothing binds or sends with the options off or the network inert. Synthetic data.
@MainActor @Suite struct SpectrumUdpModelTests {

    /// An app whose network allows the real loopback spectrum sockets (and nothing else).
    static func app() async throws -> KeyingApp {
        try await KeyingApp.make(adjust: { environment in
            environment.network.isInert = false
            environment.network.udp = UdpPorts.inert.withSpectrum(
                listener: { host, port, handler in
                    try SpectrumUdpListener(bindHost: host, bindPort: port, handler: handler)
                },
                send: { bytes, host, port in
                    try UdpSender.send(bytes, host: host, port: port)
                })
        })
    }

    /// 400 levels of 25 Hz from 14020 kHz with one signal at 14025 kHz.
    static func packet(name: String) -> SpectrumPacket {
        var levels = [Int](repeating: 20, count: 400)
        for i in 198...202 {
            levels[i] = 140
        }
        return SpectrumPacket(app: "Test SDR", name: name, lowKHz: 14_020, highKHz: 14_029.975, scalingFactor: 0.5,
                              levels: levels)
    }

    @Test func anExternalSourceIsShownThroughThePipeline() async throws {
        let app: KeyingApp = try await Self.app()
        let model: WaterfallModel = app.model.makeWaterfall()
        model.updateSetup { setup in
            setup.source = .external
            setup.set(.udpReceive, flag: true)
            setup.set(.udpBind, "127.0.0.1:0")
        }
        #expect(model.receivePort == nil)
        await model.open()
        await model.settleSockets()
        await runMainQueue()
        let port: Int = try #require(model.receivePort)
        #expect(port > 0)
        #expect(model.infoLine.text.czech == "Čekám na spektrum přes UDP…")
        try UdpSender.send(SpectrumXml.serialize(Self.packet(name: "SDR A")), host: "127.0.0.1", port: port)
        await eventually("datagram") { model.externalSource.currentName == "SDR A" }
        app.radioClock.advance(by: 100)
        await model.settle()
        await runMainQueue()
        let picture: SpectrumPicture = try #require(model.picture)
        #expect(picture.count == 400)
        #expect(picture.axis.startHz == 14_020_000)
        #expect(picture.signals.count == 1)
        #expect(abs((picture.signals.first?.centerHz ?? 0) - 14_025_000) < 1)
        #expect(model.heardSources == ["SDR A"])
        #expect(model.infoLine.text.czech == "Spektrum přes UDP: SDR A")
        #expect(model.image != nil)
        // A click on the signal tunes the rig on the band.
        app.model.rig.tuneTo(14_024_000)
        let at: Double = try #require(model.fraction(ofHz: 14_025_300))
        model.press(fraction: at, command: false, inSpectrum: true)
        #expect(abs(app.model.rig.tuning.tunedFreqHz - 14_025_000) <= 10)
        // Receiving off: the socket goes.
        model.updateSetup { $0.set(.udpReceive, flag: false) }
        #expect(model.receivePort == nil)
        model.close()
        await app.settle()
    }

    @Test func theRelaySendsTheShownSpectrumUnderItsName() async throws {
        let app: KeyingApp = try await Self.app()
        let received = OSAllocatedUnfairLock<[SpectrumPacket]>(initialState: [])
        let station = try SpectrumUdpListener(bindHost: "127.0.0.1", bindPort: 0) { packet in
            received.withLock { $0.append(packet) }
        }
        station.start()
        let model: WaterfallModel = app.model.makeWaterfall()
        app.model.rig.tuneTo(14_025_000)
        model.updateSetup { setup in
            setup.set(.relayEnabled, flag: true)
            setup.set(.relayTargets, "127.0.0.1:" + String(station.boundPort))
            setup.set(.relayName, "OK1 audio")
        }
        await model.open()
        try RadioSignals.feed(app, SpectrumPaneModelTests.noisyTone(1_000, 4_096 * 3))
        app.radioClock.advance(by: 100)
        await model.settle()
        await runMainQueue()
        await model.settleSockets()
        await eventually("relayed") { !received.withLock { $0 }.isEmpty }
        let packet: SpectrumPacket = try #require(received.withLock { $0 }.first)
        #expect(packet.name == "OK1 audio")
        #expect(packet.app == "MacContestLogger")
        #expect(packet.levels.count == 512)
        #expect(packet.lowKHz == 14_025)
        // The tone stands out in the relayed levels at 14026 kHz.
        let peak: Int = try #require(packet.levels.indices.max { packet.levels[$0] < packet.levels[$1] })
        let peakHz: Double = packet.frame.hz(atBin: Double(peak))
        #expect(abs(peakHz - 14_026_000) < 20)
        model.close()
        station.close()
        await station.waitUntilStopped()
        await app.settle()
    }

    @Test func nothingBindsOrSendsWhenOffOrInert() async throws {
        let live: KeyingApp = try await Self.app()
        let model: WaterfallModel = live.model.makeWaterfall()
        await model.open()
        await model.settleSockets()
        await runMainQueue()
        // Off by default.
        #expect(model.receivePort == nil)
        #expect(!model.setup.flag(.relayEnabled))
        model.close()
        // The inert network (MCL_INERT_NETWORK, the default of the tests): even switched on nothing binds.
        let inert: KeyingApp = try await KeyingApp.make()
        let quiet: WaterfallModel = inert.model.makeWaterfall()
        quiet.updateSetup { setup in
            setup.set(.udpReceive, flag: true)
            setup.set(.udpBind, "127.0.0.1:0")
        }
        await quiet.open()
        await quiet.settleSockets()
        await runMainQueue()
        #expect(quiet.receivePort == nil)
        quiet.close()
        await live.settle()
        await inert.settle()
    }
}
