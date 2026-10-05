import os
import Testing
@testable import MCLCore

/// Port of `so2r/OtrspTest` (1 test, same name) + errors and order against the probes (`OTRSP`, `OTRSP.more`).
@Suite struct OtrspTests {

    final class Sink: Sendable {
        private let list = OSAllocatedUnfairLock<[String]>(initialState: [])
        func add(_ command: String) { list.withLock { $0.append(command) } }
        var sent: [String] { list.withLock { $0 } }
    }

    @Test func commands() throws {
        let sink = Sink()
        let o = Otrsp(sink: sink.add)
        try o.focus(2, stereo: false)
        try o.rx(1, stereo: true)
        try o.aux(1, value: 5)
        #expect(sink.sent == ["TX2", "RX2", "RX1S", "AUX15"])
        #expect(throws: JavaIllegalArgumentError.self) { try o.tx(3) }
        #expect(throws: JavaIllegalArgumentError.self) { try o.aux(1, value: 16) }
    }

    static func outcome(_ action: () throws -> Void) -> String {
        do {
            try action()
            return "null"
        } catch let error as JavaIllegalArgumentError {
            return "EXC IllegalArgumentException: " + error.message
        } catch {
            return "unexpected error \(error)"
        }
    }

    @Test func commandsAndErrorsMatchJava() {
        let sink = Sink()
        let o = Otrsp(sink: sink.add)
        let got: [String] = [
            Self.outcome { try o.focus(1, stereo: true) },
            Self.outcome { try o.aux(2, value: 0) },
            Self.outcome { try o.aux(2, value: 15) },
            Self.outcome { try o.rx(0, stereo: false) },
            Self.outcome { try o.aux(3, value: 1) },
            Self.outcome { try o.aux(1, value: -1) },
            ProbeRows.javaList(sink.sent),
        ]
        #expect(got == ProbeRows.rows(VoiceAudioMeasured.research, "OTRSP")[0])

        let more = Sink()
        let o2 = Otrsp(sink: more.add)
        let got2: [String] = [
            Self.outcome { try o2.focus(2, stereo: true) },
            Self.outcome { try o2.tx(-1) },
            Self.outcome { try o2.aux(0, value: 16) },
            Self.outcome { try o2.aux(1, value: 16) },
            Self.outcome { try o2.focus(3, stereo: false) },
            ProbeRows.javaList(more.sent),
        ]
        var expected = ProbeRows.rows(VoiceAudioMeasured.extra, "OTRSP.more")[0]
        expected[0] = expected[0] == "<null>" ? "null" : expected[0]
        #expect(got2 == expected)
    }
}
