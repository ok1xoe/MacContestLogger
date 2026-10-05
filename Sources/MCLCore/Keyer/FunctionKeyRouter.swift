import Foundation

/// The F1–F12 messages of one keyer: the Run set and the S&P set (N1MM).
public struct FunctionKeySet: Equatable, Sendable {
    public var run: [FunctionKeyMessage]
    public var sp: [FunctionKeyMessage]

    public init(run: [FunctionKeyMessage], sp: [FunctionKeyMessage]) {
        self.run = run
        self.sp = sp
    }

    /// Kotlin `useRunSet(opposite) = (runMode == RUN) != opposite` (`AS:1323`): Shift picks the other set.
    public func messages(run isRun: Bool, opposite: Bool) -> [FunctionKeyMessage] {
        (isRun != opposite) ? run : sp
    }
}

/// What the F-keys need from the window and the configuration.
public struct FunctionKeyContext: Sendable {
    public var mode: Mode
    /// A digital modem is configured (`config.digital.engine != NONE`).
    public var digitalReady: Bool
    public var postContest: Bool
    public var run: Bool
    public var call: String
    public var rstSent: String
    /// `parseFreqHz(freqKHz)` at the press.
    public var freqHz: Int64
    public var progress: EsmProgress
    /// `config.station.call` for `{MYCALL}` in the labels.
    public var stationCall: String
    public var voice: FunctionKeySet
    public var cw: FunctionKeySet
    public var digital: FunctionKeySet
    /// `cwContext` without the per-press values: station, last logged call, serial, `{EXCH}`, cut/leading-zero
    /// options **as configured**, rover QTH, county line, cut style, the moment. `hisCall`, `rst` and `functionKeys`
    /// are set by the router; for digital modes cut numbers and leading zeros are off (`AS:1526-1529`).
    public var cwBase: CwMessageBuilder.Context

    public init(mode: Mode, digitalReady: Bool, postContest: Bool, run: Bool, call: String, rstSent: String,
                freqHz: Int64, progress: EsmProgress, stationCall: String, voice: FunctionKeySet, cw: FunctionKeySet,
                digital: FunctionKeySet, cwBase: CwMessageBuilder.Context) {
        self.mode = mode
        self.digitalReady = digitalReady
        self.postContest = postContest
        self.run = run
        self.call = call
        self.rstSent = rstSent
        self.freqHz = freqHz
        self.progress = progress
        self.stationCall = stationCall
        self.voice = voice
        self.cw = cw
        self.digital = digital
        self.cwBase = cwBase
    }

    var phone: Bool { EsmFlow.isPhone(mode) }
    var isCw: Bool { mode == .cw }
    var digi: Bool { mode.isDigital && digitalReady }
    var canTransmit: Bool { EsmFlow.canTransmit(mode: mode, digitalReady: digitalReady) }
}

/// What a press hands to the keyer (`KeyerPort`).
public enum FunctionKeyTransmission: Equatable, Sendable {
    /// `playFunctionKeys(indices, hisCall, freqHz, opposite)` — the voice keyer resolves the messages itself.
    case voice(indices: [Int], hisCall: String, freqHz: Int64, opposite: Bool)
    /// `sendCw(message, index)`; `index` = the lit key.
    case cw(CwMessage, index: Int)
    /// `sendDigitalText(text, index)` (fldigi).
    case digital(text: String, index: Int)
}

/// The result of an F-key press, applied by the app in this order: status, ESM progress and last sent keys, the
/// transmission, the macro actions (`{LOG}` logs, `{WIPE}` wipes…), `onCqSent`, the focus.
public struct FunctionKeyOutcome: Equatable, Sendable {
    /// The status set synchronously (post-contest refusal, unknown macros, a mode that sends nothing).
    public var status: EntryStatus?
    /// New ESM progress (`esm.afterSent`); `nil` = unchanged.
    public var progress: EsmProgress?
    /// New `lastSentKeys` (the `=` key); `nil` = unchanged.
    public var lastSentKeys: [Int]?
    public var transmission: FunctionKeyTransmission?
    /// Actions of the control macros, in message order (`CwMessage.Action`).
    public var actions: [CwMessage.Action] = []
    /// F1 sent: `onCqSent(freqHz)` — CQ frequency remembered, Run (N1MM "CQ key is special").
    public var cqSentFreqHz: Int64?
    /// Ctrl+Shift+F in phone: start/stop recording this key.
    public var recordKey: Int?
    /// Move the focus back to the call field.
    public var refocus: Bool = false

    public init() {}
}

/// F-keys of the entry window (`functionKeys`, `EP:719-755`; key branch `EP:953-964`; senders `AS:1315-1350,
/// 1465-1524, 1561-1578`).: the whole decision is here; sending goes to the keyer port.
public enum FunctionKeyRouter {

    /// A key press: Ctrl+Shift = record (phone only), Shift = the opposite set, otherwise the current set. Both send
    /// paths refocus the call field.
    public static func press(index: Int, shift: Bool, ctrlShift: Bool, context: FunctionKeyContext) -> FunctionKeyOutcome {
        if ctrlShift {
            var out = FunctionKeyOutcome()
            if context.phone {
                out.recordKey = index
            } else {
                out.status = .tr("Nahrávání zpráv (Ctrl+Shift+F) je jen pro fone")
            }
            return out
        }
        return send([index], opposite: shift, refocus: true, context: context)
    }

    /// Kotlin `functionKeys(indices, refocus, opposite)` — also used by ESM (`refocus = false`), the send shortcuts
    /// and `=`.
    public static func send(_ indices: [Int], opposite: Bool = false, refocus: Bool = true,
                            context: FunctionKeyContext) -> FunctionKeyOutcome {
        var out = FunctionKeyOutcome()
        if context.postContest {
            out.status = .tr("Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
            return out
        }
        guard let first = indices.first else {
            // Kotlin would fail on `indices.first()` in the non-transmitting branches; no caller passes an empty list.
            return out
        }
        if context.canTransmit {
            out.progress = context.progress.afterSent(indices, context.call)
            out.lastSentKeys = indices
        }
        if context.phone {
            out.transmission = .voice(indices: indices, hisCall: KotlinStrings.trim(context.call),
                                      freqHz: context.freqHz, opposite: opposite)
        } else if context.isCw || context.digi {
            keyed(indices, opposite: opposite, digital: context.digi, context: context, into: &out)
        } else if context.mode.isDigital {
            out.status = .tr("F%s: pro %s nastav fldigi (Nastavení → Digitální módy)", .int(first + 1),
                             .string(context.mode.rawValue))
        } else {
            out.status = .tr("F%s: v módu %s zatím nic nevysílá", .int(first + 1), .string(context.mode.rawValue))
        }
        if context.canTransmit && first == EsmEngine.f1 {
            out.cqSentFreqHz = context.freqHz
        }
        out.refocus = refocus
        return out
    }

    /// `sendCwFunctionKeys` / `sendDigitalFunctionKeys`: the non-blank texts of the keys joined by a space, built
    /// with `CwMessageBuilder`; CW reports unknown macros, an empty message is not sent; the actions always come back.
    private static func keyed(_ indices: [Int], opposite: Bool, digital: Bool, context: FunctionKeyContext,
                              into out: inout FunctionKeyOutcome) {
        let set: [FunctionKeyMessage] = (digital ? context.digital : context.cw).messages(run: context.run,
                                                                                         opposite: opposite)
        let texts: [String] = indices.compactMap { i in
            guard i >= 0, i < set.count, !KotlinStrings.isBlank(set[i].text) else { return nil }
            return set[i].text
        }
        var ctx: CwMessageBuilder.Context = context.cwBase
        ctx.hisCall = KotlinStrings.trim(context.call)
        ctx.rst = KotlinStrings.isBlank(context.rstSent) ? "599" : context.rstSent
        ctx.functionKeys = set.map(\.text)
        if digital {
            ctx.cutNumbers = false
            ctx.leadingZeros = false
        }
        let message: CwMessage = CwMessageBuilder.build(texts.joined(separator: " "), ctx)
        let index: Int = indices[indices.count - 1]
        if digital {
            if !message.isEmpty {
                out.transmission = .digital(text: message.plainText(), index: index)
            }
        } else {
            if !message.unknownMacros.isEmpty {
                out.status = .tr("%s: makra %s zatím neumím — vynechána", .string(keysLabel(indices)),
                                 .string(message.unknownMacros.joined(separator: " ")))
            }
            if !message.isEmpty {
                out.transmission = .cw(message, index: index)
            }
        }
        out.actions = message.actions
    }

    /// `keysLabel(indices)`: `F5+F2`.
    public static func keysLabel(_ indices: [Int]) -> String {
        indices.map { "F\($0 + 1)" }.joined(separator: "+")
    }

    /// The label of an F-key button (`*FunctionKeyLabel(i, shiftHeld)`, `EP:1335-1339`): the CW set in CW, the
    /// digital set in a ready digital mode, otherwise the voice set; `{MYCALL}` = the station call or `Me`.
    public static func label(index: Int, shift: Bool, context: FunctionKeyContext) -> String {
        let keys: FunctionKeySet = context.isCw ? context.cw : (context.digi ? context.digital : context.voice)
        let set: [FunctionKeyMessage] = keys.messages(run: context.run, opposite: shift)
        let label: String = index >= 0 && index < set.count ? set[index].label : ""
        let myCall: String = KotlinStrings.isBlank(context.stationCall) ? "Me" : context.stationCall
        return JavaText.replace(label, "{MYCALL}", myCall)
    }

    /// The button text: `"● "` while recording, `F<n> <label>`.
    public static func buttonText(index: Int, label: String, recording: Bool) -> String {
        (recording ? "● " : "") + "F\(index + 1) " + label
    }
}
