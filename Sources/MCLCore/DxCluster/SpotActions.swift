import Foundation

/// The spot actions of the entry window and the DX cluster of v1.1.1 as pure functions: the commands sent to the
/// cluster, the spots put into the buffer and the status texts (`ui/AppState.kt`: `jumpToNextSpot`/`removeSpotOf`/
/// `markFrequency`/`promptSpotWithComment` `:840-905`, `selfSpot` `:1015-1027`, `loadBeacons` `:2117-2128`,
/// `spotToCluster`/`spotMe` `:3944-3976`, the self-spot message `:385-395`; `ui/EntryPanel.kt`: `storeCall`/`spotIt`
/// `:770-812`). Keys are the Czech originals; texts without `tr` in Kotlin are `verbatim`.
///
/// Kotlin quirks kept: sending needs the **main** cluster connection even when parallel ones are connected; the
/// navigation skips dupes except for "own spots" (that predicate is only `selfSpotted`); Alt+D with an empty call takes
/// the nearest spot within 200 Hz (and the buffer removes every spot of that call).
public enum SpotActions {

    // MARK: - spot to the cluster (`spotToCluster`, SPOTME, Spot It, Ctrl+P)

    public static let notConnected = "Spot: DX cluster není připojený (okno DX Cluster)"
    public static let missingCallOrFrequency = "Spot: chybí volačka nebo frekvence"
    public static let sentKey = "Spot odeslán: %s"
    /// Appended after `sent` when SPOTME succeeded.
    public static let spotMeSuffix = " (self-spot — ověř, že ho propozice závodu povolují)"
    /// SPOTME's comment when none was given.
    public static let spotMeDefaultComment = "CQ"
    /// Spot It with neither a call nor a logged QSO.
    public static let spotItNothing = "Spot: není co spotovat"
    /// Ctrl+P without a call.
    public static let commentNoCall = "Ctrl+P: zadej volačku ke spotu"
    /// Ctrl+P prompt hint.
    public static let commentHint = "Komentář ke spotu"

    /// `spotToCluster`: the cluster command `DX <kHz %.1f, US> <CALL> <comment>` trimmed (Kotlin `trim()`), or the
    /// error status. `connected` is the **main** connection's state.
    public static func clusterCommand(call: String, freqHz: Int64, comment: String,
                                      connected: Bool) -> Outcome<String> {
        if !connected {
            return .rejected(.tr(notConnected))
        }
        if KotlinText.isBlank(call) || freqHz <= 0 {
            return .rejected(.tr(missingCallOrFrequency))
        }
        let khz = Double(freqHz) / 1000
        let upper: String = JavaText.toUpperCase(KotlinText.trim(call))
        let command: String = JavaFormat.format("DX %.1f %s %s", .double(khz), .string(upper),
                                                .string(KotlinText.trim(comment)))
        return .accepted(KotlinText.trim(command))
    }

    /// A value, or the status text that replaces it (Kotlin sets `statusMessage` and returns).
    public enum Outcome<Value: Equatable & Sendable>: Equatable, Sendable {
        case accepted(Value)
        case rejected(EntryStatus)
    }

    /// `tr("Spot odeslán: %s", cmd)`.
    public static func sent(_ command: String) -> EntryStatus {
        .tr(sentKey, .string(command))
    }

    /// `spotMe`: the comment `ifBlank { "CQ" }`.
    public static func spotMeComment(_ comment: String) -> String {
        KotlinText.isBlank(comment) ? spotMeDefaultComment : comment
    }

    /// The SPOTME status after a successful send: `sent` + `tr(" (self-spot — …)")`.
    public static func spotMeSent(_ command: String) -> EntryStatus {
        sent(command).appending(.tr(spotMeSuffix))
    }

    /// Spot It (Alt+P, `EP:806-812`): the call from the field (Kotlin `trim()`) at the field frequency when it is not
    /// blank and not a text command; otherwise the last logged QSO (`call ?: ""`); with neither `spotItNothing`.
    public static func spotItTarget(call: String, isCommand: Bool, fieldFreqHz: Int64,
                                    lastQso: (call: String?, freqHz: Int64)?) -> Outcome<DxTarget> {
        if !KotlinText.isBlank(call) && !isCommand {
            return .accepted(DxTarget(call: KotlinText.trim(call), freqHz: fieldFreqHz))
        }
        guard let lastQso else { return .rejected(.tr(spotItNothing)) }
        return .accepted(DxTarget(call: lastQso.call ?? "", freqHz: lastQso.freqHz))
    }

    /// What to spot: a call and a frequency.
    public struct DxTarget: Equatable, Sendable {
        public let call: String
        public let freqHz: Int64

        public init(call: String, freqHz: Int64) {
            self.call = call
            self.freqHz = freqHz
        }
    }

    /// Ctrl+P: the prompt title `"Spot $call"` (not translated, the call as typed); `nil` = blank call
    /// (`commentNoCall`).
    public static func commentTitle(call: String) -> String? {
        KotlinText.isBlank(call) ? nil : "Spot " + call
    }

    // MARK: - Mark (Alt+M)

    public static let markSpotter = "MARK"
    public static let markComment = "obsazeno"
    public static let markStatusKey = "Frekvence %.1f kHz označena v bandmapě"

    /// `markFrequency`: the spot `DxSpot("MARK", f, "*%.1f" (US), "obsazeno", true)`; `nil` for `f <= 0`.
    public static func markSpot(freqHz: Int64) -> DxSpot? {
        if freqHz <= 0 { return nil }
        let call: String = JavaFormat.format("*%.1f", .double(Double(freqHz) / 1000))
        return DxSpot(spotter: markSpotter, freqHz: Int(truncatingIfNeeded: freqHz), dxCall: call,
                      comment: markComment, selfSpotted: true)
    }

    /// `String.format(Locale.US, tr("Frekvence %.1f kHz označena v bandmapě"), kHz)`: translated first, then formatted
    /// with a decimal **point** in every language — so the text is built here, not where it is shown.
    public static func markStatus(freqHz: Int64, translator: Translator) -> EntryStatus {
        let khz = Double(freqHz) / 1000
        let text: String = translator.translate(markStatusKey, [.double(khz)], decimalSeparator: ".")
        return .verbatim(text)
    }

    // MARK: - remove (Alt+D / Alt+Shift+D)

    /// The tolerance of the nearest spot when the call field is empty.
    public static let removeToleranceHz = 200
    public static let removeNoSpot = "Alt+D: na frekvenci ani v poli volačky není spot"

    /// `removeSpotOf` target: Kotlin `call.trim().uppercase()`, when blank the call of the nearest spot within 200 Hz
    /// (as the buffer holds it); `nil` = nothing to remove (`removeNoSpot`). `nearest` is `SpotBuffer.nearestWithin`.
    public static func removeTarget(call: String, tunedFreqHz: Int64,
                                    nearest: (_ freqHz: Int, _ toleranceHz: Int) -> DxSpot?) -> String? {
        var target: String = CallbookPolicy.key(call)
        if KotlinText.isBlank(target) {
            target = nearest(Int(truncatingIfNeeded: tunedFreqHz), removeToleranceHz)?.dxCall ?? ""
        }
        return KotlinText.isBlank(target) ? nil : target
    }

    /// The status after the removal.
    public static func removed(_ target: String, blacklist: Bool) -> EntryStatus {
        blacklist ? .tr("Spot %s odstraněn a dán na blacklist", .string(target)) : .tr("Spot %s odstraněn", .string(target))
    }

    // MARK: - navigation (Ctrl/Alt+↑↓)

    /// The `SpotNavigator` predicate of `jumpToNextSpot`: own spots = `selfSpotted` (dupes included), multipliers =
    /// `newMult && !dupe`, otherwise `!dupe`.
    public static func navigable(selfSpotted: Bool, dupe: Bool, newMult: Bool, onlyMult: Bool, onlySelf: Bool) -> Bool {
        if onlySelf { return selfSpotted }
        if onlyMult { return newMult && !dupe }
        return !dupe
    }

    /// The six whole sentences when no spot was found (`direction > 0` = up); `onlyMult` wins over `onlySelf`.
    public static func noSpotText(direction: Int, onlyMult: Bool, onlySelf: Bool) -> String {
        let up: Bool = direction > 0
        if onlyMult { return up ? "Žádný násobič výš na pásmu" : "Žádný násobič níž na pásmu" }
        if onlySelf { return up ? "Žádný vlastní spot výš na pásmu" : "Žádný vlastní spot níž na pásmu" }
        return up ? "Žádný spot výš na pásmu" : "Žádný spot níž na pásmu"
    }

    // MARK: - self-spot messages (`wireSelfSpot.onSelfSpot`)

    public static let rbnMessageKey = "RBN: %s tě slyší na %s kHz"

    /// The message for the messages window: RBN translated + `", <snr> dB"` + `", <wpm> WPM"`, a human spot literally
    /// `"Byl jsi spotnut: <spotter> na <f> kHz"`. The frequency is `"%.1f".format(…)` in the default locale
    /// (`decimalSeparator`, `cs_CZ` `","`).
    public static func selfSpotMessage(_ spot: SelfSpot, translator: Translator, decimalSeparator: String) -> String {
        let point: String = JavaFormat.fixed(Double(spot.freqHz) / 1000, precision: 1)
        let freq: String = point.replacingOccurrences(of: ".", with: decimalSeparator)
        guard spot.rbn else {
            return "Byl jsi spotnut: " + spot.spotter + " na " + freq + " kHz"
        }
        let head: String = translator.translate(rbnMessageKey, [.string(spot.spotter), .string(freq)],
                                                decimalSeparator: decimalSeparator)
        let snr: String = spot.snrDb.map { ", " + String($0) + " dB" } ?? ""
        let wpm: String = spot.wpm.map { ", " + String($0) + " WPM" } ?? ""
        return head + snr + wpm
    }

    // MARK: - Store (Alt+O) and the self-spot of the tracker (`selfSpot`)

    public static let storeNoCall = "Store: zadej volačku"
    public static let storeComment = "self"

    /// `selfSpot(call, f)`: `DxSpot(myCall, f, CALL, "self", true)` with Kotlin `trim().uppercase()`; `nil` for a blank
    /// call. The buffer keys by call, so an existing spot of it is replaced.
    public static func storeSpot(myCall: String, call: String, freqHz: Int64) -> DxSpot? {
        let upper: String = CallbookPolicy.key(call)
        if KotlinText.isBlank(upper) { return nil }
        return DxSpot(spotter: myCall, freqHz: Int(truncatingIfNeeded: freqHz), dxCall: upper, comment: storeComment,
                      selfSpotted: true)
    }

    /// Store's status: `tr("%s uloženo do bandmapy", call.trim())`.
    public static func stored(call: String) -> EntryStatus {
        .tr("%s uloženo do bandmapy", .string(KotlinText.trim(call)))
    }

    // MARK: - beacons (BEACONS / LOADBEACONS)

    /// The file could not be read: `tr("BEACONS: nelze číst %s", path.fileName)` (`nil` file name prints `null`).
    public static func beaconsUnreadable(fileName: String?) -> EntryStatus {
        .tr("BEACONS: nelze číst %s", .string(fileName))
    }

    /// The beacons stay in the buffer until `now + hours` (`Instant.now().plus(Duration.ofHours(hours))`).
    public static func beaconsUntil(now: Date, hours: Int) -> Date {
        now.addingTimeInterval(Double(hours) * 3_600)
    }

    /// After loading: the count and hours, plus `" · "` and the skipped line count when some lines were skipped.
    public static func beaconsLoaded(_ beacons: BeaconFile.Beacons) -> EntryStatus {
        let head = EntryStatus.tr("BEACONS: %s majáků v bandmapě na %s h", .int(beacons.beacons.count),
                                  .int(beacons.hours))
        if beacons.skipped.isEmpty { return head }
        return head.appending(.verbatim(" · ")).appending(.tr("%s řádků nešlo přečíst", .int(beacons.skipped.count)))
    }
}
