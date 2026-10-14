import Foundation
import MCLCore

/// The rig macros of the F-key messages (N1MM): raw CAT commands, the antenna port / RX antenna toggle and the
/// antenna table's `{AUXANTSEL}`.
extension RigModel {

    /// `{CAT…ASC}` / `{CAT…HEX}`: the commands go to the target rig's `rigctld` as `w` (send_cmd) on its own lane, in
    /// order, followed by the `{CATDELAY}` pause; nothing is sent when the target does not apply (`{CATA1…}` while
    /// radio 2 is active). A failure is shown in the status line.
    func sendMacroCat(_ macro: CatMacro, delayMs: Int) {
        guard let index = catTarget(macro.target), index < lanes.count else { return }
        let commands: [String] = macro.commands
        lanes[index].run({ cat -> RigOutcome in
            let outcome: RigOutcome = RigOutcome.run(cat) { rig in
                for command in commands {
                    let reply: RigRawReply = try rig.sendRaw("w " + command)
                    if reply.code < 0 {
                        throw CatException("RPRT " + String(reply.code))
                    }
                }
            }
            if delayMs > 0 {
                Thread.sleep(forTimeInterval: Double(delayMs) / 1000)
            }
            return outcome
        }, then: { [weak self] outcome in
            switch outcome {
            case .done:
                break
            case .noRig:
                self?.show(.tr("CAT makro: TRX %s není připojený", .int(index + 1)))
            case .failed(let message):
                self?.show(.tr("CAT makro: %s", .string(message)))
            }
        })
    }

    /// The rig index a CAT macro goes to, `nil` = not now. Radio n is the rig of VFO n (both VFOs are one rig in SO2V).
    func catTarget(_ target: CatMacro.Target) -> Int? {
        let active: Int = vfo.activeVfo
        switch target {
        case .active:
            return vfo.catIndex(for: active)
        case .radio(let radio):
            return vfo.catIndex(for: radio)
        case .ifActive(let radio):
            return radio == active ? vfo.catIndex(for: radio) : nil
        case .ifInactive(let radio):
            return vfo.twoEntryWindows && radio != active ? vfo.catIndex(for: radio) : nil
        }
    }

    /// `{ANTRX1TOGGLE}`…: antenna port `port` of the active rig (hamlib `Y port 0`); the same port again toggles its
    /// RX antenna (`Y port 1` / `Y port 0`; what the option does is rig-specific). Refused while transmitting.
    func toggleRxAntenna(port: Int, transmitting: Bool) {
        if transmitting {
            show(.tr("Anténa: během vysílání se nepřepíná"))
            return
        }
        let index: Int = vfo.activeCatIndex
        var state: MacroAntennaState = macroAntenna[index] ?? MacroAntennaState()
        let option: Int = state.select(port: port)
        macroAntenna[index] = state
        lanes[index].run({ cat -> RigOutcome in
            RigOutcome.run(cat) { rig in
                let reply: RigRawReply = try rig.sendRaw("Y " + String(port) + " " + String(option))
                if reply.code < 0 {
                    throw CatException("RPRT " + String(reply.code))
                }
            }
        }, then: { [weak self] outcome in
            switch outcome {
            case .done:
                self?.show(option == 0 ? .tr("Anténa ANT%s", .int(port)) : .tr("Anténa ANT%s + RX anténa", .int(port)))
            case .noRig:
                self?.show(.tr("Anténa: TRX není připojený"))
            case .failed(let message):
                self?.show(.tr("Anténa: %s", .string(message)))
            }
        })
    }

    /// `{AUXANTSEL nn}`: the antenna with code `nn` from the antenna table, applied as Alt+F9 would (OTRSP AUX, the
    /// rig's connector) and announced in the UDP RadioInfo.
    func selectAntenna(code: Int) {
        let antennas: [AntennaEntry] = config.config.antennas
        guard let index = antennas.firstIndex(where: { $0.code == code }) else {
            show(.tr("Anténa s kódem %s není v tabulce antén", .int(code)))
            return
        }
        var next: AntennaApply = antenna
        let plan: AntennaApply.Plan? = next.apply(index: index, antennas: antennas, activeVfo: vfo.activeVfo,
                                                  viaRig: config.config.antennaViaRig, rigConnected: active.connected)
        antenna = next
        auxAntenna = antennas[index]
        applyAntennaPlan(plan)
    }
}

/// The antenna port a `{ANTRXnTOGGLE}` chose last on one rig and the RX antenna remembered for each port.
struct MacroAntennaState: Equatable, Sendable {
    var port: Int?
    var rxOn: [Int: Bool] = [:]

    /// Selects `port`; the same port again toggles its RX antenna. The result is the hamlib option (1 = RX antenna).
    mutating func select(port next: Int) -> Int {
        if port == next {
            rxOn[next] = !(rxOn[next] ?? false)
        }
        port = next
        return (rxOn[next] ?? false) ? 1 : 0
    }
}

/// The two-radio macros of the F-key messages (N1MM): stereo, OTRSP commands and the AF mute of the active or the
/// inactive rig.
extension RigModel {

    /// `{STEREOON}` / `{STEREOOFF}`: OTRSP `RXnS` / `RXn` for the active rig (SO2R).
    func setSo2rStereo(_ on: Bool) {
        guard vfo.so2r else {
            show(.tr("Stereo jen v SO2R"))
            return
        }
        vfo.setStereo(on)
        peripherals.otrspRx(rig: vfo.activeVfo + 1, stereo: on)
        show(RigTexts.so2rStereo(on))
    }

    /// `{OTRSP cmd}` / `{OTRSPOTHER cmd}`: the command as written; `RX` alone is the RX command of the active / the
    /// inactive radio (with the stereo state).
    func sendOtrsp(_ command: String, other: Bool) {
        guard peripherals.otrspOpen else {
            show(.tr("OTRSP: zařízení není připojené (Nastavení → SO2R)"))
            return
        }
        if command == "RX" {
            let radio: Int = (other ? 1 - vfo.activeVfo : vfo.activeVfo) + 1
            peripherals.otrspRx(rig: radio, stereo: vfo.stereo)
        } else {
            peripherals.otrspRaw(command)
        }
    }

    /// `{ACTIVEAUDIO…}` / `{INACTIVEAUDIO…}`: hamlib `U MUTE 1` / `U MUTE 0` on the active or the inactive rig
    /// (`on` = unmute, `nil` = toggle). The inactive rig exists only in SO2R. Only rigs whose hamlib driver knows MUTE
    /// follow it.
    func setAudio(inactive: Bool, on: Bool?) {
        let index: Int
        if inactive {
            guard vfo.so2r else {
                show(.tr("Neaktivní rig je jen v SO2R"))
                return
            }
            index = vfo.catIndex(for: 1 - vfo.activeVfo)
        } else {
            index = vfo.activeCatIndex
        }
        guard index < lanes.count else { return }
        let muted: Bool = on.map { !$0 } ?? !(macroMuted[index] ?? false)
        macroMuted[index] = muted
        lanes[index].run({ cat -> RigOutcome in
            RigOutcome.run(cat) { rig in
                let reply: RigRawReply = try rig.sendRaw("U MUTE " + (muted ? "1" : "0"))
                if reply.code < 0 {
                    throw CatException("RPRT " + String(reply.code))
                }
            }
        }, then: { [weak self] outcome in
            switch outcome {
            case .done:
                self?.show(muted ? .tr("TRX %s: zvuk ztlumen", .int(index + 1))
                                 : .tr("TRX %s: zvuk zapnut", .int(index + 1)))
            case .noRig:
                self?.show(.tr("CAT makro: TRX %s není připojený", .int(index + 1)))
            case .failed(let message):
                self?.show(.tr("CAT makro: %s", .string(message)))
            }
        })
    }
}
