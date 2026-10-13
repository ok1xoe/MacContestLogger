import Foundation
import MCLCore

/// The band map's top bar (N1MM Logger+ Bandmap window): SH/DX to the cluster, the Wide/Narrow filter, back to the
/// CQ frequency, the RIT offset (a click clears it), the mode (a click picks another one) and the programmable
/// buttons (up to 36, `BandmapButtonCommand`), and the spot filter sheet of the context menu.
///
/// Safety: nothing here keys the transmitter. Raw CAT goes through `PluginCatPolicy` (no PTT) on the plugins' own
/// `rigctld` connection, the macros are the non-transmitting control macros and the text commands are the call
/// field's (QSY, mode, split, RIT).
extension BandmapModel {

    /// The modes of the mode label's menu (N1MM: USB/LSB/CW/RTTY/PSK/AM/FM, plus the WSJT modes), as call field
    /// commands.
    public static let modeCommands: [String] = ["CW", "USB", "LSB", "RTTY", "PSK", "FT8", "FT4", "AM", "FM"]

    // MARK: - SH/DX, CQ, RIT, mode

    /// „SH/DX" with the Telnet window's spot count, formatted for the node, to the main cluster connection (status when
    /// it is not connected).
    public func showDx() {
        guard let cluster = dxCluster, cluster.connected else {
            statusLine?.show(ContestMessage("DX Cluster není připojen"))
            return
        }
        cluster.send(cluster.showDxCommand())
    }

    /// The CQ button is active with a CQ frequency on this band.
    public var canJumpToCq: Bool {
        cqHz != nil
    }

    /// „CQ": back to the last CQ frequency on the band (Run), like a click on the CQ marker.
    public func jumpToCq() {
        guard let band, let cq = operating.jumpToCqFrequency(band: band) else { return }
        rig.qsy(cq)
    }

    /// The RIT offset the application last set (0 = off).
    public var ritHz: Int {
        rig.rit.ritHz
    }

    /// The RIT label: `RIT +120`, `RIT 0`.
    public var ritText: String {
        "RIT " + (ritHz > 0 ? "+" : "") + String(ritHz)
    }

    /// A click on the RIT label clears it.
    public func clearRit() {
        rig.clearRit()
    }

    /// The mode label: the rig's mode (USB, CW, PKTUSB…) with CAT, otherwise the entry window's.
    public var modeText: String {
        if let raw = rig.activeState?.rawMode, !KotlinStrings.isBlank(raw) {
            return raw
        }
        return keyEntry?()?.form.mode.rawValue ?? ""
    }

    /// A mode picked from the mode label: the call field's mode command (rig and log), the call field untouched.
    public func setMode(_ command: String) {
        runText(command)
    }

    // MARK: - Wide/Narrow

    /// The filter is narrow (`nil` without CAT: the button shows „Wide/Narrow").
    public var filterIsNarrow: Bool? {
        guard let state = rig.activeState, !KotlinStrings.isBlank(state.rawMode) else { return nil }
        let widths = config.config.dxCluster.filterWidths(state.mode ?? .ssb)
        return FilterWidthToggle.isNarrow(passbandHz: state.passband, wide: widths.wide, narrow: widths.narrow)
    }

    /// „Wide/Narrow": the rig's passband to the other width of its mode (`M <mode> <Hz>`).
    public func toggleFilterWidth() {
        guard let state = rig.activeState else {
            statusLine?.show(ContestMessage("Šířka filtru: připoj TRX (CAT)"))
            return
        }
        let widths = config.config.dxCluster.filterWidths(state.mode ?? .ssb)
        guard let command = FilterWidthToggle.command(rawMode: state.rawMode, passbandHz: state.passband,
                                                      wide: widths.wide, narrow: widths.narrow) else {
            statusLine?.show(ContestMessage("Šířka filtru: připoj TRX (CAT)"))
            return
        }
        sendCat(command)
    }

    // MARK: - programmable buttons

    /// The configured buttons (at most 36).
    public var buttons: [DxClusterCommand] {
        config.config.dxCluster.bandmapButtons
    }

    /// The label a button shows now (its current toggle state); an empty label shows the button's key.
    public func buttonLabel(_ index: Int) -> String {
        guard buttons.indices.contains(index) else { return "" }
        let label: String = BandmapButtonCommand.label(buttons[index].label, state: buttonStates[index] ?? 0)
        return label.isEmpty ? Self.buttonKey(index) : label
    }

    /// N1MM Ctrl+Alt+Shift+0…9, A…Z (here ⌘⌥⇧): the key of button `index`.
    public static func buttonKey(_ index: Int) -> String {
        let keys: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return keys.indices.contains(index) ? String(keys[index]) : ""
    }

    /// The button of a key character (`0`…`9`, `A`…`Z`), `nil` for another one or a missing button.
    public func buttonIndex(forKey key: String) -> Int? {
        let keys: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard key.count == 1, let index = keys.firstIndex(of: Character(key.uppercased())),
              buttons.indices.contains(index) else { return nil }
        return index
    }

    /// ⌘⌥⇧+0…9, A…Z while the Bandmap window is the key window (N1MM Ctrl+Alt+Shift+0…Z): the button of the key.
    /// `true` = consumed (press and release); other keys are left alone.
    public func handleButtonKey(_ event: MacKeyEvent) -> Bool {
        guard event.kind != .flagsChanged, let stroke = AwtKeyCodes.translateForLayout(event),
              stroke.isMetaDown, stroke.isAltDown, stroke.isShiftDown, !stroke.isControlDown,
              (0x30...0x5A).contains(stroke.vk), let scalar = Unicode.Scalar(UInt32(stroke.vk)),
              let index = buttonIndex(forKey: String(Character(scalar))) else { return false }
        if stroke.phase == .pressed && !event.isARepeat {
            pressButton(index)
        }
        return true
    }

    /// A click on button `index`: its current state runs, the next state becomes current.
    public func pressButton(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        let button: DxClusterCommand = buttons[index]
        let states: [String] = BandmapButtonCommand.states(button.command)
        let current: Int = (buttonStates[index] ?? 0) % states.count
        buttonStates[index] = (current + 1) % states.count
        for step in BandmapButtonCommand.steps(states[current]) {
            switch step {
            case .cat(let command):
                sendCat(command)
            case .macro(let action):
                keyEntry?()?.performMacroAction(action)
            case .text(let text):
                runText(text)
            case .refused(let macro):
                statusLine?.show(ContestMessage("%s: tlačítko bandmapy ho neprovede", .string(macro)))
            }
        }
    }

    /// The editor saved the buttons (the configuration file only, like the band plan option); the toggle states start
    /// over.
    public func saveButtons(_ list: [DxClusterCommand]) {
        config.config.dxCluster.bandmapButtons = list.filter {
            !KotlinStrings.isBlank($0.label) || !KotlinStrings.isBlank($0.command)
        }
        config.saveSilently()
        buttonStates = [:]
    }

    /// N1MM „Telnet Bands/Modes" and „Telnet Filters": the spot filter sheet.
    public func openSpotFilter() {
        showSpotFilter = true
    }

    /// The buttons' editor (starting on button `index`).
    public func editButtons(_ index: Int = 0) {
        editingButtons = index
    }

    // MARK: - running

    /// A call field text command without clearing the call field; a text that is no command says so.
    func runText(_ text: String) {
        guard let entry = keyEntry?() else { return }
        if !entry.runButtonText(text) {
            statusLine?.show(ContestMessage("„%s“ není příkaz", .string(text)))
        }
    }

    /// A raw `rigctld` command checked by `PluginCatPolicy`; a refusal or a failure goes to the status line.
    func sendCat(_ command: String) {
        if let refusal = PluginCatPolicy.refusal(command, context: catContext()) {
            statusLine?.show(ContestMessage("CAT %s: %s", .string(command), .string(refusal)))
            return
        }
        rig.sendRawCat(command) { [weak self] result in
            if case .failure(let error) = result {
                self?.statusLine?.show(ContestMessage("CAT %s: %s", .string(command), .string(error.message)))
            }
        }
    }
}

extension EntryModel {

    /// A band map button's text command: run like Enter in the call field (QSY, mode, split, RIT…) but the call field
    /// keeps its call and the focus. `false` = the text is no command.
    @discardableResult
    func runButtonText(_ text: String) -> Bool {
        guard let command = EntryCommandPlan.parseForEnter(text, currentFreqHz: form.freqHz,
                                                           otherVfoHz: otherVfoHz) else { return false }
        let effects: [EntryCommandEffect] = EntryCommandPlan.plan(command, context: commandContext())
            .filter { $0 != .clearCall && $0 != .focusCall }
        perform(effects: effects[...])
        return true
    }
}
