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
    /// The received exchange is complete (`{LOGTHENPOP}` logs only a complete QSO).
    public var exchangeValid: Bool
    /// The call that would come off the call stack now (`{LOGTHENPOP}`), `nil` = an empty stack.
    public var stackNext: String?
    /// The call `{GRAB}` / `{LOGTHENGRAB}` would take from the Grab window now, `nil` = an empty list.
    public var grabNext: String?
    /// The serial number of the QSO after the one being logged (`#` after `{LOGTHENPOP}`); `nil` = `serial + 1`.
    public var serialAfterLog: Int?
    /// The ESM key assignments (the CQ key is special, the progress follows the exchange / my call / his call keys).
    public var esmKeys: EsmKeyMap = .n1mm
    /// N1MM „String between his call and exchange (CW)": joins the his-call and the exchange key sent together.
    public var callExchangeSeparator: String = " "
    /// N1MM „Send partial calls": ESM resends only the corrected part of the call (`PartialCall`); `nil` = the whole.
    public var partialCall: String?

    public init(mode: Mode, digitalReady: Bool, postContest: Bool, run: Bool, call: String, rstSent: String,
                freqHz: Int64, progress: EsmProgress, stationCall: String, voice: FunctionKeySet, cw: FunctionKeySet,
                digital: FunctionKeySet, cwBase: CwMessageBuilder.Context, exchangeValid: Bool = false,
                stackNext: String? = nil, serialAfterLog: Int? = nil, grabNext: String? = nil) {
        self.grabNext = grabNext
        self.exchangeValid = exchangeValid
        self.stackNext = stackNext
        self.serialAfterLog = serialAfterLog
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
    /// `sendDigitalText(text, index)` (fldigi). `returnToRx == false`: the message had `{TX}` without `{RX}` —
    /// fldigi keeps transmitting after it (N1MM).
    case digital(text: String, index: Int, returnToRx: Bool = true)
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
    /// The parameterized macros (`{COMMENT text}`…), performed before the actions.
    public var commands: [MacroCommand] = []
    /// The `{VARYMSGn}` macros of the sent message (their counters move on).
    public var varyUsed: [Int] = []
    /// N1MM `{END}`: what runs once the transmission has finished (nothing when it is stopped or nothing is sent).
    public var deferredActions: [CwMessage.Action] = []
    public var deferredCommands: [MacroCommand] = []
    /// F1 sent: `onCqSent(freqHz)` — CQ frequency remembered, Run (N1MM "CQ key is special").
    public var cqSentFreqHz: Int64?
    /// Ctrl+Shift+F in phone: start/stop recording this key.
    public var recordKey: Int?
    /// Move the focus back to the call field.
    public var refocus: Bool = false
    /// `{LOGTHENPOP}`: the call that comes off the stack after the QSO is logged (`nil` = none, only log).
    public var stackNextCall: String?
    /// `{LOGTHENPOP}`: the ESM progress of the next QSO (what the rest of the message sent to the next call).
    public var stackProgress: EsmProgress?
    /// `{LOGTHENGRAB}`: the next call comes from the Grab window, not the call stack.
    public var nextFromGrab: Bool = false

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
            out.progress = context.progress.afterSent(indices, context.call, map: context.esmKeys)
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
        if context.canTransmit && first == context.esmKeys.cq {
            out.cqSentFreqHz = context.freqHz
        }
        out.refocus = refocus
        return out
    }

    /// `sendCwFunctionKeys` / `sendDigitalFunctionKeys`: the non-blank texts of the keys joined by a space, built
    /// with `CwMessageBuilder`; CW reports unknown macros, an empty message is not sent; the actions always come back.
    private static func keyed(_ indices: [Int], opposite: Bool, digital: Bool, context: FunctionKeyContext,
                              template: String? = nil, into out: inout FunctionKeyOutcome) {
        let set: [FunctionKeyMessage] = (digital ? context.digital : context.cw).messages(run: context.run,
                                                                                         opposite: opposite)
        let keyed: [(key: Int, text: String)] = template.map { [(-1, $0)] } ?? indices.compactMap { i in
            guard i >= 0, i < set.count, !KotlinStrings.isBlank(set[i].text) else { return nil }
            var text: String = set[i].text
            if i == context.esmKeys.hisCall, let partial = context.partialCall {
                // N1MM „Send partial calls": the corrected part only.
                text = JavaText.replace(JavaText.replace(text, "{CALL}", partial), "!", partial)
            }
            return (i, text)
        }
        var ctx: CwMessageBuilder.Context = context.cwBase
        ctx.hisCall = KotlinStrings.trim(context.call)
        ctx.rst = KotlinStrings.isBlank(context.rstSent) ? "599" : context.rstSent
        ctx.functionKeys = set.map(\.text)
        ctx.freqHz = context.freqHz
        ctx.frequencyR = !digital
        if digital {
            ctx.cutNumbers = false
            ctx.leadingZeros = false
        }
        var joined: String = ""
        for (n, item) in keyed.enumerated() {
            if n > 0 {
                let afterCall: Bool = !digital && keyed[n - 1].key == context.esmKeys.hisCall
                    && item.key == context.esmKeys.exchange
                joined += afterCall ? context.callExchangeSeparator : " "
            }
            joined += item.text
        }
        let message: CwMessage
        if let split = CallStackMacro.split(joined) {
            guard let built = logThenPop(split, set: set, indices: indices, context: context, ctx: ctx, into: &out)
            else { return }
            message = built
        } else {
            message = CwMessageBuilder.build(joined, ctx)
        }
        let index: Int = indices[indices.count - 1]
        out.commands = message.commands
        if !message.isEmpty {
            out.varyUsed = message.varyUsed
            out.deferredActions = digital ? message.deferredActions : cwActions(message.deferredActions)
            out.deferredCommands = message.deferredCommands
        }
        if digital {
            if !message.isEmpty {
                // N1MM {TX}/{RX}: a message with {TX} and no {RX} leaves fldigi transmitting; both are then
                // handled by the transmission. Alone (no text) they switch transmit on / back to receive.
                let tx: Bool = message.actions.contains(.digitalTx)
                let rx: Bool = message.actions.contains(.digitalRx)
                out.transmission = .digital(text: message.plainText(), index: index, returnToRx: rx || !tx)
                out.actions = message.actions.filter { $0 != .digitalTx && $0 != .digitalRx }
                return
            }
        } else {
            if !message.unknownMacros.isEmpty {
                out.status = .tr("%s: makra %s zatím neumím — vynechána", .string(keysLabel(indices)),
                                 .string(message.unknownMacros.joined(separator: " ")))
            }
            if !message.isEmpty {
                out.transmission = .cw(message.withoutNewlines, index: index)
            }
        }
        // N1MM `{TX}` in CW: a message that sends nothing keys the PTT by hand (Esc releases it).
        let manualPtt: Bool = message.isEmpty && message.actions.contains(.digitalTx)
        out.actions = digital ? message.actions : cwActions(message.actions) + (manualPtt ? [.manualPtt] : [])
    }

    /// The actions of a CW message: the digital-only ones are dropped.
    private static func cwActions(_ actions: [CwMessage.Action]) -> [CwMessage.Action] {
        actions.filter {
            ![.digitalTx, .digitalRx, .clearTx, .toggleTx, .align, .afcOn, .afcOff, .netOn, .netOff].contains($0)
        }
    }

    /// `{LOGTHENPOP}` / `{LOGTHENNEXT}` (N1MM, Run only): the text before the macro goes to the station being logged,
    /// the text after it to the next call from the stack (`!`, `#`, `{F5}` resolve to the next QSO). Without a stacked
    /// call the QSO is logged and the TU message (F3) is sent instead of the rest. A QSO whose exchange was not sent
    /// or is not complete is never logged this way: nothing is sent (`nil`).
    private static func logThenPop(_ split: CallStackMacro.Split, set: [FunctionKeyMessage], indices: [Int],
                                   context: FunctionKeyContext, ctx: CwMessageBuilder.Context,
                                   into out: inout FunctionKeyOutcome) -> CwMessage? {
        let label: String = keysLabel(indices)
        if !context.run {
            refuse(&out, .tr("%s: {LOGTHENPOP} jen v Run", .string(label)))
            return nil
        }
        if KotlinStrings.isBlank(context.call) || !context.exchangeValid || !context.progress.exchangeSent {
            refuse(&out, .tr("%s: výměna nebyla odeslána nebo není úplná — {LOGTHENPOP} nic nezapíše",
                             .string(label)))
            return nil
        }
        let first: CwMessage = CwMessageBuilder.build(split.prefix, ctx)
        var next: CwMessageBuilder.Context = ctx
        next.lastLogged = ctx.hisCall
        next.serial = context.serialAfterLog ?? (ctx.serial &+ 1)
        let second: CwMessage
        out.nextFromGrab = split.grab
        if let call = split.grab ? context.grabNext : context.stackNext {
            next.hisCall = call
            second = CwMessageBuilder.build(split.suffix, next)
            out.stackNextCall = call
            out.stackProgress = EsmProgress.empty.afterSent(CallStackMacro.functionKeys(in: split.suffix), call,
                                                            map: context.esmKeys)
        } else {
            // Nothing on the stack: log and thank (`!` is the call just logged).
            next.hisCall = ""
            let end: Int = context.esmKeys.end
            let tu: String = end < set.count ? set[end].text : ""
            second = CwMessageBuilder.build(tu, next)
        }
        var parts: [CwMessage.Part] = first.parts
        if !first.parts.isEmpty && !second.parts.isEmpty {
            parts.append(.text(" "))
        }
        parts += second.parts
        return CwMessage(parts: parts, actions: first.actions + [.logThenPop] + second.actions,
                         unknownMacros: first.unknownMacros + second.unknownMacros,
                         commands: first.commands + second.commands, varyUsed: first.varyUsed + second.varyUsed,
                         deferredActions: first.deferredActions + second.deferredActions,
                         deferredCommands: first.deferredCommands + second.deferredCommands)
    }

    /// A refused press: nothing sent, the ESM progress and the last sent keys stay.
    private static func refuse(_ out: inout FunctionKeyOutcome, _ status: EntryStatus) {
        out.status = status
        out.progress = nil
        out.lastSentKeys = nil
    }

    /// A Digital Interface message button (N1MM DI1…DI24): its text is sent through fldigi like an F-key message
    /// (the same macros, `{Fn}` from the digital set, `{LOGTHENPOP}`); `index` is the lamp's key (none: -1).
    public static func sendDigitalTemplate(_ template: String, context: FunctionKeyContext) -> FunctionKeyOutcome {
        var out = FunctionKeyOutcome()
        if context.postContest {
            out.status = .tr("Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
            return out
        }
        guard context.mode.isDigital && context.digitalReady else {
            out.status = .tr("Tlačítka zpráv DI vysílají jen v digitálním módu přes fldigi")
            return out
        }
        keyed([-1], opposite: false, digital: true, context: context, template: template, into: &out)
        return out
    }

    /// `keysLabel(indices)`: `F5+F2`.
    public static func keysLabel(_ indices: [Int]) -> String {
        indices.map { $0 < 0 ? "DI" : "F\($0 + 1)" }.joined(separator: "+")
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
