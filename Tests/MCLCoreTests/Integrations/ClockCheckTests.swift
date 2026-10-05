import Foundation
import Testing
@testable import MCLCore

/// The `clock` rows of `IntegrationsProbe.java` (`AppState.checkClock` of the Kotlin v1.1.1 with a stand-in
/// `SntpClient` that answers a scripted offset — no socket, no NTP server) against `ClockCheck`.
@Suite struct ClockCheckTests {

    typealias F = IntegrationsFixture

    /// One probe row replayed. Columns: index, server, correct, offset, failure, calls, offset, status, statusMessage,
    /// message count, first message.
    @Test func rowsMatchJvm() {
        let rows = F.rows("clock")
        #expect(rows.count == 28)
        for row in rows {
            let server = F.unescape(row[2])
            let correct = row[3] == "true"
            let offset = Int64(row[4])!
            let failure = row[5]
            var calls = "[]"
            var offsetText = "null"
            var status: EntryStatus = .tr(ClockCheck.neverChecked)
            var statusMessage = ""
            var messages: [String] = []
            if let host = ClockCheck.server(server) {
                calls = "[\(host):\(ClockCheck.port):\(ClockCheck.timeoutMs)]"
                if failure == "-" {
                    let result = ClockCheck.result(offsetMs: offset, server: host, correct: correct)
                    offsetText = String(offset)
                    status = result.status
                    if let warn = result.warnStatus {
                        statusMessage = warn.czech
                        messages.append(result.status.czech)
                    }
                    #expect(result.applyOffsetMs == (correct ? offset : 0), "row \(row[1])")
                    #expect(result.warn == (warn(offset)), "row \(row[1])")
                } else {
                    status = ClockCheck.failure(server: host, message: failure == "<null>" ? nil : F.unescape(failure))
                }
            } else {
                status = ClockCheck.disabled
            }
            let swift: [String] = [
                "calls=\(calls)", "offset=\(offsetText)", F.escape(status.czech), F.escape(statusMessage),
                "msgs=\(messages.count)", F.escape(messages.first ?? "-"),
            ]
            if swift != Array(row[6...]) {
                Issue.record("row \(row[1])\nSwift: \(swift)\nJava:  \(Array(row[6...]))")
            }
        }
    }

    func warn(_ offset: Int64) -> Bool {
        abs(offset) > 1000
    }

    @Test func serverIsTrimmedAndBlankMeansOff() {
        #expect(ClockCheck.server(" pool.ntp.org ") == "pool.ntp.org")
        #expect(ClockCheck.server("") == nil)
        #expect(ClockCheck.server("  ") == nil)
        #expect(ClockCheck.server("\u{00A0}") == nil) // Kotlin isBlank: NBSP is blank
        #expect(ClockCheck.server("\u{0001}x\u{0001}") == "\u{0001}x\u{0001}") // Kotlin trim keeps control characters
    }

    @Test func offsetAppliesOnlyWithTheCorrectionOn() {
        #expect(ClockCheck.result(offsetMs: -2500, server: "s", correct: true).applyOffsetMs == -2500)
        #expect(ClockCheck.result(offsetMs: -2500, server: "s", correct: false).applyOffsetMs == 0)
        #expect(ClockCheck.result(offsetMs: 0, server: "s", correct: true).applyOffsetMs == 0)
    }

    @Test func warningNeedsMoreThanASecond() {
        #expect(!ClockCheck.result(offsetMs: 1000, server: "s", correct: true).warn)
        #expect(ClockCheck.result(offsetMs: 1001, server: "s", correct: true).warn)
        #expect(!ClockCheck.result(offsetMs: -1000, server: "s", correct: true).warn)
        #expect(ClockCheck.result(offsetMs: -1001, server: "s", correct: true).warn)
        let r = ClockCheck.result(offsetMs: 2000, server: "s", correct: false)
        #expect(r.warnStatus?.czech == "⏰ Hodiny: odchylka +2.00 s od s — srovnej hodiny počítače")
        #expect(ClockCheck.result(offsetMs: 500, server: "s", correct: false).warnStatus == nil)
    }

    @Test func constantsMatchTheSource() {
        #expect(ClockCheck.port == 123)
        #expect(ClockCheck.timeoutMs == 3000)
        #expect(ClockCheck.intervalSeconds == 1800)
        #expect(ClockCheck.disabled.czech == "Synchronizace času vypnutá")
        #expect(ClockCheck.neverChecked == "Čas zatím neověřen")
    }
}
