import Foundation
import Testing
@testable import MCLCore

/// The chat / PASS / STACK reducer, the send plans, the serial reservation, the own station status and NETON/NETOFF
/// against v1.1.1 `AppState` (`ui/AppState.kt:1259-1280, 2735-2762, 2955-3148`), measured on the JVM
/// (maintainer-only probe, the real private methods over an `Unsafe`-allocated `AppState`).
@Suite struct NetworkLogicTests {

    /// The "wall clock" of the emergency time; the probe's rows with an unparseable time show it as `NOW`.
    static let now = JavaInstant.parseIsoInstant("2026-10-04T09:41:00Z")!
    static let nowText = "0941"

    // MARK: - helpers

    static func value(_ f: [String: String?], _ key: String) -> String? {
        guard let entry = f[key] else { return nil }
        return entry
    }

    static func wire(_ f: [String: String?]) -> NetMessageWire {
        let freq: Int = Int(value(f, "freq") ?? "0") ?? 0
        return NetMessageWire(type: value(f, "type"), id: value(f, "id"), fromStation: value(f, "from"),
                              fromOperator: value(f, "op"), toStation: value(f, "to"), text: value(f, "text"),
                              call: value(f, "call"), freqHz: freq, mode: value(f, "mode"),
                              timestampUtc: value(f, "ts"))
    }

    static func chatText(_ messages: NetMessages, timestampParsed: Bool) -> String {
        var out = ""
        for line in messages.lines {
            let time: String = (!timestampParsed && line.time == nowText) ? "NOW" : line.time
            let fields: [String] = [time, NetworkProbeTable.esc(line.from), NetworkProbeTable.esc(line.to),
                                    NetworkProbeTable.esc(line.text), line.own ? "true" : "false"]
            out += fields.joined(separator: "|") + ";"
        }
        return out
    }

    static func stackText(_ messages: NetMessages) -> String {
        messages.stack.map { NetworkProbeTable.esc($0) + "," }.joined()
    }

    static func czech(_ effects: [NetEffect]) -> String {
        var text = ""
        for effect in effects {
            if case .status(let status) = effect { text = status.czech }
        }
        return text
    }

    static func spotsText(_ effects: [NetEffect]) -> String {
        var out = ""
        for effect in effects {
            guard case .addSpot(let spot) = effect else { continue }
            let fields: [String] = [NetworkProbeTable.esc(spot.spotter), String(spot.freqHz),
                                    NetworkProbeTable.esc(spot.dxCall), NetworkProbeTable.esc(spot.comment)]
            out += fields.joined(separator: "|") + ";"
        }
        return out
    }

    // MARK: - reducer rows

    @Test func receiveMatchesTheJvm() {
        let rows = NetworkProbeTable.area("recv")
        #expect(rows.count == 41)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let message = Self.wire(f)
            let cat: Int? = Self.value(f, "cat").flatMap { Int($0) }
            let tuned: Int = Int(Self.value(f, "tuned") ?? "0") ?? 0
            var messages = NetMessages()
            let effects = messages.receive(message, catFreqHz: cat, tunedHz: tuned, now: Self.now)
            let parsed: Bool = message.timestampUtc.flatMap { JavaInstant.parseIsoInstant($0) } != nil
            let observed = "status=[" + NetworkProbeTable.esc(Self.czech(effects)) + "] unread=\(messages.unread) lines=["
                + Self.chatText(messages, timestampParsed: parsed) + "] spots=[" + Self.spotsText(effects)
                + "] stack=[" + Self.stackText(messages) + "]"
            // The one row where Kotlin throws before anything changes.
            let expected: String = row.result.hasPrefix("EXC NullPointerException ")
                ? String(row.result.dropFirst("EXC NullPointerException ".count)) : row.result
            #expect(observed == expected, "\(row.input)")
        }
    }

    @Test func stackKeepsTenWithoutDuplicates() {
        var messages = NetMessages()
        var steps: [String] = []
        func push(_ call: String) {
            let w = NetMessageWire(type: "STACK", id: "id", fromStation: "OP2", fromOperator: "", toStation: "OP1",
                                   text: "", call: call, freqHz: 0, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
            _ = messages.receive(w, catFreqHz: nil, tunedHz: 0, now: Self.now)
            steps.append(Self.stackText(messages))
        }
        for i in 1...12 { push("c\(i)") }
        push("C12")
        push("c3")
        push("C2")
        let row = NetworkProbeTable.area("stackseq")[0]
        #expect(steps.joined(separator: " / ") == row.result)
    }

    @Test func chatIsCappedAtFiveHundredLines() {
        var messages = NetMessages()
        for i in 1...505 {
            let w = NetMessageWire(type: "CHAT", id: "id", fromStation: "OP2", fromOperator: "", toStation: "",
                                   text: "m\(i)", call: "", freqHz: 0, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
            _ = messages.receive(w, catFreqHz: nil, tunedHz: 0, now: Self.now)
        }
        let text = Self.chatText(messages, timestampParsed: true)
        let parts = text.split(separator: ";").map(String.init)
        let observed = "size=\(messages.lines.count) first=\(parts[0]) last=\(parts[parts.count - 1]) unread=\(messages.unread)"
        #expect(observed == NetworkProbeTable.area("chatcap")[0].result)
    }

    @Test func mixedMessagesCountOnlyChatAndPassAsUnread() {
        var messages = NetMessages()
        var spots = ""
        var status = ""
        func feed(_ type: String, _ from: String, _ text: String, _ call: String, _ freq: Int) {
            let w = NetMessageWire(type: type, id: "id", fromStation: from, fromOperator: "", toStation: "", text: text,
                                   call: call, freqHz: freq, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
            let effects = messages.receive(w, catFreqHz: nil, tunedHz: 0, now: Self.now)
            spots += Self.spotsText(effects)
            let s = Self.czech(effects)
            if !s.isEmpty { status = s }
        }
        feed("CHAT", "OP2", "one", "", 0)
        feed("PASS", "OP2", "two", "ok1abc", 14_025_000)
        feed("PING", "OP2", "three", "", 0)
        feed("STACK", "OP2", "four", "ok1abc", 0)
        feed("CHAT", "OP3", "five", "", 0)
        let observed = "status=[" + NetworkProbeTable.esc(status) + "] unread=\(messages.unread) lines=["
            + Self.chatText(messages, timestampParsed: true) + "] spots=[" + spots + "] stack=["
            + Self.stackText(messages) + "]"
        #expect(observed == NetworkProbeTable.area("mixed")[0].result)
    }

    @Test func markReadResetsTheCounterOnly() {
        var messages = NetMessages()
        let w = NetMessageWire(type: "CHAT", id: "id", fromStation: "OP2", fromOperator: "", toStation: "", text: "x",
                               call: "", freqHz: 0, mode: "", timestampUtc: nil)
        _ = messages.receive(w, catFreqHz: nil, tunedHz: 0, now: Self.now)
        #expect(messages.unread == 1)
        messages.markRead()
        #expect(messages.unread == 0)
        #expect(messages.lines.count == 1)
    }

    // MARK: - chatTime

    @Test func chatTimeMatchesTheJvm() {
        let rows = NetworkProbeTable.area("chatTime")
        #expect(rows.count == 20)
        for row in rows {
            let input: String? = row.input == "<null>" ? nil : NetworkProbeTable.unescape(row.input)
            let out = NetMessages.chatTime(input, now: Self.now)
            #expect((out == Self.nowText ? "NOW" : out) == row.result, "\(row.input)")
        }
    }

    // MARK: - own station status

    @Test func stationStatusMatchesTheJvm() {
        let rows = NetworkProbeTable.area("status")
        #expect(rows.count == 34)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            var catFreq: Int?
            var catMode: Mode?
            if let cat = Self.value(f, "cat"), cat != "<null>" {
                let parts = cat.split(separator: "/", omittingEmptySubsequences: false)
                catFreq = Int(parts[0])
                catMode = Mode(rawValue: String(parts[1]))
            }
            let status = StationStatusBuilder.status(
                stationId: Self.value(f, "id") ?? "", operatorCall: Self.value(f, "op") ?? "",
                stationType: OperatingGuard.StationType(rawValue: Self.value(f, "type") ?? "NONE") ?? .none,
                catFreqHz: catFreq, catMode: catMode, tunedFreqHz: Int(Self.value(f, "tuned") ?? "0") ?? 0,
                runMode: Self.value(f, "run") == "RUN" ? .run : .searchAndPounce,
                qsoCount: Int(Self.value(f, "qsos") ?? "0") ?? 0,
                sending: Self.value(f, "voice") == "true" || Self.value(f, "cw") == "true",
                typedCall: Self.value(f, "typed") ?? "")
            let e = { (value: String?) in NetworkProbeTable.esc(value, semicolon: true) }
            let parts: [String] = [
                "id=" + e(status.stationId), "op=" + e(status.operator), "type=" + e(status.stationType),
                "band=" + e(status.band), "mode=" + e(status.mode), "freq=\(status.freqHz)",
                "run=" + e(status.runMode), "qso=\(status.qsoCount)", "tx=\(status.transmitting)",
                "online=\(status.online)", "ts=" + e(status.timestampUtc), "entry=" + e(status.entryCall),
            ]
            #expect(parts.joined(separator: ";") == row.result, "\(row.input)")
        }
    }

    // MARK: - serial reservation

    @Test func serialTickMatchesTheJvm() {
        let rows = NetworkProbeTable.area("serialTick")
        #expect(rows.count == 80)
        let nowMs: Int64 = 1_700_000_000_000
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let enabled = Self.value(f, "enabled") == "true"
            let net = Self.value(f, "net") == "true"
            let reserved: Int? = Self.value(f, "reserved").flatMap { Int($0) }
            let reqId: String? = Self.value(f, "reqId")
            let age = Int64(Self.value(f, "age") ?? "0") ?? 0
            let original: Int64 = nowMs - age
            var reservation = SerialReservation(reserved: reserved, requestId: reqId, requestedAtMs: original)
            let id = reservation.tick(nowMs: nowMs, enabled: enabled, hasNet: net, newId: { "new-id" })
            let pending: String? = reservation.pendingRequestId
            let idText: String = pending == nil ? "<null>" : (pending == reqId ? "same" : "new")
            let at = reservation.lastRequestAtMs
            let reservedText = reservation.reserved.map { String($0) } ?? "null"
            let observed = "requests=\(id == nil ? 0 : 1) requestId=\(idText) stamped=\(at != original) "
                + "untouched=\(at == original) sent=\(id == nil ? "<none>" : "id") reserved=\(reservedText)"
            #expect(observed == row.result, "\(row.input)")
        }
    }

    @Test func serialReplyMatchesTheJvm() {
        let rows = NetworkProbeTable.area("serialReply")
        #expect(rows.count == 6)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            var reservation = SerialReservation(reserved: nil, requestId: Self.value(f, "pending"), requestedAtMs: 0)
            reservation.reply(SerialReply(stationId: "OP1", requestId: Self.value(f, "reply"), serial: 42))
            let reservedText = reservation.reserved.map { String($0) } ?? "null"
            let observed = "reserved=\(reservedText) pending=" + NetworkProbeTable.esc(reservation.pendingRequestId)
            #expect(observed == row.result, "\(row.input)")
        }
    }

    @Test func serialRoundTrip() {
        var reservation = SerialReservation()
        let id = reservation.tick(nowMs: 10_000, enabled: true, hasNet: true, newId: { "r-1" })
        #expect(id == "r-1")
        reservation.reply(SerialReply(stationId: "OP1", requestId: "r-1", serial: 1))
        let rows = NetworkProbeTable.area("serialRound")
        #expect(rows[0].result == "reserved=1 pending=<null>")
        #expect(reservation.reserved == 1)
        #expect(reservation.pendingRequestId == nil)
        // While a number is reserved, nothing is requested (`requests=1` in the probe).
        let blocked = reservation.tick(nowMs: 99_000, enabled: true, hasNet: true, newId: { "r-2" })
        #expect(blocked == nil)
        #expect(rows[1].result == "requests=1")
    }

    /// `AS:2783`: the QSO that carries the reserved number uses it up and the next one is requested at once.
    @Test func consumedUsesUpTheReservedNumberOnly() {
        var reservation = SerialReservation(reserved: 5, requestId: nil, requestedAtMs: 0)
        let wrong = reservation.consumed(serial: 6)
        let none = reservation.consumed(serial: nil)
        #expect(!wrong && !none)
        #expect(reservation.reserved == 5)
        let used = reservation.consumed(serial: 5)
        #expect(used)
        #expect(reservation.reserved == nil)
        let again = reservation.consumed(serial: 5)
        #expect(!again)
        let next = reservation.tick(nowMs: 1, enabled: true, hasNet: true, newId: { "next" })
        #expect(next == "next")
    }

    @Test func retryBoundaryIsThreeSecondsExclusive() {
        // Kotlin `now - serialRequestedAt < 3_000`: exactly 3000 ms repeats (a real clock cannot hit the boundary in
        // the probe, whose ages are 1, 1000, 2500, 3500 and 10000 ms).
        var waiting = SerialReservation(reserved: nil, requestId: "r1", requestedAtMs: 0)
        let early = waiting.tick(nowMs: 2_999, enabled: true, hasNet: true, newId: { "x" })
        let due = waiting.tick(nowMs: 3_000, enabled: true, hasNet: true, newId: { "x" })
        #expect(early == nil)
        #expect(due == "x")
    }

    @Test func resetForgetsTheReservationAndThePendingRequest() {
        var reservation = SerialReservation(reserved: 7, requestId: "r1", requestedAtMs: 123)
        reservation.reset()
        #expect(reservation.reserved == nil)
        #expect(reservation.pendingRequestId == nil)
        let fresh = reservation.tick(nowMs: 124, enabled: true, hasNet: true, newId: { "fresh" })
        #expect(fresh == "fresh")
    }

    // MARK: - NETON / NETOFF

    @Test func networkCommandsMatchTheJvm() {
        let rows = NetworkProbeTable.area("networkOn")
        #expect(rows.count == 7)
        for row in rows where row.input.hasPrefix("host=") {
            let f = NetworkProbeTable.fields(row.input)
            var config = ClusterConfig()
            config.brokerHost = Self.value(f, "host") ?? ""
            config.stationId = Self.value(f, "id") ?? ""
            let outcome = NetworkCommands.on(config: config, running: false)
            switch outcome {
            case .notConfigured(let status):
                #expect("status=[" + status.czech + "] enabled=false outcome=returned" == row.result, "\(row.input)")
            case .start:
                // The probe has no logbook, so `startClusterIfEnabled` throws after `isEnabled = true`.
                #expect(row.result == "status=[] enabled=true outcome=EXC NullPointerException")
            case .alreadyRunning:
                Issue.record("not running")
            }
        }
        var configured = ClusterConfig()
        configured.brokerHost = "broker.example"
        configured.stationId = "OP1"
        guard case .alreadyRunning(let status) = NetworkCommands.on(config: configured, running: true) else {
            Issue.record("expected already running")
            return
        }
        let running = rows.first { $0.input == "running" }
        #expect("status=[" + status.czech + "] enabled=false" == running?.result)
        let off = NetworkProbeTable.area("networkOff")[0]
        #expect(off.result.hasPrefix("status=[" + NetworkCommands.off.czech + "] enabled=false"))
    }

    @Test func networkCommandChecksAreKotlinBlank() {
        var config = ClusterConfig()
        config.brokerHost = "\u{00A0}"
        config.stationId = "OP1"
        #expect(NetworkCommands.on(config: config, running: false)
            == .notConfigured(.tr(NetworkCommands.notConfiguredKey)))
        config.brokerHost = "h"
        config.stationId = "  "
        #expect(NetworkCommands.on(config: config, running: true)
            == .notConfigured(.tr(NetworkCommands.notConfiguredKey)))
    }

    @Test func wipeNoteOnlyWhileConnected() {
        #expect(NetTexts.wipeNote(connected: false).czech == "")
        #expect(NetTexts.wipeNote(connected: true).czech
            == "\n\nJsi připojený ke clusteru — QSO zmizí i na ostatních stanicích.")
    }
}
