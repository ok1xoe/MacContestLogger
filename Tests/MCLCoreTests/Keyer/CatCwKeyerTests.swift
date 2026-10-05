import Foundation
import Testing
@testable import MCLCore

/// Port of `keyer/CatCwKeyerTest` (5) + `KCAT.*`, `KCK.tune` measurements (maintainer-only probe) over a
/// rig stand-in (no real radio).
@Suite struct CatCwKeyerTests {

    private static let ctx = CwMessageBuilder.Context(
        myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "15",
        cutNumbers: false, leadingZeros: false)

    private static func build(_ template: String) -> CwMessage {
        CwMessageBuilder.build(template, ctx)
    }

    /// A mutable rig source (Java `Supplier`), so that it can be swapped/disconnected between calls.
    final class RigSource: @unchecked Sendable {
        private let lock = NSLock()
        private var current: (any RigController)?

        init(_ rig: (any RigController)?) {
            current = rig
        }

        var rig: (any RigController)? {
            get { lock.lock(); defer { lock.unlock() }; return current }
            set { lock.lock(); current = newValue; lock.unlock() }
        }
    }

    private static func keyer(_ rig: (any RigController)?) -> (CatCwKeyer, RigSource) {
        let source = RigSource(rig)
        return (CatCwKeyer(rig: { source.rig }), source)
    }

    // MARK: - Port of CatCwKeyerTest

    @Test func sendsPlainTextAndSetsSpeedOnlyWhenChanged() throws {
        let rig = KeyerRecordingRig()
        let (keyer, _) = Self.keyer(rig)

        try keyer.send(Self.build("cq test *"), wpm: 28)
        try keyer.send(Self.build("tu+"), wpm: 28)
        try keyer.send(Self.build("{SENTRSTCUT} {EXCH}"), wpm: 32)

        #expect(rig.calls == ["speed 28", "morse CQ TEST OK1XOE", "morse TU AR", "speed 32", "morse 5NN 15"])
    }

    @Test func inlineSpeedChangesAreIgnoredByCat() throws {
        let rig = KeyerRecordingRig()

        try Self.keyer(rig).0.send(Self.build("<<5nn>>"), wpm: 28)

        #expect(rig.calls == ["speed 28", "morse 5NN"])
    }

    @Test func emptyMessageSendsNothing() throws {
        let rig = KeyerRecordingRig()

        try Self.keyer(rig).0.send(Self.build("{WIPE}"), wpm: 28)

        #expect(rig.calls == [])
    }

    @Test func abortStopsMorse() throws {
        let rig = KeyerRecordingRig()

        try Self.keyer(rig).0.abort()

        #expect(rig.calls == ["stop"])
    }

    @Test func disconnectedRigIsReported() throws {
        let keyer = Self.keyer(nil).0

        #expect(throws: CwKeyerError(.illegalState, "CW přes CAT: TRX není připojený")) {
            try keyer.send(Self.build("cq"), wpm: 28)
        }
        try keyer.abort() // does nothing without a rig, but does not crash
    }

    // MARK: - Measurements

    private static func ok(_ body: () throws -> Void) -> String {
        KeyerProbe.safe {
            try body()
            return "ok"
        }
    }

    /// `KCAT.sequence`: an empty message or mere speed changes send nothing (not even the speed), `setSpeed`
    /// remembers the speed, a negative speed is sent as is, `close` does not close the rig.
    @Test func measuredSequence() {
        let rig = KeyerRecordingRig()
        let keyer = Self.keyer(rig).0
        var results: [String] = []
        results.append(Self.ok { try keyer.send(Self.build("{LOG}"), wpm: 20) })
        results.append(Self.ok { try keyer.send(Self.build("<<"), wpm: 20) })
        results.append(Self.ok { try keyer.send(Self.build("a]b"), wpm: 20) })
        results.append(Self.ok { try keyer.setSpeed(30) })
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: 30) })
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: -1) })
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: -1) })
        results.append(Self.ok { try keyer.tune(true) })
        results.append(Self.ok { try keyer.tune(false) })
        results.append(Self.ok { try keyer.abort() })
        results.append(Self.ok { keyer.close() })
        results.append(keyer.name())
        #expect(results.joined(separator: " | ") == "ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | CAT")
        #expect(rig.calls.joined(separator: " | ")
            == "speed 20 | morse A SK B | speed 30 | morse E | speed -1 | morse E | morse E | ptt true | ptt false | stop")
    }

    /// `KCAT.fail`: a rig error passes out (`CatException`); after a failed `setCwSpeed` the speed
    /// is not remembered (it is sent again next time).
    @Test(arguments: [
        ("speed", "EXC CatException: selhalo speed | ok | EXC CatException: selhalo speed | ok | ok | ok",
         "speed 20 | speed 20 | morse E | speed 25 | speed 25 | morse E | stop | ptt true"),
        ("morse", "EXC CatException: selhalo morse | ok | ok | ok | ok | ok",
         "speed 20 | morse E | morse E | speed 25 | morse E | stop | ptt true"),
        ("stop", "ok | ok | ok | ok | EXC CatException: selhalo stop | ok",
         "speed 20 | morse E | morse E | speed 25 | morse E | stop | ptt true"),
        ("ptt", "ok | ok | ok | ok | ok | EXC CatException: selhalo ptt",
         "speed 20 | morse E | morse E | speed 25 | morse E | stop | ptt true"),
    ])
    func measuredRigFailures(failOn: String, expectedResults: String, expectedCalls: String) {
        let rig = KeyerRecordingRig()
        rig.failOn = failOn
        let keyer = Self.keyer(rig).0
        var results: [String] = []
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: 20) })
        rig.failOn = ""
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: 20) })
        rig.failOn = failOn
        results.append(Self.ok { try keyer.setSpeed(25) })
        rig.failOn = ""
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: 25) })
        rig.failOn = failOn
        results.append(Self.ok { try keyer.abort() })
        results.append(Self.ok { try keyer.tune(true) })
        #expect(results.joined(separator: " | ") == expectedResults)
        #expect(rig.calls.joined(separator: " | ") == expectedCalls)
    }

    /// `KCAT.null`: without a rig `send` throws (empty messages not — those end earlier), `setSpeed` and `tune`;
    /// `abort` and `close` pass.
    @Test func measuredWithoutRig() {
        let keyer = Self.keyer(nil).0
        var results: [String] = []
        results.append(Self.ok { try keyer.send(Self.build("e"), wpm: 20) })
        results.append(Self.ok { try keyer.send(Self.build("{LOG}"), wpm: 20) })
        results.append(Self.ok { try keyer.setSpeed(20) })
        results.append(Self.ok { try keyer.tune(true) })
        results.append(Self.ok { try keyer.abort() })
        results.append(Self.ok { keyer.close() })
        let error = "EXC IllegalStateException: CW přes CAT: TRX není připojený"
        #expect(results == [error, "ok", error, error, "ok", "ok"])
    }

    /// `KCAT.swap`: the last speed is remembered by the key, not the rig — a new rig after CAT reconnection does not
    /// get the speed until it changes.
    @Test func measuredRigSwap() throws {
        let a = KeyerRecordingRig()
        let b = KeyerRecordingRig()
        let (keyer, source) = Self.keyer(a)
        try keyer.send(Self.build("e"), wpm: 20)
        source.rig = b
        try keyer.send(Self.build("t"), wpm: 20)
        try keyer.send(Self.build("t"), wpm: 22)
        #expect(a.calls == ["speed 20", "morse E"])
        #expect(b.calls == ["morse T", "speed 22", "morse T"])
    }

    /// `KCK.tune`: the key's default `tune` throws Java `UnsupportedOperationException`.
    @Test func measuredDefaultTune() {
        final class BareKeyer: CwKeyer, Sendable {
            func send(_ message: CwMessage, wpm: Int) throws {}
            func abort() throws {}
            func setSpeed(_ wpm: Int) throws {}
            func name() -> String { "bare" }
            func close() {}
        }
        #expect(Self.ok { try BareKeyer().tune(true) }
            == "EXC UnsupportedOperationException: Tento klíč ladění nosnou neumí")
    }
}
