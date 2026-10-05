/// The antenna of v1.1.1 (`AppState.currentAntenna`, `autoSelectAntenna`, `nextAntenna`, `applyAntenna` —
/// `AS:767-797`) with the identity rules (a)–(c): Kotlin compares antennas by identity
/// (`currentAntenna === a`), Swift by the index into `config.antennas`:
/// (a) `currentIndex` carries the identity, `current` the shown value;
/// (b) every write of `config.antennas` (each Settings save) resets the index to `nil` and keeps the value;
/// (c) `applyAntenna` skips only when `index != nil && index == the new index`.
public struct AntennaApply: Sendable, Equatable {

    /// What applying an antenna sends to the hardware (on a background lane, results ignored as in Kotlin).
    public struct Plan: Equatable, Sendable {
        /// OTRSP `aux(port, code)` when a controller is open: `(activeVfo + 1, code.coerceIn(0, 15))`.
        public let otrspAux: (port: Int, code: Int)
        /// `rig.setAntenna(code)` when `isAntennaViaRig`, a rig is connected and `code in 1..4`; otherwise `nil`.
        public let rigAntenna: Int?
        /// The status shown right away (`tr("Anténa: %s (kód %s)")`), without waiting for the hardware.
        public let status: EntryStatus

        public static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.otrspAux == rhs.otrspAux && lhs.rigAntenna == rhs.rigAntenna && lhs.status == rhs.status
        }
    }

    /// The outcome of Alt+F9-style "next antenna".
    public enum NextOutcome: Equatable, Sendable {
        /// No tuned band (`currentBand ?: return`) — nothing at all.
        case noBand
        /// No antenna for the band — `RigTexts.noAntennaForBand`.
        case none(EntryStatus)
        /// Apply this antenna (`nil` = the same index again, rule (c) — nothing).
        case apply(Plan?)
    }

    /// The identity (index into `config.antennas`), rule (a).
    public private(set) var currentIndex: Int?
    /// `currentAntenna` — what the entry window shows.
    public private(set) var current: AntennaEntry?

    public init() {}

    /// `applyAntenna` rule (c) + the hardware plan. `nil` = the same antenna (by index), nothing happens.
    public mutating func apply(index: Int, antennas: [AntennaEntry], activeVfo: Int, viaRig: Bool,
                               rigConnected: Bool) -> Plan? {
        guard index >= 0, index < antennas.count else { return nil }
        if let currentIndex, currentIndex == index {
            return nil
        }
        let entry = antennas[index]
        currentIndex = index
        current = entry
        return Self.plan(entry: entry, activeVfo: activeVfo, viaRig: viaRig, rigConnected: rigConnected)
    }

    /// The hardware half of `applyAntenna` (`AS:787-795`).
    public static func plan(entry: AntennaEntry, activeVfo: Int, viaRig: Bool, rigConnected: Bool) -> Plan {
        let code = Swift.min(Swift.max(entry.code, 0), 15)
        let rig: Int? = viaRig && rigConnected && (1...4).contains(entry.code) ? entry.code : nil
        return Plan(otrspAux: (activeVfo + 1, code), rigAntenna: rig, status: RigTexts.antenna(entry))
    }

    /// `autoSelectAntenna(band)` (`AS:775-779`, called by `updateTuned` on a band change): the antenna for the band by
    /// the azimuth to the typed call; `nil` = nothing to apply (no antenna, or the same index).
    public mutating func autoSelect(band: Band, azimuth: Int?, antennas: [AntennaEntry], activeVfo: Int,
                                    viaRig: Bool, rigConnected: Bool) -> Plan? {
        guard let index = AntennaSelector.select(antennas, band: band, azimuth: azimuth) else { return nil }
        return apply(index: index, antennas: antennas, activeVfo: activeVfo, viaRig: viaRig,
                     rigConnected: rigConnected)
    }

    /// `nextAntenna` (`AS:782-786`).
    public mutating func next(band: Band?, antennas: [AntennaEntry], activeVfo: Int, viaRig: Bool,
                              rigConnected: Bool) -> NextOutcome {
        guard let band else { return .noBand }
        guard let index = AntennaSelector.next(antennas, band: band, currentIndex: currentIndex) else {
            return .none(RigTexts.noAntennaForBand(band))
        }
        return .apply(apply(index: index, antennas: antennas, activeVfo: activeVfo, viaRig: viaRig,
                            rigConnected: rigConnected))
    }

    /// Rule (b): `config.antennas` was written — the index is forgotten, the shown antenna stays.
    public mutating func antennasChanged() {
        currentIndex = nil
    }
}
