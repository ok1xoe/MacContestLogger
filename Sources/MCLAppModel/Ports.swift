import Foundation
import MCLCore

/// What a keyer needs to know about the configuration when a message is handed over.
public struct KeyerSettings: Equatable, Sendable {
    /// `config.cwKeyer.method`.
    public var cwMethod: CwKeyerConfig.Method
    /// `config.cwKeyer.winkeyerPort`.
    public var winkeyerPort: String
    /// Texts of the voice messages of the set the press uses (Run/S&P, Shift = opposite).
    public var voiceTexts: [String]

    public init(cwMethod: CwKeyerConfig.Method, winkeyerPort: String, voiceTexts: [String]) {
        self.cwMethod = cwMethod
        self.winkeyerPort = winkeyerPort
        self.voiceTexts = voiceTexts
    }
}

/// The CW / voice / digital keyer behind the F-keys. The entry window decides everything (which set,
/// macros, ESM progress, macro actions); the port only transmits. Called on the main actor; the real keyer
/// (`LiveKeyer`) does its blocking work on its own threads.
public protocol KeyerPort: Sendable {
    /// The keyer can key the entry window's mode now (Kotlin `phone || cw || digi`).
    @MainActor var canSend: Bool { get }
    /// Esc would stop something: tuning, a recording, a voice message, fldigi or a lit CW key.
    @MainActor var isSending: Bool { get }
    /// The carrier is on (Ctrl+T): Esc only switches it off and leaves the CQ repeat alone (`AS:1758-1761`).
    @MainActor var isTuning: Bool { get }
    /// Transmits a message; the result is the status Kotlin shows at once (`nil` = none; the keyer's own errors
    /// follow asynchronously, as Kotlin's do).
    @MainActor func send(_ transmission: FunctionKeyTransmission, settings: KeyerSettings) -> EntryStatus?
    /// Esc: stops tuning, or the first of voice, fldigi and CW (without the CQ repeat — the entry window clears
    /// it); `true` = something was stopped.
    @MainActor func stopSending() -> Bool
    /// Ctrl+Shift+F in phone: start or stop recording the message of the key.
    @MainActor func toggleRecording(_ key: Int) -> EntryStatus?
    /// Ctrl+T (TUNE): the carrier on or off; the result is a status to show (`nil` = the keyer shows its own).
    @MainActor func toggleTune() -> EntryStatus?
    /// PgUp/PgDn in CW: the CW speed by `deltaWpm`; the result is a status to show (`nil` = none).
    @MainActor func changeCwSpeed(by deltaWpm: Int) -> EntryStatus?
}

extension KeyerPort {
    public var isTuning: Bool {
        false
    }

    public func toggleTune() -> EntryStatus? {
        .tr(EntryTexts.unavailable)
    }

    public func changeCwSpeed(by deltaWpm: Int) -> EntryStatus? {
        .tr(EntryTexts.unavailable)
    }
}

/// The rig half of the entry window's actions: the local part (field, mode, status) is done by the
/// entry model, the rig gets the rest. The app passes `LiveRig` over its `RigModel`; tests may pass a recorder.
public protocol RigPort: Sendable {
    /// `state.qsy(hz)`: the shared tuned and previous frequency for any value; the rig is tuned only for a
    /// frequency > 0 (L11).
    @MainActor func qsy(hz: Int64)
    /// `cat.setMode(mode, freqHz)`.
    @MainActor func setMode(_ mode: Mode, freqHz: Int64)
    /// `{CLEARRIT}`: `setRit(0)`; the result is a status to show at once (`nil` = the rig reports later).
    @MainActor func clearRit() -> EntryStatus?
    /// `{NOSPLIT}`: `splitOff()`; the result is a status to show at once (`nil` = the rig reports later).
    @MainActor func splitOff() -> EntryStatus?
}

/// The keyer by default: nothing is connected (tests and the inert stand-in until `bootstrap` puts `LiveKeyer` in
/// its place). It answers as Kotlin does without a keyer:
/// - CW: `sendCw` fails in the keyer — method NONE `"CW: " + tr("CW klíč je vypnutý (Nastavení → CW klíč)")`,
///   CAT without a rig `"CW: CW přes CAT: TRX není připojený"` (Java `CatCwKeyer`, not translated), Winkeyer without
///   a port `"CW: " + tr("Winkeyer: vyber port v Nastavení → CW klíč")`; a Winkeyer port is not opened;
/// - voice: an empty message `tr("%s: zpráva je prázdná (Nastavení → Function Keys)")`; no files are played;
/// - digital (fldigi configured): nothing is sent.
public struct NoKeyer: KeyerPort {

    public init() {}

    public var canSend: Bool {
        false
    }

    public var isSending: Bool {
        false
    }

    public func send(_ transmission: FunctionKeyTransmission, settings: KeyerSettings) -> EntryStatus? {
        switch transmission {
        case .cw:
            switch settings.cwMethod {
            case .none:
                return EntryStatus.verbatim("CW: ").appending(.tr("CW klíč je vypnutý (Nastavení → CW klíč)"))
            case .cat:
                return .verbatim("CW: CW přes CAT: TRX není připojený")
            case .winkeyer:
                if KotlinStrings.isBlank(settings.winkeyerPort) {
                    return EntryStatus.verbatim("CW: ").appending(.tr("Winkeyer: vyber port v Nastavení → CW klíč"))
                }
                return EntryStatus.verbatim("CW: ").appending(.tr(EntryTexts.unavailable))
            }
        case .voice(let indices, _, _, _):
            let texts: [String] = indices.compactMap { index in
                guard index >= 0, index < settings.voiceTexts.count else { return nil }
                let text: String = settings.voiceTexts[index]
                return KotlinStrings.isBlank(text) ? nil : text
            }
            if texts.isEmpty {
                return .tr("%s: zpráva je prázdná (Nastavení → Function Keys)",
                           .string(FunctionKeyRouter.keysLabel(indices)))
            }
            return .tr(EntryTexts.unavailable)
        case .digital:
            return .tr(EntryTexts.unavailable)
        }
    }

    public func stopSending() -> Bool {
        false
    }

    public func toggleRecording(_ key: Int) -> EntryStatus? {
        .tr(EntryTexts.unavailable)
    }
}

/// No rig: the rig half is dropped; RIT and split answer with Kotlin's texts without CAT. In
/// `AppModel.Environment.ports` it stands for "the app's own rig model" (`bootstrap` puts `LiveRig` in its place).
public struct NoRig: RigPort {

    public init() {}

    public func qsy(hz: Int64) {}

    public func setMode(_ mode: Mode, freqHz: Int64) {}

    public func clearRit() -> EntryStatus? {
        .tr("RIT: připoj TRX (CAT)")
    }

    public func splitOff() -> EntryStatus? {
        .tr("%s: připoj TRX (CAT) — bez něj druhé VFO ani split nejdou", .string("Split"))
    }
}

/// The outside world of the entry window: the keyer, the rig and the dupe beep (Kotlin `Toolkit.beep()`), injected
/// through `AppModel.Environment` (tests pass fakes; `NoKeyer`/`NoRig` stand for the app's own keyer and rig, which
/// `bootstrap` puts in their place — `LiveKeyer`, `LiveRig`).
public struct EntryPorts: Sendable {
    public var keyer: any KeyerPort
    public var rig: any RigPort
    public var beep: @MainActor @Sendable () -> Void

    public init(keyer: any KeyerPort = NoKeyer(), rig: any RigPort = NoRig(),
                beep: @escaping @MainActor @Sendable () -> Void = {}) {
        self.keyer = keyer
        self.rig = rig
        self.beep = beep
    }
}
