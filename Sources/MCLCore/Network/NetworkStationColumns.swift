import Foundation

/// A column of the Network Status station table (N1MM Network Status → Stations: computer, operator, band, mode,
/// frequency, Run/S&P, pass frequency, rates, last QSO). The raw value is what `AppConfig.networkStatusColumns` stores.
public enum NetworkStationColumn: String, CaseIterable, Sendable, Equatable {
    case station
    case `operator`
    case type
    case band
    case mode
    case freq
    case runMode
    case pass
    case qsos
    case rate10
    case rate100
    case lastQso
    case state

    /// The header key (Czech; `translate` false for `kHz` and `QSO`).
    public var header: NetTexts.Header {
        switch self {
        case .station: return NetTexts.Header(text: "Stanice", translate: true)
        case .operator: return NetTexts.Header(text: "Operátor", translate: true)
        case .type: return NetTexts.Header(text: "Typ", translate: true)
        case .band: return NetTexts.Header(text: "Pásmo", translate: true)
        case .mode: return NetTexts.Header(text: "Mód", translate: true)
        case .freq: return NetTexts.Header(text: "kHz", translate: false)
        case .runMode: return NetTexts.Header(text: "Režim", translate: true)
        case .pass: return NetTexts.Header(text: "Pass kHz", translate: true)
        case .qsos: return NetTexts.Header(text: "QSO", translate: false)
        case .rate10: return NetTexts.Header(text: "Rate 10", translate: true)
        case .rate100: return NetTexts.Header(text: "Rate 100", translate: true)
        case .lastQso: return NetTexts.Header(text: "Posl. QSO", translate: true)
        case .state: return NetTexts.Header(text: "Stav", translate: true)
        }
    }

    /// The column width in points at the default font size.
    public var width: Double {
        switch self {
        case .station, .operator: return 90
        case .type: return 50
        case .band, .mode: return 60
        case .freq, .pass: return 80
        case .runMode, .qsos: return 50
        case .rate10, .rate100: return 60
        case .lastQso: return 120
        case .state: return 110
        }
    }

    /// The default order: v1.1.1's eight columns with the type after the operator and the new ones before the state.
    public static let defaultOrder: [NetworkStationColumn] = [
        .station, .operator, .type, .band, .mode, .freq, .runMode, .pass, .qsos, .rate10, .rate100, .lastQso, .state,
    ]

    /// The saved columns: unknown and repeated names dropped; an empty list (never configured) is the default order.
    /// `station` is always kept as the first column (it names the row).
    public static func resolve(_ saved: [String]) -> [NetworkStationColumn] {
        var out: [NetworkStationColumn] = []
        for name in saved {
            if let column = NetworkStationColumn(rawValue: name), !out.contains(column) {
                out.append(column)
            }
        }
        if out.isEmpty {
            return defaultOrder
        }
        out.removeAll { $0 == .station }
        return [.station] + out
    }

    /// The columns with `column` shown or hidden (a shown one is added at its default position relative to the
    /// shown ones); `station` cannot be hidden.
    public static func toggled(_ columns: [NetworkStationColumn], _ column: NetworkStationColumn)
        -> [NetworkStationColumn] {
        guard column != .station else { return columns }
        if columns.contains(column) {
            return columns.filter { $0 != column }
        }
        let rank: Int = defaultOrder.firstIndex(of: column) ?? defaultOrder.count
        var out: [NetworkStationColumn] = columns
        let insertAt: Int = out.firstIndex { (defaultOrder.firstIndex(of: $0) ?? 0) > rank } ?? out.count
        out.insert(column, at: max(1, insertAt))
        return out
    }

    /// The columns with `column` moved one place left (`by: -1`) or right (`by: 1`); `station` stays first.
    public static func moved(_ columns: [NetworkStationColumn], _ column: NetworkStationColumn, by delta: Int)
        -> [NetworkStationColumn] {
        guard column != .station, let index = columns.firstIndex(of: column) else { return columns }
        let target: Int = index + delta
        guard target >= 1, target < columns.count else { return columns }
        var out: [NetworkStationColumn] = columns
        out.swapAt(index, target)
        return out
    }
}

/// What the Network Status table shows of a station besides its published state: the rates and the last QSO computed
/// from the shared log (the QSOs carry the station id of their origin) and the pass frequency it announced (Alt+Z).
public struct NetworkStationExtras: Equatable, Sendable {
    /// N1MM rate of the last 10 / 100 QSOs (QSOs per hour).
    public var rate10: Int = 0
    public var rate100: Int = 0
    /// The last QSO of the station: `call HHmm`, `""` without one.
    public var lastQso: String = ""
    /// The announced pass frequency (Hz), 0 = none.
    public var passHz: Int = 0

    public init(rate10: Int = 0, rate100: Int = 0, lastQso: String = "", passHz: Int = 0) {
        self.rate10 = rate10
        self.rate100 = rate100
        self.lastQso = lastQso
        self.passHz = passHz
    }

    /// The extras of every station id found in `qsos` (deleted QSOs and QSOs without an origin are skipped) merged with
    /// the announced pass frequencies.
    public static func compute(_ qsos: [Qso], passFrequencies: [String: Int]) -> [String: NetworkStationExtras] {
        var byStation: [String: [Qso]] = [:]
        for qso in qsos where !qso.deleted && !qso.stationId.isEmpty {
            byStation[qso.stationId, default: []].append(qso)
        }
        var out: [String: NetworkStationExtras] = [:]
        for (station, list) in byStation {
            let stats: ContestStats = ContestStats.of(list)
            var extras = NetworkStationExtras(rate10: stats.rateForLastQsos(10), rate100: stats.rateForLastQsos(100))
            let last: Qso? = list.filter { $0.timestampUtc != nil }.max { a, b in
                (a.timestampUtc ?? .distantPast) < (b.timestampUtc ?? .distantPast)
            }
            if let last, let time = last.timestampUtc {
                extras.lastQso = last.call + " " + MacroTime.format(time, "HHmm")
            }
            out[station] = extras
        }
        for (station, hz) in passFrequencies where hz > 0 {
            out[station, default: NetworkStationExtras()].passHz = hz
        }
        return out
    }
}

extension NetTexts {

    /// The text of one cell of a peer row.
    public static func cell(_ column: NetworkStationColumn, _ peer: StationNetwork.Peer, extras: NetworkStationExtras,
                            translator: Translator) -> String {
        let status: StationStatusWire = peer.status
        switch column {
        case .station: return status.stationId ?? "null"
        case .operator: return status.operator ?? ""
        case .type: return status.stationType ?? ""
        case .band: return status.band ?? ""
        case .mode: return status.mode ?? ""
        case .freq: return status.freqHz > 0 ? NetMessages.kHz(status.freqHz) : ""
        case .runMode: return status.runMode ?? ""
        case .pass: return extras.passHz > 0 ? NetMessages.kHz(extras.passHz) : ""
        case .qsos: return peer.online ? String(status.qsoCount) : ""
        case .rate10: return extras.rate10 > 0 ? String(extras.rate10) : ""
        case .rate100: return extras.rate100 > 0 ? String(extras.rate100) : ""
        case .lastQso: return extras.lastQso
        case .state: return peerState(peer, translator: translator)
        }
    }
}
