import Foundation

/// Move Multipliers window logic (Kotlin `MoveMultipliersWindow.kt`, `AppState.requestMove`, `AS:1621-1642`).
/// Pure: the caller sends the CW text (through the TX gate and the simulator) and shows the status.
public enum MoveRequest {

    /// How many of the latest QSOs the window goes through (`MOVE_RECENT`).
    public static let recentLimit: Int = 25

    /// What a request produces: the CW text to send (`nil` outside CW) and the status line.
    public struct Request: Equatable, Sendable {
        /// `PSE QSY <kHz>` for a CW QSO, otherwise `nil`.
        public let cwText: String?
        /// The callsign the CW text is addressed to (`%` macros of the message builder), the QSO's.
        public let hisCall: String
        public let status: String
    }

    /// `moveFrequencyHz`: where to call the station — my CQ frequency on the band, otherwise the last one used on it.
    public static func frequencyHz(band: Band, cq: Int64?, last: Int64?) -> Int64? {
        cq ?? last
    }

    /// Asks a station to move to `bandAdif`. `hz` is `frequencyHz(band:cq:last:)` for that band. `nil` when `bandAdif`
    /// is not a band (Kotlin returns silently).
    ///
    /// CW: `PSE QSY <kHz>` (`%.0f`, US) or the upper-cased band without a frequency, status `odesláno PSE QSY`;
    /// otherwise only a hint with the frequency (`%.1f kHz`) or the band as given.
    public static func request(qso: Qso, bandAdif: String, hz: Int64?, translate: Translator) -> Request? {
        guard Band.from(adif: bandAdif) != nil else { return nil }
        let place: String
        if let hz {
            place = JavaFormat.format("%.0f", .double(Double(hz) / 1000.0))
        } else {
            place = JavaText.toUpperCase(bandAdif)
        }
        if qso.mode == .cw {
            let status: String = translate.translate("%s: odesláno PSE QSY %s", [.string(qso.call), .string(place)])
            return Request(cwText: "PSE QSY \(place)", hisCall: qso.call, status: status)
        }
        let target: String = hz.map { CatStatusLine.khz($0) } ?? bandAdif
        let status: String = translate.translate("%s: požádej o QSY na %s (nový násobič)",
                                                 [.string(qso.call), .string(target)])
        return Request(cwText: nil, hisCall: qso.call, status: status)
    }

    /// Status for the "→" button when the band has no known frequency.
    public static func noFrequencyText(band: String, translate: Translator) -> String {
        translate.translate("Na %s ještě nemám frekvenci — přelaď ručně (Ctrl+PgUp/PgDn)", [.string(band)])
    }

    /// The explanatory text above the list.
    public static func hint(translate: Translator) -> String {
        let first: String = translate.translate(
            "Stanice z posledních %s QSO, které by na jiném pásmu byly novým násobičem. ", [.int(recentLimit)])
        let second: String = translate.translate(
            "QSY? = požádat o přesun (CW: PSE QSY s mou CQ / poslední frekvencí na pásmu), → = přeladit.")
        return first + second
    }

    /// The window's rows: the latest QSOs first, not deleted and not X-QSOs, at most `recentLimit` of them, only those
    /// with at least one candidate band.
    public static func rows(qsos: [Qso], candidates: (Qso) -> [MoveMultipliers.Candidate])
        -> [(qso: Qso, candidates: [MoveMultipliers.Candidate])] {
        var out: [(qso: Qso, candidates: [MoveMultipliers.Candidate])] = []
        var taken = 0
        for qso in qsos.reversed() where !qso.deleted && !qso.xqso {
            if taken >= recentLimit { break }
            taken += 1
            let found: [MoveMultipliers.Candidate] = candidates(qso)
            if !found.isEmpty {
                out.append((qso, found))
            }
        }
        return out
    }

    /// The row's band and mode column (`20m CW`, either part empty when unknown).
    public static func bandModeText(_ qso: Qso) -> String {
        "\(qso.band?.adif ?? "") \(qso.mode?.rawValue ?? "")"
    }

    /// The candidate button label (`15m +2 QSY?`).
    public static func buttonLabel(_ candidate: MoveMultipliers.Candidate) -> String {
        "\(candidate.band) +\(candidate.newMults.count) QSY?"
    }
}

extension ContestRuntime {

    /// Bands where the station of `qso` would be a new multiplier (Move Multipliers); empty outside a contest and when
    /// the evaluation fails (Kotlin `runCatching { … }.getOrDefault(emptyList())`).
    public func moveCandidates(_ qso: Qso, at: Date = Date()) -> [MoveMultipliers.Candidate] {
        guard let session = activeSession else { return [] }
        let bands: [String?] = session.definition.bands ?? []
        return (try? MoveMultipliers.candidates(session, qso, bands: bands, at: at)) ?? []
    }
}
