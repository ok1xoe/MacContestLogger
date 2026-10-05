import Foundation

/// Score recomputation (N1MM „Rescore Current Contest"): replays the saved QSOs into a fresh
/// `ContestSession` in time order. The order decides — the dupe and the new multiplier go to the
/// first QSO, so they must not be replayed in DB write order.
///
/// A pure function without UI: the session can be built and replayed off the main thread
/// (`Task.detached`) and only the finished `Outcome` (it is `Sendable`) taken over as the live
/// session — analogous to Java `ContestController.replayed` + `adopt`.
///
/// The `replayed`/`skipped` counts and the session state after a faulty QSO are **exactly as in Java**
/// (a QSO that throws is `skipped`, but what the session wrote before the error —
/// a multiplier, an earlier bonus — stays). In addition versus Java (which swallows the exception) it returns
/// the reason for every skip, so the UI can show e.g. „Příliš hluboké zanoření ve
/// výrazu" instead of a silent zero score.
///
/// Where an expression error shows: the expression in `scoring.total` is not computed by the replay, so its error
/// (also „Příliš hluboké zanoření") comes only from `score()`; an error in a points rule, bonus or
/// condition throws on every QSO the rule reaches — `skips` then carries it many times
/// and the UI should show `firstError`.
public enum ContestReplay {

    /// One skipped QSO and why.
    public struct Skip: Sendable {
        public enum Reason: Equatable, Sendable {
            /// A QSO without a band (Java `getBand() == null`).
            case missingBand
            /// An empty callsign (Java `call == null || call.isBlank()`).
            case missingCall
            /// `replayLogged` threw (a Java `RuntimeException`).
            case error(ContestSessionError)
        }

        public let qso: Qso
        public let reason: Reason
    }

    /// - `session`: the supplied session after the replay (with a half-done state after errors)
    /// - `replayed`: how many QSOs were replayed (in the Java sense also the uncounted ones — FT8 in a CW contest)
    /// - `skipped`: how many QSOs could not be replayed (missing band/callsign, invalid data)
    /// - `skips`: reasons for skipping in replay order (`skips.count == skipped`)
    public struct Outcome: Sendable {
        public let session: ContestSession
        public let replayed: Int
        public let skipped: Int
        public let skips: [Skip]

        /// Errors from `replayLogged` in replay order (without QSOs without a band / callsign).
        public var errors: [ContestSessionError] {
            skips.compactMap {
                if case .error(let error) = $0.reason { return error }
                return nil
            }
        }

        /// The first replay error (for a UI message), `nil` = none.
        public var firstError: ContestSessionError? {
            errors.first
        }
    }

    /// Replays the QSOs (omits tombstones and X-QSOs) into the supplied fresh session.
    ///
    /// `now` is the source of "now" for QSOs **without a time** (Java `at == null ? Instant.now()`
    /// in `replayLogged`, read again for every such QSO). Default = the system clock
    /// like Java; a test passes a fixed time — with a TOUR session the result (dupe) otherwise depends on
    /// which session the real "now" falls into.
    public static func replay(_ fresh: ContestSession, _ qsos: [Qso],
                              now: () -> Date = Date.init) -> Outcome {
        replay(fresh, qsos, now: now) { _, _ in }
    }

    /// Replay with a listener of the result of every replayed QSO (score breakdown by band
    /// and mode). Skipped QSOs are not seen by the listener. `now` see `replay(_:_:now:)`.
    public static func replay(_ fresh: ContestSession, _ qsos: [Qso], now: () -> Date = Date.init,
                              listener: (Qso, ContestSession.LogResult) -> Void) -> Outcome {
        var replayed = 0
        var skips: [Skip] = []
        for q in ordered(qsos) {
            guard let band = q.band else {
                skips.append(Skip(qso: q, reason: .missingBand))
                continue
            }
            // Qso.call is always trimmed by Java trim(); Java `null` is "" here.
            if JavaText.isBlank(q.call) {
                skips.append(Skip(qso: q, reason: .missingCall))
                continue
            }
            do {
                // `exchangeRcvd`/`exchangeSent` "" behaves like Java `null` (both → no tokens).
                let result = try fresh.replayLogged(call: q.call, band: band.adif, mode: q.mode?.rawValue ?? "",
                                                    exchangeRcvdFlat: q.exchangeRcvd, serialRcvd: q.serialRcvd,
                                                    at: q.timestampUtc ?? now(), ownQth: fresh.ownQthFromSent(q.exchangeSent))
                listener(q, result)
                replayed += 1
            } catch {
                skips.append(Skip(qso: q, reason: .error(error)))
            }
        }
        return Outcome(session: fresh, replayed: replayed, skipped: skips.count, skips: skips)
    }

    /// Java `filter(!deleted).filter(!xqso).sorted(comparing(timestampUtc, nullsLast(natural)))`:
    /// the sort is stable (equal time keeps input order), `nil` time at the end.
    static func ordered(_ qsos: [Qso]) -> [Qso] {
        let kept = qsos.enumerated().filter { !$0.element.deleted && !$0.element.xqso }
        return kept.sorted { lhs, rhs in
            switch (lhs.element.timestampUtc, rhs.element.timestampUtc) {
            case let (l?, r?):
                return l == r ? lhs.offset < rhs.offset : l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
