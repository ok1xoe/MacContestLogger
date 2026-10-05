import Foundation
import Testing
@testable import MCLCore

/// The send side (`sendChat`, `startPass`, `passCall`, `stackCall`, `popStackedCall`, `AS:2977-3081`) composed from the
/// core plans exactly as the app model will, against the rows the real private Kotlin methods produced
/// (maintainer-only probe, the in-memory transport behind a proxy, a fixed clock).
@Suite struct NetworkSendTests {

    /// The probe's peers: online OP2 and OP3, OP4 reported offline, OP5 silent for longer than 90 s.
    static func peers(op2: Bool, op3: Bool, op4: Bool, op5: Bool) -> [StationNetwork.Peer] {
        func peer(_ id: String, _ op: String, _ band: String, _ mode: String, _ freq: Int, _ run: String, _ qsos: Int32,
                  _ tx: Bool, _ online: Bool, _ entry: String, stale: Bool) -> StationNetwork.Peer {
            let status = StationStatusWire(stationId: id, operator: op, stationType: "", band: band, mode: mode,
                                           freqHz: freq, runMode: run, qsoCount: qsos, transmitting: tx,
                                           online: online, timestampUtc: "2026-10-04T12:34:56Z", entryCall: entry)
            return StationNetwork.Peer(status: status, receivedAt: .epoch, online: online && !stale,
                                       age: stale ? .seconds(101) : .seconds(1))
        }
        var out: [StationNetwork.Peer] = []
        if op2 { out.append(peer("OP2", "Tom", "20m", "CW", 14_025_000, "RUN", 10, false, true, "ok1abc", stale: false)) }
        if op3 { out.append(peer("OP3", "Ann", "15m", "SSB", 21_300_000, "S&P", 20, true, true, "", stale: false)) }
        if op4 { out.append(peer("OP4", "Bob", "80m", "CW", 3_525_000, "RUN", 0, false, false, "", stale: false)) }
        if op5 { out.append(peer("OP5", "Eve", "40m", "CW", 7_020_000, "RUN", 3, false, true, "", stale: true)) }
        return out
    }

    /// The app model's side of the scenarios, composed from the core plans.
    struct Sim {
        var messages = NetMessages()
        var status = ""
        var showNet = false
        var sent: [NetMessageWire] = []
        var prefill = ""
        let peers: [StationNetwork.Peer]?
        let timestamp: String
        var now: JavaInstant { JavaInstant.parseIsoInstant(timestamp)! }

        func message(_ type: String, to: String, text: String, call: String, freq: Int, mode: String) -> NetMessageWire {
            NetMessageWire(type: type, id: "id", fromStation: "OP1", fromOperator: "OK1XOE", toStation: to, text: text,
                           call: call, freqHz: freq, mode: mode, timestampUtc: timestamp)
        }

        mutating func sendChat(to: String, text: String, fail: Bool, failMessage: String?) {
            switch NetMessages.planChat(connected: peers != nil, text: text) {
            case .rejected(let s): status = s.czech
            case .ignore: break
            case .send(let trimmed):
                if fail {
                    status = NetMessages.failure("Chat", message: failMessage).czech
                    return
                }
                let m = message("CHAT", to: to, text: trimmed, call: "", freq: 0, mode: "")
                sent.append(m)
                messages.sentChat(m, now: now)
            }
        }

        mutating func startPass(typed: String, myFreq: Int) {
            switch NetMessages.startPass(typedCall: typed, peers: peers) {
            case .rejected(let s): status = s.czech
            case .direct(let to, let call): passCall(to: to, call: call, myFreq: myFreq, fail: false)
            case .choose(let call, let s):
                messages.passPending = call
                showNet = true
                status = s.czech
            }
        }

        mutating func passCall(to: String, call: String, myFreq: Int, fail: Bool) {
            guard let plan = NetMessages.passMessage(to: to, call: call, peers: peers, myFreqHz: myFreq,
                                                     translator: .source) else { return }
            if fail {
                status = NetMessages.failure("Pass", message: "boom").czech
                return
            }
            let m = message("PASS", to: plan.to, text: plan.note, call: plan.call, freq: plan.freqHz, mode: plan.mode)
            sent.append(m)
            status = messages.sentPass(m, to: to, call: call, now: now).czech
        }

        mutating func stackCall(to: String, call: String, fail: Bool) {
            switch NetMessages.planStack(connected: peers != nil, to: to, call: call) {
            case .rejected(let s): status = s.czech
            case .ignore: break
            case .send(let target, let upper):
                if fail {
                    status = NetMessages.failure("Partner", message: "boom").czech
                    return
                }
                sent.append(message("STACK", to: target, text: "", call: upper, freq: 0, mode: ""))
                status = NetMessages.sentStack(call: upper, to: target).czech
            }
        }

        mutating func pop() {
            if let call = messages.popStack() {
                prefill = call
            } else {
                status = NetMessages.stackEmptyStatus.czech
            }
        }

        func observe() -> String {
            let e = { (text: String?) in NetworkProbeTable.esc(text) }
            var sentText = ""
            for m in sent {
                let fields: [String] = [e(m.type), e(m.fromStation), e(m.fromOperator), e(m.toStation), e(m.text),
                                        e(m.call), String(m.freqHz), e(m.mode), e(m.timestampUtc)]
                sentText += fields.joined(separator: "|") + ";"
            }
            return "status=[" + e(status) + "] lines=[" + NetworkLogicTests.chatText(messages, timestampParsed: true)
                + "] pending=[" + e(messages.passPending) + "] showNet=\(showNet) sent=[" + sentText + "] stack=["
                + NetworkLogicTests.stackText(messages) + "] prefill=[" + e(prefill) + "]"
        }
    }

    /// The transport clock of a scenario: `+1 s` once peers were added, `+101 s` with the stale one.
    static func timestamp(_ f: [String: String?], hasPeers: Bool) -> String {
        if !hasPeers { return "2026-10-04T12:34:56Z" }
        return NetworkLogicTests.value(f, "op5") == "true" ? "2026-10-04T12:36:37Z" : "2026-10-04T12:34:57Z"
    }

    static func peerList(_ f: [String: String?]) -> [StationNetwork.Peer]? {
        guard NetworkLogicTests.value(f, "net") == "true" else { return nil }
        let on = { (key: String) in NetworkLogicTests.value(f, key) == "true" }
        return peers(op2: on("op2"), op3: on("op3"), op4: on("op4"), op5: on("op5"))
    }

    static func myFreq(_ f: [String: String?]) -> Int {
        let cat: Int? = NetworkLogicTests.value(f, "cat").flatMap { Int($0) }
        return cat ?? Int(NetworkLogicTests.value(f, "tuned") ?? "0") ?? 0
    }

    @Test func sendChatMatchesTheJvm() {
        let rows = NetworkProbeTable.area("sendChat")
        #expect(rows.count == 10)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let connected = NetworkLogicTests.value(f, "net") == "true"
            var sim = Sim(peers: connected ? [] : nil, timestamp: Self.timestamp(f, hasPeers: false))
            sim.sendChat(to: NetworkLogicTests.value(f, "to") ?? "", text: NetworkLogicTests.value(f, "text") ?? "",
                         fail: NetworkLogicTests.value(f, "fail") == "true",
                         failMessage: NetworkLogicTests.value(f, "failMessage"))
            #expect(sim.observe() == row.result, "\(row.input)")
        }
    }

    @Test func startPassMatchesTheJvm() {
        let rows = NetworkProbeTable.area("startPass")
        #expect(rows.count == 16)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let list = Self.peerList(f)
            var sim = Sim(peers: list, timestamp: Self.timestamp(f, hasPeers: list != nil))
            sim.messages.passPending = NetworkLogicTests.value(f, "pending") ?? ""
            sim.startPass(typed: NetworkLogicTests.value(f, "typed") ?? "", myFreq: Self.myFreq(f))
            #expect(sim.observe() == row.result, "\(row.input)")
        }
    }

    @Test func passCallMatchesTheJvm() {
        let rows = NetworkProbeTable.area("passCall")
        #expect(rows.count == 19)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let list = Self.peerList(f)
            var sim = Sim(peers: list, timestamp: Self.timestamp(f, hasPeers: list != nil))
            sim.messages.passPending = NetworkLogicTests.value(f, "pending") ?? ""
            sim.passCall(to: NetworkLogicTests.value(f, "to") ?? "", call: NetworkLogicTests.value(f, "call") ?? "",
                         myFreq: Self.myFreq(f), fail: NetworkLogicTests.value(f, "fail") == "true")
            #expect(sim.observe() == row.result, "\(row.input)")
        }
    }

    @Test func stackCallMatchesTheJvm() {
        let rows = NetworkProbeTable.area("stackCall")
        #expect(rows.count == 10)
        for row in rows {
            let f = NetworkProbeTable.fields(row.input)
            let connected = NetworkLogicTests.value(f, "net") == "true"
            var sim = Sim(peers: connected ? [] : nil, timestamp: Self.timestamp(f, hasPeers: false))
            sim.stackCall(to: NetworkLogicTests.value(f, "to") ?? "", call: NetworkLogicTests.value(f, "call") ?? "",
                          fail: NetworkLogicTests.value(f, "fail") == "true")
            #expect(sim.observe() == row.result, "\(row.input)")
        }
    }

    @Test func popStackIsFifoAndReportsAnEmptyStack() {
        let rows = NetworkProbeTable.area("popStack")
        #expect(rows.count == 5)
        var sim = Sim(peers: [], timestamp: "2026-10-04T12:34:56Z")
        sim.pop()
        #expect(sim.observe() == rows[0].result)
        for call in ["aaa", "bbb", "ccc"] {
            let w = NetMessageWire(type: "STACK", id: "id", fromStation: "OP2", fromOperator: "", toStation: "",
                                   text: "", call: call, freqHz: 0, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
            let effects = sim.messages.receive(w, catFreqHz: nil, tunedHz: 0, now: sim.now)
            sim.status = NetworkLogicTests.czech(effects)
        }
        for index in 1...4 {
            sim.pop()
            let observed = "stack=[" + NetworkLogicTests.stackText(sim.messages) + "] prefill=["
                + NetworkProbeTable.esc(sim.prefill) + "] status=[" + NetworkProbeTable.esc(sim.status) + "]"
            #expect(observed == rows[index].result, "pop \(index)")
        }
    }

    // MARK: - parts the probe does not reach

    /// `passCall` without an explicit call: `passPending.ifBlank { typedCall }.trim().uppercase()` (default argument).
    @Test func defaultPassCallPrefersThePendingCall() {
        #expect(NetMessages.defaultPassCall(pending: " ok1abc ", typedCall: "dl1xyz") == "OK1ABC")
        #expect(NetMessages.defaultPassCall(pending: "  ", typedCall: " dl1xyz/p ") == "DL1XYZ/P")
        #expect(NetMessages.defaultPassCall(pending: "\u{00A0}", typedCall: "straße") == "STRASSE")
        #expect(NetMessages.defaultPassCall(pending: "", typedCall: "") == "")
    }

    /// The note is formatted with US decimals even in a language that would use a comma, and translated first.
    @Test func passNoteIsTranslatedAndUsesUsDecimals() {
        #expect(NetMessages.passNote(myFreqHz: 14_025_050, translator: .source) == "u mě 14025.1")
        #expect(NetMessages.passNote(myFreqHz: 0, translator: .source) == "")
        #expect(NetMessages.passNote(myFreqHz: -5, translator: .source) == "")
        let english = SpotActionsTests.translator(["u mě %.1f": "at my side %.1f"])
        #expect(NetMessages.passNote(myFreqHz: 7_030_000, translator: english) == "at my side 7030.0")
    }

    @Test func passTargetCountsOnlyOnlinePeers() {
        let none: [StationNetwork.Peer] = []
        let one = Self.peers(op2: true, op3: false, op4: true, op5: true)
        let two = Self.peers(op2: true, op3: true, op4: false, op5: false)
        #expect(NetMessages.passTarget(peers: nil) == .noNet)
        #expect(NetMessages.passTarget(peers: none) == .choose)
        #expect(NetMessages.passTarget(peers: two) == .choose)
        guard case .direct(let peer) = NetMessages.passTarget(peers: one) else {
            Issue.record("expected a direct target")
            return
        }
        #expect(peer.status.stationId == "OP2")
    }

    @Test func ownLinesAreAddedOnlyAfterASuccessfulSend() {
        var messages = NetMessages()
        messages.passPending = "OK1ABC"
        let m = NetMessageWire(type: "PASS", id: "id", fromStation: "OP1", fromOperator: "OK1XOE", toStation: "OP2",
                               text: "", call: "OK1ABC", freqHz: 0, mode: "", timestampUtc: "2026-10-04T12:34:56Z")
        let status = messages.sentPass(m, to: "OP2", call: "OK1ABC", now: JavaInstant.now())
        #expect(status.czech == "Pass: OK1ABC předáno stanici OP2")
        #expect(messages.passPending == "")
        #expect(messages.lines == [ChatLine(time: "1234", from: "OP1", to: "OP2", text: "PASS OK1ABC", own: true)])
        #expect(messages.unread == 0)
    }

    // MARK: - texts of the windows

    @Test func networkStatusWindowTexts() {
        let headers = NetTexts.headers.map { $0.text }
        #expect(headers == ["Stanice", "Operátor", "Pásmo", "Mód", "kHz", "Režim", "QSO", "Stav"])
        #expect(NetTexts.headers.map { $0.translate } == [false, true, true, true, false, true, false, false])
        #expect(NetTexts.thisStation(stationId: "OP1", connected: true, translator: .source)
            == "Tato stanice: OP1 · připojeno")
        #expect(NetTexts.thisStation(stationId: "OP1", connected: false, translator: .source)
            == "Tato stanice: OP1 · odpojeno")
        #expect(NetTexts.passHint(pending: "", typedCall: " ", translator: .source)
            == "Pass: napiš volačku do zadávacího okna, pak „Předat“ u cílové stanice (nebo Ctrl+Alt+P).")
        #expect(NetTexts.passHint(pending: "", typedCall: "ok1abc", translator: .source)
            == "Pass: OK1ABC — klikni na „Předat“ u cílové stanice.")
    }

    @Test func peerRowCells() {
        let all = Self.peers(op2: true, op3: true, op4: true, op5: true)
        let cells = all.map { NetTexts.peerCells($0, translator: .source) }
        #expect(cells[0] == ["OP2", "Tom", "20m", "CW", "14025.0", "RUN", "10", "online"])
        #expect(cells[1] == ["OP3", "Ann", "15m", "SSB", "21300.0", "S&P", "20", "vysílá"])
        #expect(cells[2] == ["OP4", "Bob", "80m", "CW", "3525.0", "RUN", "", "offline"])
        #expect(cells[3] == ["OP5", "Eve", "40m", "CW", "7020.0", "RUN", "", "neaktivní 101 s"])
    }

    @Test func inactiveAgeIsRoundedDownLikeJavaDuration() {
        #expect(NetTexts.wholeSeconds(.milliseconds(101_900)) == 101)
        #expect(NetTexts.wholeSeconds(.milliseconds(-500)) == -1)
        #expect(NetTexts.wholeSeconds(.zero) == 0)
    }

    @Test func partnerAndChatRows() {
        let peer = Self.peers(op2: true, op3: false, op4: false, op5: false)[0]
        #expect(NetTexts.partnerLine(peer.status, translator: .source) == "OP2  20m CW  14025.0 kHz  · píše: ok1abc")
        var blank = peer.status
        blank.entryCall = " "
        #expect(NetTexts.partnerLine(blank, translator: .source) == "OP2  20m CW  14025.0 kHz  · píše: —")
        let own = ChatLine(time: "1234", from: "OP1", to: "OP2", text: "hi", own: true)
        let received = ChatLine(time: "1235", from: "OP2 (Tom)", to: "", text: "yo", own: false)
        #expect(NetTexts.chatRow(own, translator: .source) == "1234  já → OP2: hi")
        #expect(NetTexts.chatRow(received, translator: .source) == "1235  OP2 (Tom): yo")
    }
}
