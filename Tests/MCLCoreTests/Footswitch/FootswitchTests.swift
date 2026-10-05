import Dispatch
import Foundation
import os
import Testing
@testable import MCLCore

/// Port of `footswitch/FootswitchTest` (2 tests, same names) + the edge detector against probes
/// (`FSW.edge`, `research/` a `voice-audio/`).
@Suite(.ioSafetyNet) struct FootswitchTests {

    @Test func debounce() {
        let d = Footswitch.EdgeDetector(stableSamples: 2)
        #expect(d.sample(true) == nil, "one sample = a glitch")
        #expect(d.sample(false) == nil)
        #expect(d.sample(true) == nil)
        #expect(d.sample(true) == true, "twice in a row = a press")
        #expect(d.sample(true) == nil)
        #expect(d.sample(false) == nil)
        #expect(d.sample(false) == false)
    }

    /// Without a fixed time bound: it waits for a listener event (guard 10 s), period 2 ms as in Java.
    @Test func pollingReportsPressAndRelease() async throws {
        let pin = OSAllocatedUnfairLock(initialState: false)
        let events = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        let closed = OSAllocatedUnfairLock(initialState: 0)
        let footswitch = Footswitch(input: { pin.withLock { $0 } }, onChange: { value in events.withLock { $0.append(value) } },
                                    onClose: { closed.withLock { $0 += 1 } }, periodMs: 2)
        pin.withLock { $0 = true }
        #expect(try await Self.waitFor { events.withLock { $0.count } == 1 })
        pin.withLock { $0 = false }
        #expect(try await Self.waitFor { events.withLock { $0.count } == 2 })
        footswitch.close()
        #expect(events.withLock { $0 } == [true, false])
        #expect(closed.withLock { $0 } == 1)
    }

    /// Waits via `Task.sleep` (does not block a shared pool thread), guard 10 s.
    private static func waitFor(_ condition: () -> Bool) async throws -> Bool {
        let deadline = DispatchTime.now() + .seconds(10)
        while !condition() {
            if DispatchTime.now() > deadline { return false }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    /// `EdgeDetector(n)` over a fixed sequence: `t`/`f` = reported state, `n` = nothing.
    @Test func edgeDetectorMatchesJava() {
        let rows = ProbeRows.rows(VoiceAudioMeasured.research, "FSW.edge")
            + ProbeRows.rows(VoiceAudioMeasured.extra, "FSW.edge")
        #expect(rows.count == 7)
        for row in rows {
            let detector = Footswitch.EdgeDetector(stableSamples: Int32(row[0])!)
            let got: String = row[1].map { bit in
                switch detector.sample(bit == "1") {
                case .some(true): "t"
                case .some(false): "f"
                case .none: "n"
                }
            }.joined()
            #expect(got == row[2], "\(row)")
        }
    }

    @Test func pinAndActionNamesMatchConfig() {
        #expect(Footswitch.Pin.allCases.map(\.rawValue) == ["CTS", "DSR", "DCD"])
        #expect(Footswitch.Action.allCases.map(\.rawValue) == ["PTT", "ENTER", "F1"])
        #expect(Footswitch.Pin(rawValue: AppConfig().footswitchPin) == .cts)
        #expect(Footswitch.Action(rawValue: AppConfig().footswitchAction) == .ptt)
    }
}
