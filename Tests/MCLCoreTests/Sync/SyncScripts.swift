import Foundation
@testable import MCLCore

/// A collection mailbox for listeners (`@Sendable` closures must not mutate a captured `var`); the tests run synchronously
/// on one thread, the lock is only for `Sendable`.
final class Collected<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T] = []

    func add(_ value: T) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int { values.count }
}

/// A listener call counter.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0

    func increment() {
        lock.lock()
        n += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return n
    }
}

/// An advanceable clock (Java `MutableClock` from `StationNetworkTest`).
final class FakeInstantClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: JavaInstant

    init(_ start: JavaInstant) {
        current = start
    }

    var now: JavaInstant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(seconds: Int64, nanos: Int64 = 0) {
        lock.lock()
        current = current.plus(seconds: seconds, nanos: nanos) ?? current
        lock.unlock()
    }
}

/// Scripts of the sections `sync.COORD` and `sync.NET` (`SyncSections.runCoord`/`runNet`): the same steps over
/// `InMemorySyncTransport`, the same state writing after every step.
enum SyncScripts {

    typealias S = SyncParitySections

    static func coordTs(_ k: Int) -> JavaInstant {
        let millis: Int64 = 1_790_000_000_000 + Int64(k) * 61_001
        return JavaInstant.ofEpochSecond(millis / 1_000, (millis % 1_000) * 1_000_000)!
    }

    static func coordWire(_ call: String, _ k: Int) -> QsoWire {
        QsoWire(timestampUtc: coordTs(k), call: call, freqHz: 14_025_000, band: "M20", mode: "CW", rstSent: "599",
                rstRcvd: "599", exchangeSent: nil, exchangeRcvd: "0" + String(k), serialSent: Int32(k), serialRcvd: nil,
                operator: nil, comment: nil, dxccEntity: nil, dxccName: nil, continent: "EU")
    }

    final class Station {
        let repo: LogbookRepository
        let logbook: LogbookService
        let coord: SyncCoordinator
        let changes = Counter()
        let spots = Collected<SpotWire>()

        init(_ index: Int, _ transport: InMemorySyncTransport) throws {
            repo = try LogbookRepository.inMemory()
            logbook = LogbookService(repository: repo)
            logbook.activeContestId = "c1"
            let changes = self.changes
            coord = SyncCoordinator(logbook: logbook, transport: transport, stationId: "OP" + String(index + 1),
                                    onChange: { changes.increment() })
            let spots = self.spots
            coord.shareSpots { spots.add($0) }
        }
    }

    static func coordinator(_ script: [String]) throws -> [String] {
        var out: [String] = []
        let t = InMemorySyncTransport()
        let n = Int(script[0].dropFirst(2)) ?? 1
        var st: [Station] = []
        for i in 0..<n {
            st.append(try Station(i, t))
        }
        var k = 0
        for step in script.dropFirst() {
            k += 1
            let f: [String] = step.split(separator: ":").map(String.init)
            var res = "ok"
            do {
                try coordStep(f, k, t, st)
            } catch {
                res = "throws"
            }
            out += ["#" + String(k), res, S.b(t.isConnected)]
            for x in st {
                out += [String(x.changes.value), S.b(x.coord.isConnected)]
                let rows: [Qso] = try x.logbook.findAllIncludingDeleted()
                out.append(String(rows.count))
                for q in rows {
                    out += coordRow(q)
                }
                out.append(String(try x.logbook.findAll().count))
                out.append(String(x.spots.count))
                for sp in x.spots.values {
                    let parts: [String] = [sp.stationId ?? "null", sp.dxCall ?? "null", String(sp.freqHz)]
                    out.append(S.tx(parts.joined(separator: "|")))
                }
            }
        }
        for x in st {
            x.repo.close()
        }
        return out
    }

    static func coordStep(_ f: [String], _ k: Int, _ t: InMemorySyncTransport, _ st: [Station]) throws {
        let station: Station? = f.count > 1 ? Int(f[1]).map { st[$0] } : nil
        switch f[0] {
        case "start":
            try station?.coord.start()
        case "ins":
            try t.publishInsert(QsoCommand(stationId: "OP9", uuid: f[1], clientTimestampUtc: coordTs(k),
                                           qso: coordWire(f[2], Int(f[3]) ?? 0)))
        case "upd":
            try t.publishUpdate(QsoCommand(stationId: "OP9", uuid: f[1], clientTimestampUtc: coordTs(k),
                                           qso: coordWire(f[2], Int(f[3]) ?? 0)))
        case "del":
            try t.publishDelete(DeleteCommand(stationId: "OP9", uuid: f[1], clientTimestampUtc: coordTs(k)))
        case "local":
            var q = Qso()
            q.call = f[3]
            q.timestampUtc = coordTs(k).date
            q.freqHz = 7_025_000
            q.mode = .ssb
            q.uuid = f[2]
            try station?.coord.publishInsert(q)
        case "localdel":
            var q = Qso()
            q.uuid = f[2]
            q.timestampUtc = coordTs(k).date
            try station?.coord.publishDelete(q)
        case "state":
            let wire: QsoWire? = f[6] == "payload" ? coordWire(f[5], k) : nil
            let state = QsoState(uuid: f[2], stationId: "OP8", version: Int64(f[3]) ?? 0,
                                 updatedAtUtc: wire == nil ? nil : coordTs(k), deleted: f[4] == "1", qso: wire)
            try station?.coord.onState(state)
        case "nullstate":
            try station?.coord.onState(nil)
        case "noid":
            try station?.coord.onState(QsoState(uuid: nil, stationId: "OP8", version: 9, updatedAtUtc: coordTs(k),
                                                deleted: false, qso: coordWire("NOID", k)))
        case "spot":
            try station?.coord.publishSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: f[2], comment: "CQ")
        case "contest":
            station?.logbook.activeContestId = f[2] == "~" ? "" : f[2]
        default:
            station?.coord.close()
        }
    }

    static func coordRow(_ q: Qso) -> [String] {
        var o: [String] = [q.id.map { String($0) } ?? "~", S.tx(q.uuid), S.tx(q.stationId), String(q.version)]
        o += [S.b(q.deleted), S.tx(q.call), String(q.freqHz), q.band?.javaName ?? "~", q.mode?.rawValue ?? "~"]
        o += [q.serialSent.map { String($0) } ?? "~", S.tx(q.exchangeRcvd), S.tx(q.contestId)]
        o += [S.millis(q.timestampUtc), S.millis(q.updatedAtUtc), S.b(q.xqso), S.tx(q.continent)]
        return o
    }

    // MARK: - sync.NET

    final class NetStation {
        let net: StationNetwork
        let changes = Counter()
        let messages = Collected<NetMessageWire>()
        let serials = Collected<SerialReply>()

        init(_ net: StationNetwork) {
            self.net = net
        }
    }

    static func nul(_ f: String) -> String? {
        f == "~" ? nil : f
    }

    static func network(_ script: [String]) throws -> [String] {
        var out: [String] = []
        let t = InMemorySyncTransport()
        let clock = FakeInstantClock(JavaInstant.parseIsoInstant("2026-11-28T12:00:00Z")!)
        let n = Int(script[0].dropFirst(2)) ?? 2
        var st: [NetStation] = []
        for i in 0..<n {
            st.append(NetStation(StationNetwork(transport: t, stationId: "STN" + String(i + 1),
                                                clock: { clock.now })))
        }
        var k = 0
        for step in script.dropFirst() {
            k += 1
            let f: [String] = step.components(separatedBy: ":")
            var res: [String]
            do {
                res = try netStep(f, t, st, clock)
            } catch {
                res = ["throws"]
            }
            out.append("#" + String(k))
            out += res
            for x in st {
                out.append(String(x.changes.value))
                out.append(String(x.messages.count))
                for m in x.messages.values {
                    out += message(m)
                }
                out.append(String(x.serials.count))
                for r in x.serials.values {
                    let parts: [String] = [r.stationId ?? "null", r.requestId ?? "null", String(r.serial)]
                    out.append(S.tx(parts.joined(separator: "|")))
                }
            }
        }
        return out
    }

    static func netStep(_ f: [String], _ t: InMemorySyncTransport, _ st: [NetStation],
                        _ clock: FakeInstantClock) throws -> [String] {
        let stationSteps: Set<String> = ["start", "onmsg", "onser", "pub", "off", "send", "req", "lock", "peers"]
        let x: NetStation? = stationSteps.contains(f[0]) ? Int(f[1]).map { st[$0] } : nil
        switch f[0] {
        case "start":
            let changes = x!.changes
            try x!.net.start { changes.increment() }
        case "onmsg":
            let messages = x!.messages
            x!.net.onMessages { messages.add($0) }
        case "onser":
            let serials = x!.serials
            x!.net.onSerialReplies { serials.add($0) }
        case "pub":
            let w = StationStatusWire(stationId: "x", operator: "OK1XOE", stationType: "RUN", band: nul(f[2]), mode: "CW",
                                      freqHz: 14_025_000, runMode: "RUN", qsoCount: Int32(f[3]) ?? 0,
                                      transmitting: f[4] == "1", online: true, timestampUtc: nil, entryCall: f[5])
            return [S.b(try x!.net.publish(w))]
        case "adv":
            clock.advance(seconds: Int64(f[1]) ?? 0, nanos: Int64(f[2]) ?? 0)
        case "off":
            try x!.net.goOffline()
        case "send":
            let m = try x!.net.send(nul(f[2]), operator: "OP", to: nul(f[3]), text: nul(f[4]), call: nul(f[5]),
                                    freqHz: Int(f[6]) ?? 0, mode: nul(f[7]))
            return message(m)
        case "req":
            try x!.net.requestSerial(f[2])
        case "seed":
            if f[3] == "1" {
                try t.publishDelete(DeleteCommand(stationId: "STN9", uuid: f[1], clientTimestampUtc: nil))
            } else {
                let wire = QsoWire(timestampUtc: nil, call: "X", freqHz: 0, band: nil, mode: nil, rstSent: nil, rstRcvd: nil,
                                   exchangeSent: nil, exchangeRcvd: nil, serialSent: f[2] == "~" ? nil : Int32(f[2]),
                                   serialRcvd: nil, operator: nil, comment: nil, dxccEntity: nil, dxccName: nil,
                                   continent: nil)
                try t.publishInsert(QsoCommand(stationId: "STN9", uuid: f[1], clientTimestampUtc: nil, qso: wire))
            }
        case "lock":
            let scope: Interlock.Scope? = f[2] == "~" ? nil : Interlock.Scope(rawValue: f[2])
            return [S.tx(Interlock.lockedBy(x!.net.peers(), scope, nul(f[3])))]
        case "raw":
            try t.publishStatus(StationStatusWire(stationId: nul(f[1]), operator: "", stationType: "", band: "40m",
                                                  mode: "", freqHz: 0, runMode: "", qsoCount: 0, transmitting: true,
                                                  online: f[2] == "1", timestampUtc: nil, entryCall: ""))
        default:
            let peers: [StationNetwork.Peer] = x!.net.peers()
            var res: [String] = [String(peers.count)]
            for p in peers {
                let (seconds, atto) = p.age.components
                res += [S.tx(p.status.stationId), S.b(p.online), String(seconds) + ":" + String(atto / 1_000_000_000)]
                res += [S.inst(p.receivedAt), S.tx(p.status.band), String(p.status.qsoCount), S.b(p.status.transmitting)]
                res += [S.tx(p.status.timestampUtc), S.tx(p.status.entryCall)]
            }
            return res
        }
        return ["ok"]
    }

    static func message(_ m: NetMessageWire) -> [String] {
        var o: [String] = [S.tx(m.type), S.tx(m.fromStation), S.tx(m.fromOperator), S.tx(m.toStation), S.tx(m.text)]
        o += [S.tx(m.call), String(m.freqHz), S.tx(m.mode), S.tx(m.timestampUtc)]
        return o
    }
}
