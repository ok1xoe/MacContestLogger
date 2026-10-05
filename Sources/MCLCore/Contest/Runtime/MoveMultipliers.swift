import Foundation

/// Move Multipliers (N1MM „Move Multipliers", DXLog „QSY wizard"): on which other
/// bands of the contest the worked station would be a **new multiplier** — where to ask it
/// to move. Evaluated by a session preview (nothing is written).
///
/// Port of Java `contest/runtime/MoveMultipliers.java`.
public enum MoveMultipliers {

    /// Band to move the station to: new multipliers (binding ids in definition order)
    /// and points for the QSO (Java `int`).
    public struct Candidate: Equatable, Sendable {
        public let band: String
        public let newMults: [String?]
        public let points: Int32
    }

    /// - Parameters:
    ///   - bands: contest bands in the order they should be offered (the QSO's band is skipped,
    ///     comparison by UTF-16 like Java `equals`; a band outside the definition is not filtered).
    ///     A `nil` list or `nil` element: Java NPE, Swift skips them (a deliberate divergence from Java v1.1.1).
    ///   - at: preview time for the dupe (TOUR); default "now" like Java `Instant.now()`.
    /// - Returns: bands where the QSO would not be a dupe and would bring at least one new multiplier.
    /// - Throws: an exchange error (number above 2³¹−1), expression or set error — as in Java.
    public static func candidates(_ session: ContestSession, _ qso: Qso, bands: [String?]?,
                                  at: Date = Date()) throws(ContestSessionError) -> [Candidate] {
        // Java `getCall() == null` does not occur in Swift (the callsign is `""`);
        // an empty callsign goes into the preview as Java "".
        guard let qsoBand = qso.band?.adif else { return [] }
        let mode = qso.mode?.rawValue ?? ""
        let exch: JavaLinkedMap<String>
        do {
            exch = try session.receivedFromFlat(call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd,
                                                serialRcvd: qso.serialRcvd)
        } catch {
            throw .expression(error)
        }
        let ownQth = session.ownQthFromSent(qso.exchangeSent)
        var out: [Candidate] = []
        for case let band? in bands ?? [] {
            if JavaText.equals(band, qsoBand) {
                continue
            }
            let r = try session.preview(call: qso.call, band: band, mode: mode, receivedRaw: exch, ownQth: ownQth,
                                        at: at)
            if r.dupe {
                continue
            }
            let mults = r.multipliers.filter { $0.isNew && $0.countsAsMultiplier }.map(\.bindingId)
            if !mults.isEmpty {
                out.append(Candidate(band: band, newMults: mults, points: r.points))
            }
        }
        return out
    }
}
