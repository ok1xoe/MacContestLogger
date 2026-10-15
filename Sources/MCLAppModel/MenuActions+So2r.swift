import Foundation
import MCLCore

/// N1MM Config → SO2R: Dueling CQs and their pause, FocusOther, the `{CTRLFx}` and stereo / OTRSP macro switches, the
/// radio swap times, Winkeyer's second output and the SO2V option „Repeating CQ Ends With VFOB Window Entry" (the
/// sticky options of `So2rSetup`, saved at once).
extension MenuActions {

    /// The ids handled here.
    static let so2rIds: Set<String> = [
        "so2r.dueling", "so2r.duelingTime", "so2r.focusOther", "so2r.focusOtherAlways", "so2r.ctrlFx",
        "so2r.stereoMacros", "so2r.swapTail", "so2r.swapLead", "so2r.winkeyer2", "so2r.so2vRepeat",
        "so2r.twoKeyboards",
        "so2r.voice1.both", "so2r.voice1.left", "so2r.voice1.right", "so2r.voice2.both", "so2r.voice2.left",
        "so2r.voice2.right",
    ]

    /// N1MM SO2R DVK routing: `so2r.voice<radio>.<channel>` → the radio's key and the channel.
    static func voiceRouting(_ id: String) -> (key: So2rSetup.Key, channel: So2rSetup.VoiceChannel)? {
        let parts: [Substring] = id.split(separator: ".")
        guard parts.count == 3, parts[0] == "so2r", let channel = So2rSetup.VoiceChannel(rawValue: String(parts[2]))
        else { return nil }
        switch parts[1] {
        case "voice1": return (.voiceChannel1, channel)
        case "voice2": return (.voiceChannel2, channel)
        default: return nil
        }
    }

    /// Runs one of `so2rIds`.
    static func performSo2r(_ id: String, app: AppModel) {
        if let routing = voiceRouting(id) {
            var setup: So2rSetup = app.config.config.so2r
            setup.set(routing.key, routing.channel.rawValue)
            app.config.config.so2r = setup
            app.config.save(failureKey: "Uložení nastavení selhalo: %s")
            app.status.show("Hlasové zprávy rádia %s: %s", .int(routing.key == .voiceChannel1 ? 1 : 2),
                            .string(app.language.tr(voiceChannelLabel(routing.channel))))
            return
        }
        switch id {
        case "so2r.dueling":
            guard let automation = app.so2rAutomation else { return }
            automation.toggleDueling()
        case "so2r.duelingTime":
            promptSo2rMillis(.duelingCqMs, title: "Pauza Dueling CQ",
                             hint: "ms mezi koncem CQ na jednom rádiu a začátkem na druhém (0–2000)", app: app)
        case "so2r.focusOther":
            guard let automation = app.so2rAutomation else { return }
            automation.toggleFocusOther()
        case "so2r.focusOtherAlways":
            toggleSo2r(.focusOtherAlwaysSwap, app: app, on: "FocusOther: vždy přepnout fokus",
                       off: "FocusOther: přepnout jen při vysílání run rádia")
        case "so2r.ctrlFx":
            toggleSo2r(.ctrlFx, app: app, on: "Makro {CTRLFx} zapnuto", off: "Makro {CTRLFx} vypnuto")
        case "so2r.stereoMacros":
            toggleSo2r(.stereoMacros, app: app, on: "Makra stereo / OTRSP RX zapnuta",
                       off: "Makra stereo / OTRSP RX vypnuta")
        case "so2r.so2vRepeat":
            toggleSo2r(.so2vRepeatEndsWithVfoB, app: app, on: "SO2V: zápis do okna VFO B ukončí opakované CQ",
                       off: "SO2V: zápis do okna VFO B opakované CQ neukončí")
        case "so2r.twoKeyboards":
            toggleSo2r(.twoKeyboards, app: app,
                       on: "Dvě klávesnice zapnuty — klávesnice 1 ovládá levé okno, klávesnice 2 pravé",
                       off: "Dvě klávesnice vypnuty")
        case "so2r.swapTail":
            promptSo2rMillis(.swapTailMs, title: "Čas po vysílání při přepnutí rádia",
                             hint: "ms, o které se po přerušeném vysílání na jednom rádiu odloží přepnutí na druhé (0–2000)",
                             app: app)
        case "so2r.swapLead":
            promptSo2rMillis(.swapLeadMs, title: "Předstih při přepnutí rádia",
                             hint: "ms mezi přepnutím vysílání na druhé rádio a jeho klíčováním (0–2000)", app: app)
        case "so2r.winkeyer2":
            toggleSo2r(.winkeyerSecondOutput, app: app, on: "Winkeyer: rádio 2 klíčuje KEY OUT 2",
                       off: "Winkeyer: obě rádia klíčuje KEY OUT 1")
        default:
            break
        }
    }

    /// The ✓ of the SO2R toggles.
    /// The label of a DVK routing channel.
    static func voiceChannelLabel(_ channel: So2rSetup.VoiceChannel) -> String {
        switch channel {
        case .both: "Oba kanály"
        case .left: "Jen levý kanál"
        case .right: "Jen pravý kanál"
        }
    }

    static func isSo2rChecked(_ id: String, app: AppModel) -> Bool {
        let setup: So2rSetup = app.config.config.so2r
        if let routing = voiceRouting(id) {
            return setup.text(routing.key) == routing.channel.rawValue
        }
        switch id {
        case "so2r.dueling":
            return app.operating.duelingCq
        case "so2r.focusOther":
            return setup.flag(.focusOther)
        case "so2r.focusOtherAlways":
            return setup.flag(.focusOtherAlwaysSwap)
        case "so2r.ctrlFx":
            return setup.flag(.ctrlFx)
        case "so2r.stereoMacros":
            return setup.flag(.stereoMacros)
        case "so2r.so2vRepeat":
            return setup.flag(.so2vRepeatEndsWithVfoB)
        case "so2r.winkeyer2":
            return setup.flag(.winkeyerSecondOutput)
        case "so2r.twoKeyboards":
            return setup.flag(.twoKeyboards)
        default:
            return false
        }
    }

    /// A time of the SO2R setup asked for and saved (0–2000 ms).
    static func promptSo2rMillis(_ key: So2rSetup.Key, title: String, hint: String, app: AppModel) {
        let config: ConfigModel = app.config
        let status: StatusModel = app.status
        app.dialogs.prompt(title: ContestMessage(title), hint: ContestMessage(hint),
                           initial: String(config.config.so2r.millis(key))) { text in
            applySo2rMillis(key, text: text, config: config, status: status)
        }
    }

    /// The prompt's answer: 0–2000 ms is saved, anything else refused.
    static func applySo2rMillis(_ key: So2rSetup.Key, text: String, config: ConfigModel, status: StatusModel) {
        guard let value = So2rSetup.parseMillis(text) else {
            status.show("Neplatný čas (0–2000 ms)")
            return
        }
        var setup: So2rSetup = config.config.so2r
        setup.set(key, millis: value)
        config.config.so2r = setup
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        status.show("SO2R: uloženo %s ms", .int(value))
    }

    /// An SO2R switch flipped and saved, with its status.
    static func toggleSo2r(_ key: So2rSetup.Key, app: AppModel, on: String, off: String) {
        var setup: So2rSetup = app.config.config.so2r
        let next: Bool = !setup.flag(key)
        setup.set(key, flag: next)
        app.config.config.so2r = setup
        app.config.save(failureKey: "Uložení nastavení selhalo: %s")
        app.status.show(next ? on : off)
    }
}
