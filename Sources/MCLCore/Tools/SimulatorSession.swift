import Foundation

/// The pileup simulator session (Kotlin `AppState` simulator part, `AS:1646-1712`, `AS:2790-2795`, and
/// `SimulatorWindow.kt`): the simulator, the check list and the counters. No sound and no clock — the caller plays
/// the replies and keeps the timing.
///
/// Safety gate: while `isRunning` nothing may key the real rig and the simulated QSOs must not be published
/// outward (cluster sync, Club Log, score reporting, broadcast, plugins). The app asks `allowsRigKeying` and
/// `allowsOutwardEffects` instead of tracking its own flag.
public final class SimulatorSession {

    /// One reply of a calling station with the amplitude it is played at (`0.1 + random × 0.4`).
    public struct Reply: Equatable, Sendable {
        public let transmission: PileupSimulator.Transmission
        public let amplitude: Double
    }

    private let simulator: PileupSimulator
    private let random: any PileupRandom
    /// Newest first.
    public private(set) var checks: [PileupSimulator.Check] = []
    public private(set) var qsos: Int = 0
    public private(set) var errors: Int = 0
    /// `true` from creation until `stop()`.
    public private(set) var isRunning: Bool = true

    /// Starts a session. `scp` is the callsign pool (an empty database makes up callsigns); the random source is shared
    /// by the simulator, the callsign source and the reply amplitudes, as the Kotlin `simRandom`.
    public init(settings: PileupSimulator.Settings, scp: ScpDatabase, random: any PileupRandom) {
        self.random = random
        self.simulator = PileupSimulator(settings: settings,
                                         callSource: PileupSimulator.callSource(scp: scp, random: random),
                                         random: random)
    }

    /// The station being worked (`nil` between QSOs).
    public var current: PileupSimulator.Caller? { simulator.current }

    /// The callers waiting for the operator.
    public var callers: [PileupSimulator.Caller] { simulator.callers }

    /// Rig keying is allowed only while no simulation runs.
    public var allowsRigKeying: Bool { !isRunning }

    /// Publishing QSOs outward (sync, Club Log, score, broadcast, plugins) is allowed only while no simulation runs.
    public var allowsOutwardEffects: Bool { !isRunning }

    /// Ends the session; later calls do nothing.
    public func stop() {
        isRunning = false
    }

    /// The operator sent `text` (what the keyer would have sent): the stations' replies. Kotlin ignores an
    /// `IllegalArgumentException` for an absurd tone spread (`try?`), the replies are then none.
    public func onSent(_ text: String) -> [Reply] {
        guard isRunning else { return [] }
        guard let transmissions = try? simulator.onSent(text) else { return [] }
        return transmissions.map { transmission in
            Reply(transmission: transmission, amplitude: 0.1 + random.nextDouble() * 0.4)
        }
    }

    /// A QSO was logged (not an import — the caller checks): compares it with the worked station, updates the list and
    /// the counters. `exchange` is the received exchange and the serial number joined by a space.
    @discardableResult
    public func onLogged(call: String, exchangeRcvd: String, serialRcvd: Int?) -> PileupSimulator.Check? {
        guard isRunning else { return nil }
        let check: PileupSimulator.Check = simulator.onLogged(call: call,
                                                              exchange: Self.exchange(exchangeRcvd, serialRcvd))
        checks.insert(check, at: 0)
        qsos = Int(simulator.qsos)
        errors = Int(simulator.errors)
        return check
    }

    /// Kotlin `listOfNotNull(exchangeRcvd, serialRcvd?.toString()).joinToString(" ")`.
    public static func exchange(_ exchangeRcvd: String, _ serialRcvd: Int?) -> String {
        guard let serialRcvd else { return exchangeRcvd }
        return exchangeRcvd + " " + String(serialRcvd)
    }

    // MARK: - texts and form parsing

    /// Status after starting; without a callsign database a note that the callsigns are made up.
    public static func startText(scpSize: Int, translate: Translator) -> String {
        let head: String = translate.translate("Simulátor běží — zavolej CQ (F1)")
        return head + (scpSize == 0 ? "; bez master.scp jsou volačky smyšlené" : "")
    }

    /// Status when the sound output cannot be opened.
    public static func audioFailureText(message: String?, translate: Translator) -> String {
        translate.translate("Simulátor: zvukový výstup nejde otevřít (%s)", [.string(message)])
    }

    /// `Aktivita (volajících na CQ): n`.
    public static func activityText(_ activity: Int, translate: Translator) -> String {
        translate.translate("Aktivita (volajících na CQ): %s", [.int(activity)])
    }

    /// `Šum: n %` (percent truncated, not translated).
    public static func noiseText(_ level: Float) -> String {
        let percent: Float = level * 100
        return "Šum: \(Int(JavaMath.d2i(Double(percent)))) %"
    }

    /// `QSO: n   chyby: n`.
    public static func counterText(qsos: Int, errors: Int) -> String {
        "QSO: \(qsos)   chyby: \(errors)"
    }

    /// The two-sentence note under the controls.
    public static func hint(translate: Translator) -> String {
        let first: String = translate.translate(
            "Během simulace jde CW z F-kláves místo klíče do simulátoru. QSO se zapisují do aktivního ")
        let second: String = translate.translate(
            "závodu — na trénink si založ zkušební závod. Volající posílají „5NN číslo“.")
        return first + second
    }

    /// A row of the check list: mark, the logged call padded to 12, the detail; `ok` selects the colour.
    public static func checkText(_ check: PileupSimulator.Check, translate: Translator) -> String {
        let mark: String = check.ok ? "✓" : "✗"
        let detail: String
        if check.ok {
            detail = "OK"
        } else if check.expectedCall.isEmpty {
            detail = "nikdo s tebou nepracoval"
        } else {
            var parts: [String] = []
            if !check.callOk {
                parts.append(translate.translate("volačka: %s", [.string(check.expectedCall)]))
            }
            if !check.exchangeOk {
                parts.append(translate.translate("výměna: %s", [.string(check.expectedExchange)]))
            }
            detail = parts.joined(separator: ", ")
        }
        return "\(mark) \(ToolsFormat.padEnd(check.loggedCall, 12)) \(detail)"
    }

    /// Kotlin `filter(Char::isDigit).take(n)` of a numeric field.
    public static func digits(_ text: String, limit: Int) -> String {
        let kept: [UInt16] = text.utf16.filter { JavaChar.isDigit($0) }
        return JavaChar.string(Array(kept.prefix(limit)))
    }

    /// Kotlin `String.toIntOrNull()` (optional sign, `Character.digit` digits, `Int` range).
    public static func toIntOrNull(_ text: String) -> Int? {
        let units: [UInt16] = Array(text.utf16)
        guard let first = units.first else { return nil }
        var negative = false
        var start = 0
        if first < 0x30 {
            if units.count == 1 { return nil }
            start = 1
            if first == 0x2D {
                negative = true
            } else if first != 0x2B {
                return nil
            }
        }
        var value: Int64 = 0
        for unit in units[start...] {
            guard let digit = JavaChar.digit(unit) else { return nil }
            value = value * 10 + Int64(digit)
            if value > 2_147_483_648 { return nil }
        }
        if negative { value = -value }
        return value >= Int64(Int32.min) && value <= Int64(Int32.max) ? Int(value) : nil
    }

    /// Settings from the form fields (WPM range and tone spread are the already digit-filtered texts): defaults 22 WPM
    /// and 300 Hz, the maximum defaults to the minimum.
    public static func settings(activity: Int, minWpm: String, maxWpm: String, spread: String)
        -> PileupSimulator.Settings {
        let low: Int = toIntOrNull(minWpm) ?? 22
        let high: Int = toIntOrNull(maxWpm) ?? low
        let hz: Int = toIntOrNull(spread) ?? 300
        return PileupSimulator.Settings(activity: Int32(truncatingIfNeeded: activity),
                                        minWpm: Int32(truncatingIfNeeded: low),
                                        maxWpm: Int32(truncatingIfNeeded: high),
                                        pitchSpreadHz: Int32(truncatingIfNeeded: hz))
    }
}
