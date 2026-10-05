import Foundation
import os
import Testing
@testable import MCLCore

/// Newly written tests of `DxClusterSession` (the core of the Kotlin `ui/dxcluster/DxClusterConnection.kt`; Kotlin has no
/// tests). The cluster is always `FakeLineServer` on 127.0.0.1 — never a real DX cluster or RBN, no real
/// credentials. The server sends rows only on the client's command (a server-side trigger), the Kotlin `delay`
/// is replaced by a recording `SleepGate` (optionally blocking until released by the test). No success time bounds —
/// it waits for a state from `onChange`, the listing or commands on the server; `ioSafetyNet` is only a guard.
@Suite(.ioSafetyNet) struct DxClusterSessionTests {

    /// Recorded session events (shared between the session threads and the test).
    final class Recorder: Sendable {
        private let snapshots = OSAllocatedUnfairLock<[DxClusterSession.Snapshot]>(initialState: [])
        private let errors = OSAllocatedUnfairLock<[String]>(initialState: [])
        private let selfSpots = OSAllocatedUnfairLock<[SelfSpot]>(initialState: [])
        private let spots = OSAllocatedUnfairLock<[DxSpot]>(initialState: [])

        func add(_ s: DxClusterSession.Snapshot) { snapshots.withLock { $0.append(s) } }
        func unexpected(_ e: any Error) { errors.withLock { $0.append(String(describing: e)) } }
        func selfSpot(_ s: SelfSpot) { selfSpots.withLock { $0.append(s) } }
        func spot(_ s: DxSpot) { spots.withLock { $0.append(s) } }

        var all: [DxClusterSession.Snapshot] { snapshots.withLock { $0 } }
        var statuses: [String] { all.map(\.status) }
        var last: DxClusterSession.Snapshot? { all.last }
        var unexpectedErrors: [String] { errors.withLock { $0 } }
        var allSelfSpots: [SelfSpot] { selfSpots.withLock { $0 } }
        var allSpots: [DxSpot] { spots.withLock { $0 } }

        /// Waits for the condition; records an issue instead of hanging when it never holds (`pollLimit`).
        func wait(_ condition: (Recorder) -> Bool) async throws {
            try await DxClusterSessionTests.poll("the recorded state") { condition(self) }
        }
    }

    /// A replacement for the Kotlin `delay`: records the requested duration; the blocking variant waits (on the session
    /// thread, not in the pool) until the test releases it, at most 120 s (strict-pool runs starve the polling waits).
    final class SleepGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var requested: [Int] = []
        private var released = 0
        private let blocking: Bool

        init(blocking: Bool = false) {
            self.blocking = blocking
        }

        func sleep(_ ms: Int) {
            condition.lock()
            requested.append(ms)
            let ticket: Int = requested.count
            // Bounded: a test that never releases the hold frees the session thread after 120 s instead of hanging.
            let deadline = Date(timeIntervalSinceNow: 120)
            while blocking && released < ticket {
                if !condition.wait(until: deadline) {
                    break
                }
            }
            condition.unlock()
        }

        func release() {
            condition.lock()
            released += 1
            condition.broadcast()
            condition.unlock()
        }

        var calls: [Int] {
            condition.lock()
            defer { condition.unlock() }
            return requested
        }
    }

    static let at = dxInstant("2026-10-02T12:00:00Z")

    static func makeSession(_ rec: Recorder, gate: SleepGate = SleepGate(),
                            log: DxClusterTrafficLog = DxClusterTrafficLog(), tag: String = "",
                            translate: @escaping @Sendable (String) -> String = { $0 }) -> DxClusterSession {
        let spots = SpotBuffer(maxAgeMinutes: 90, clock: { DxClusterSessionTests.at })
        return DxClusterSession(spots: spots, log: log, tag: tag, timing: DxClusterSession.Timing(),
                                clock: { DxClusterSessionTests.at }, translate: translate,
                                onChange: { rec.add($0) }, onUnexpectedError: { rec.unexpected($0) },
                                sleep: { gate.sleep($0) })
    }

    static func favorite(_ server: FakeLineServer?, port: Int? = nil, name: String = "Test",
                         login: String = "OK1XOE", password: String = "secret") -> DxClusterFavorite {
        let p: Int = port ?? server?.port ?? 0
        precondition(p != 4532 && p != 4533, "the test must not touch the shared daemon")
        return DxClusterFavorite(name: name, host: "127.0.0.1", port: p, login: login, password: password)
    }

    /// A listing without a timestamp (`HH:mm:ss` + two spaces).
    static func bodies(_ log: DxClusterTrafficLog) -> [String] {
        log.snapshot().map { String($0.dropFirst(10)) }
    }

    /// The guard of every polling wait of this suite (s): the conditions hold within milliseconds; after the limit the
    /// wait records an issue and returns, so a broken condition fails the test instead of hanging it.
    static let pollLimit: Int = 10

    /// Polls `condition` every 5 ms for at most `pollLimit` seconds; `Issue.record` when it never holds.
    static func poll(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(pollLimit)
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("\(what) was not reached within \(pollLimit) s")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    static func waitLog(_ log: DxClusterTrafficLog, contains body: String) async throws {
        try await poll("the log line \"\(body)\"") { bodies(log).contains(body) }
    }

    static func waitCommands(_ server: FakeLineServer, count: Int) async throws {
        try await poll("\(count) command(s) on the server") { server.commands(0).count >= count }
    }

    // MARK: - Connecting and logging in

    @Test func initialStateIsUntranslatedDisconnected() {
        let session = DxClusterSession()
        #expect(session.status == "Odpojeno")
        #expect(!session.connected && !session.connecting && !session.loggedIn)
        #expect(session.lastWwv == nil && session.currentFavorite == nil)
    }

    @Test func connectLoginPasswordAfterDelayAndConfirmation() async throws {
        let hello: [FakeLineServer.Step] = [.line("Hello ok1xoe, this is TEST node")]
        let server = try FakeLineServer(script: ["OK1XOE\r": hello], fallback: [.silent],
                                        onConnect: [.line("Please enter your call:")])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate(blocking: true)
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, gate: gate, log: log)
        let fav = Self.favorite(server)
        let port = String(server.port)

        try session.connect(fav)
        try await rec.wait { $0.last?.connected == true }
        #expect(session.currentFavorite == fav)
        try await Self.waitLog(log, contains: "Please enter your call:")

        session.login(fav)
        try await rec.wait { $0.last?.loggedIn == true }
        // The password waits for the "delay" to be released — the server has so far got only the login.
        #expect(server.commands(0) == ["OK1XOE\r"])
        #expect(gate.calls == [400])
        gate.release()
        try await Self.waitCommands(server, count: 2)
        await session.idle()

        #expect(server.commands(0) == ["OK1XOE\r", "secret\r"])
        #expect(server.requestBytes(0) == Array("OK1XOE\r\nsecret\r\n".utf8))
        let expected: [String] = ["Připojuji k Test…", "Připojeno k Test", "Přihlašuji jako OK1XOE…",
                                  "Přihlášeno jako OK1XOE"]
        #expect(rec.statuses == expected)
        let lines: [String] = Self.bodies(log)
        #expect(lines.first == "\u{00B7} Připojuji k 127.0.0.1:" + port + "…")
        #expect(lines.contains("\u{00BB} OK1XOE"))
        #expect(lines.contains("Hello ok1xoe, this is TEST node"))
        #expect(lines.last == "\u{00B7} (heslo odesláno)")
        #expect(!lines.contains { $0.contains("secret") })
        #expect(rec.unexpectedErrors.isEmpty)
        try session.disconnect("Konec")
    }

    @Test func autoLoginAfterDelay() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let session = Self.makeSession(rec, gate: gate)

        try session.connect(Self.favorite(server), autoLogin: true)
        try await Self.waitCommands(server, count: 2)
        await session.idle()
        #expect(server.commands(0) == ["OK1XOE\r", "secret\r"])
        #expect(gate.calls == [1_500, 400])
        #expect(rec.last?.status == "Přihlašuji jako OK1XOE…")
        try session.disconnect("Konec")
    }

    @Test func autoLoginWithoutPasswordSkipsPasswordDelay() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let session = Self.makeSession(rec, gate: gate)

        try session.connect(Self.favorite(server, password: "\u{00A0}"), autoLogin: true)
        try await Self.waitCommands(server, count: 1)
        await session.idle()
        #expect(server.commands(0) == ["OK1XOE\r"])
        #expect(gate.calls == [1_500])
        try session.disconnect("Konec")
    }

    @Test func autoLoginSkippedForBlankLogin() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let session = Self.makeSession(rec, gate: gate)

        // Kotlin `isBlank`: U+00A0 is a whitespace character (Java `isBlank` would not take it).
        try session.connect(Self.favorite(server, login: " \u{00A0}"), autoLogin: true)
        try await rec.wait { $0.last?.connected == true }
        await session.idle()
        #expect(gate.calls.isEmpty)
        #expect(rec.last?.status == "Připojeno k Test")
        try session.disconnect("Konec")
        #expect(server.commands(0).isEmpty)
    }

    /// Waits until the gate has been entered; records an issue instead of hanging when it never is (10 s).
    private static func waitRequested(_ gate: SleepGate) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while gate.calls.isEmpty {
            if ContinuousClock.now >= deadline {
                Issue.record("The hold was never reached within 10 s")
                return false
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    @Test func autoLoginSkippedWhenDisconnectedDuringDelay() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate(blocking: true)
        let session = Self.makeSession(rec, gate: gate)

        try session.connect(Self.favorite(server), autoLogin: true)
        guard await Self.waitRequested(gate) else { return }
        try session.disconnect("Konec")
        gate.release()
        await session.idle()
        #expect(gate.calls == [1_500])
        #expect(rec.statuses == ["Připojuji k Test…", "Připojeno k Test", "Konec"])
        #expect(server.commands(0).isEmpty)
    }

    /// A connect that finishes after a `disconnect` (the quit, the parallel plan) closes its client: never adopted,
    /// never connected, no auto-login (not Kotlin — technique). The connect thread is held after its client exists, so
    /// the `disconnect` always lands while the connect is in flight (no timing).
    @Test func aConnectFinishingAfterADisconnectIsClosed() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let held = SleepGate(blocking: true)
        let session = Self.makeSession(rec, gate: gate)
        session.onClientCreated = { held.sleep(0) }
        try session.connect(Self.favorite(server), autoLogin: true)
        guard await Self.waitRequested(held) else { return }
        try session.disconnect("Konec")
        held.release()
        await session.idle()
        #expect(!session.snapshot.connected)
        #expect(rec.statuses == ["Připojuji k Test…", "Konec"])
        #expect(gate.calls.isEmpty)
        #expect(server.commands(0).isEmpty)
    }

    /// Control for the hold above: without a `disconnect` the held connect is adopted and auto-logs in.
    @Test func aHeldConnectIsAdoptedWithoutADisconnect() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let held = SleepGate(blocking: true)
        let session = Self.makeSession(rec, gate: gate)
        session.onClientCreated = { held.sleep(0) }
        try session.connect(Self.favorite(server, password: ""), autoLogin: true)
        guard await Self.waitRequested(held) else { return }
        #expect(rec.statuses == ["Připojuji k Test…"])
        held.release()
        try await Self.waitCommands(server, count: 1)
        await session.idle()
        #expect(rec.statuses == ["Připojuji k Test…", "Připojeno k Test", "Přihlašuji jako OK1XOE…"])
        #expect(gate.calls == [1_500])
        try session.disconnect("Konec")
    }

    @Test func loginConfirmationIsFirstLineContainingTrimmedTokenIgnoringCase() async throws {
        let reply: [FakeLineServer.Step] = [.line("no call here"), .line("Hello OK1XOE de node")]
        let again: [FakeLineServer.Step] = [.line("OK1XOE again"), .line("done")]
        let server = try FakeLineServer(script: [" ok1xoe \r": reply, "SH/DX\r": again], fallback: [.silent],
                                        onConnect: [.line("Welcome OK1XOE")])
        defer { server.stop() }
        let rec = Recorder()
        let gate = SleepGate()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, gate: gate, log: log)
        let fav = Self.favorite(server, login: " ok1xoe ", password: "")

        try session.connect(fav)
        // A row with a callsign before `login` does not confirm the login.
        try await Self.waitLog(log, contains: "Welcome OK1XOE")
        #expect(!session.loggedIn)

        session.login(fav)
        try await rec.wait { $0.last?.loggedIn == true }
        // The login is sent untrimmed, the confirmation token is Kotlin `trim()`.
        #expect(server.commands(0) == [" ok1xoe \r"])
        #expect(rec.statuses.suffix(2) == ["Přihlašuji jako  ok1xoe …", "Přihlášeno jako ok1xoe"])
        #expect(gate.calls.isEmpty)

        try session.send("SH/DX")
        try await Self.waitLog(log, contains: "done")
        #expect(rec.statuses.filter { $0.hasPrefix("Přihlášeno") }.count == 1)
        try session.disconnect("Konec")
    }

    @Test func loginWithoutClientOrWithBlankLogin() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let session = Self.makeSession(rec)
        let fav = Self.favorite(server)

        session.login(fav)
        try session.logout()
        try session.send("SH/DX")
        #expect(rec.all.isEmpty)

        try session.connect(fav)
        try await rec.wait { $0.last?.connected == true }
        session.login(Self.favorite(server, login: "\u{2007}"))
        #expect(rec.last?.status == "Favorit nemá vyplněné přihlašovací jméno")
        try session.disconnect("Konec")
        #expect(server.commands(0).isEmpty)
    }

    @Test func blankHostOnlySetsStatus() throws {
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log)
        var fav = Self.favorite(nil, port: 7300)
        fav.host = "\u{202F}\t"
        try session.connect(fav)
        #expect(rec.statuses == ["Chybí adresa clusteru"])
        #expect(!session.connecting)
        #expect(log.snapshot().isEmpty)
    }

    @Test func connectFailureReportsJavaText() async throws {
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log)
        let port: Int = FreeLoopbackPort.take()
        // Without a name: the status text takes the host (Kotlin `ifBlank`).
        try session.connect(Self.favorite(nil, port: port, name: " "))
        try await rec.wait { $0.last?.connecting == false }
        await session.idle()
        let failure = "Připojení selhalo: Nelze se připojit k DX clusteru na 127.0.0.1:" + String(port)
        #expect(rec.statuses == ["Připojuji k 127.0.0.1…", failure])
        #expect(!session.connected)
        #expect(Self.bodies(log) == ["\u{00B7} Připojuji k 127.0.0.1:" + String(port) + "…", "\u{00B7} " + failure])
    }

    // MARK: - Row distribution

    @Test func routesSpotsSelfSpotAndWwvWithTag() async throws {
        let lines: [FakeLineServer.Step] = [
            .line("DX de W1AW-#:   14025.0  OK1XOE   CW 21 dB 25 WPM CQ  1234Z"),
            .line("DX de OK1ABC:     14030.0  OH2AS         CQ up 2          1234Z"),
            .line("WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms"),
            .line("done"),
        ]
        let server = try FakeLineServer(script: ["SH/DX\r": lines], fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log, tag: "RBN")
        session.myCall = " ok1xoe "
        session.onSelfSpot = { rec.selfSpot($0) }
        // An error from `onSpot` is swallowed (Kotlin `runCatching`) and the connection keeps running.
        session.onSpot = { spot in
            rec.spot(spot)
            throw DxClusterException("posluchač spadl")
        }

        try session.connect(Self.favorite(server))
        try await rec.wait { $0.last?.connected == true }
        try session.send("  SH/DX  ")
        try await Self.waitLog(log, contains: "[RBN] done")

        #expect(session.connected)
        #expect(server.commands(0) == ["SH/DX\r"])
        #expect(session.spots.snapshot().map(\.dxCall) == ["OK1XOE", "OH2AS"])
        #expect(rec.allSpots.map(\.dxCall) == ["OK1XOE", "OH2AS"])
        let own = SelfSpot(spotter: "W1AW-#", freqHz: 14_025_000, rbn: true, snrDb: 21, wpm: 25, at: Self.at)
        #expect(rec.allSelfSpots == [own])
        let wwv = WwvMessage(spotter: "VE7CC", hourUtc: 18, sfi: 142, aIndex: 8, kIndex: 3,
                             conditions: "No Storms -> No Storms")
        #expect(session.lastWwv == wwv)
        #expect(rec.last?.lastWwv == wwv)
        let body: [String] = Self.bodies(log)
        #expect(body.contains("\u{00BB} SH/DX"))
        #expect(body.contains("[RBN] DX de OK1ABC:     14030.0  OH2AS         CQ up 2          1234Z"))
        #expect(rec.unexpectedErrors.isEmpty)
        try session.disconnect("Konec")
        // `disconnect` keeps the last WWV.
        #expect(session.lastWwv == wwv)
    }

    @Test(arguments: [
        "WWV de VE7CC <18Z> :   SFI=99999999999, A=8, K=3",
        "DX de W1AW-#:   14025.0  OK1XOE   CW 99999999999 dB 25 WPM CQ  1234Z",
    ])
    func numberOverflowEndsConnectionLikeJava(line: String) async throws {
        let server = try FakeLineServer(script: ["SH/DX\r": [.line(line), .line("never")]], fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log)
        session.myCall = "OK1XOE"

        try session.connect(Self.favorite(server))
        try await rec.wait { $0.last?.connected == true }
        try session.send("SH/DX")
        try await rec.wait { $0.last?.connected == false }

        let lost = "Spojení ztraceno: For input string: \"99999999999\""
        #expect(rec.last?.status == lost)
        #expect(rec.last?.currentFavorite == nil)
        #expect(session.lastWwv == nil)
        #expect(Self.bodies(log).last == "\u{00B7} " + lost)
        #expect(!Self.bodies(log).contains("never"))
    }

    // MARK: - Logout, commands, disconnect

    @Test func logoutSendsByeAndServerCloseIsConnectionLost() async throws {
        let server = try FakeLineServer(script: ["BYE\r": [.close]], fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log)

        try session.connect(Self.favorite(server))
        try await rec.wait { $0.last?.connected == true }
        try session.logout()
        try await rec.wait { $0.last?.connected == false }
        await session.idle()

        #expect(server.commands(0) == ["BYE\r"])
        let expected: [String] = ["Připojuji k Test…", "Připojeno k Test", "Odhlašuji…",
                                  "Spojení ztraceno: DX cluster ukončil spojení"]
        #expect(rec.statuses == expected)
        let body: [String] = Self.bodies(log)
        #expect(body.contains("\u{00BB} BYE"))
        #expect(body.last == "\u{00B7} Spojení ztraceno: DX cluster ukončil spojení")
    }

    @Test func sendTrimsIgnoresBlankAndToggleDisconnects() async throws {
        let server = try FakeLineServer(script: ["sh/dx\r": [.line("ok")]], fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let log = DxClusterTrafficLog()
        let session = Self.makeSession(rec, log: log)
        let fav = Self.favorite(server)

        try session.toggle(fav)
        try await rec.wait { $0.last?.connected == true }
        try session.send(" \u{00A0}")
        try session.send("\u{00A0}sh/dx\t")
        try await Self.waitLog(log, contains: "ok")
        #expect(server.commands(0) == ["sh/dx\r"])

        try session.toggle(fav)
        #expect(rec.last?.status == "Odpojeno")
        #expect(!session.connected)
        #expect(Self.bodies(log).last == "\u{00B7} Odpojeno")
        try session.send("SH/DX")
        #expect(Self.bodies(log).last == "\u{00B7} Odpojeno")
    }

    @Test func statusTextsGoThroughTranslation() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let rec = Recorder()
        let table: [String: String] = ["Připojeno k %s": "Connected to %s", "Připojuji k %s…": "Bad %d…"]
        let session = Self.makeSession(rec, translate: { table[$0] ?? $0 })

        try session.connect(Self.favorite(server))
        try await rec.wait { $0.last?.connected == true }
        // An invalid translation (Kotlin would throw an exception from `format`) → the Czech original.
        #expect(rec.statuses == ["Připojuji k Test…", "Connected to Test"])
        try session.disconnect("Konec")
    }

    @Test func trafficLogFailureFollowsKotlin() throws {
        // Java defect of a negative capacity (a deliberate divergence from Java v1.1.1): the listing throws, a synchronous call lets it through.
        let rec = Recorder()
        let session = Self.makeSession(rec, log: DxClusterTrafficLog(maxLines: -1))
        #expect(throws: JavaNoSuchElementError.self) {
            try session.connect(Self.favorite(nil, port: 7300))
        }
        #expect(session.connecting)
        #expect(rec.statuses == ["Připojuji k Test…"])
        #expect(throws: JavaNoSuchElementError.self) {
            try session.disconnect("Konec")
        }
        #expect(rec.last?.status == "Konec")
        #expect(DxClusterSession.javaMessage(JavaNoSuchElementError()) == "null")
    }

    // MARK: - Kotlin texts

    @Test func kotlinTextHelpers() {
        #expect(KotlinText.isBlank(""))
        #expect(KotlinText.isBlank(" \u{00A0}\u{2007}\u{202F}\u{3000}\u{1C}"))
        #expect(!KotlinText.isBlank("\u{01}"))
        #expect(!KotlinText.isBlank("\u{85}"))
        #expect(KotlinText.trim(" OK1\u{00A0}") == "OK1")
        #expect(KotlinText.trim("\u{01}OK1 ") == "\u{01}OK1")
        #expect(KotlinText.trim("\tOK1\u{3000}") == "OK1")
        #expect(KotlinText.containsIgnoreCase("welcome ok1xoe", "OK1XOE"))
        #expect(KotlinText.containsIgnoreCase("welcome \u{130}", "i"))
        #expect(KotlinText.containsIgnoreCase("welcome \u{131}", "I"))
        #expect(!KotlinText.containsIgnoreCase("stra\u{DF}e", "STRASSE"))
        #expect(KotlinText.containsIgnoreCase("\u{3C2}", "\u{3A3}"))
    }
}
