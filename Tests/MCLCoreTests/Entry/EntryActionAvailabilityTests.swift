import Testing
@testable import MCLCore

/// Every one of the 55 shortcut actions and the 34 command kinds is assigned an area.
@Suite struct EntryActionAvailabilityTests {

    /// The `when` branches of `runShortcut` (`EP:873-938`) in source order — the same 55 constants as the enum.
    private static let runShortcutOrder: [String] = [
        "SEND_CALL_EXCHANGE", "TU_AND_LOG", "LOG_WITHOUT_SENDING", "FORCE_LOG", "WIPE", "WIPE_UNDO", "DELETE_LAST",
        "NOTE", "FIND", "INCREMENT_NR", "TOGGLE_ESM", "TOGGLE_CUT", "YANK_SCP", "FUNCTION_KEYS_SETUP", "HELP",
        "OPERATOR", "TOGGLE_RUN", "JUMP_CQ", "CQ_REPEAT", "CQ_REPEAT_TIME", "TUNE", "SPLIT_ON", "SPLIT_TOGGLE",
        "SPLIT_PROMPT", "PREVIOUS_FREQUENCY", "SWAP_VFO", "AUTO_RUN_SP", "COPY_TO_VFO_B", "RIT_UP", "RIT_DOWN",
        "RIT_CLEAR", "SWITCH_RADIO", "SO2R_STEREO", "NEXT_ANTENNA", "CW_KEYBOARD", "PASS_CALL", "POP_STACK",
        "ROTOR_TURN", "ROTOR_LONG", "ROTOR_STOP", "BAND_UP", "BAND_DOWN", "NEXT_SPOT_UP", "NEXT_SPOT_DOWN",
        "NEXT_MULT_UP", "NEXT_MULT_DOWN", "NEXT_SELF_UP", "NEXT_SELF_DOWN", "SPOT_IT", "SPOT_WITH_COMMENT", "STORE",
        "MARK", "REMOVE_SPOT", "REMOVE_SPOT_BLACKLIST", "DX_CLUSTER_WINDOW",
    ]

    private static let expected: [String: EntryArea] = [
        "SEND_CALL_EXCHANGE": .local, "TU_AND_LOG": .local, "LOG_WITHOUT_SENDING": .local, "FORCE_LOG": .local,
        "WIPE": .local, "WIPE_UNDO": .local, "DELETE_LAST": .local, "NOTE": .local, "FIND": .local, "INCREMENT_NR": .local,
        "TOGGLE_ESM": .local, "TOGGLE_CUT": .local, "YANK_SCP": .local, "FUNCTION_KEYS_SETUP": .windows, "HELP": .windows,
        "OPERATOR": .local, "TOGGLE_RUN": .local, "JUMP_CQ": .radio, "CQ_REPEAT": .local, "CQ_REPEAT_TIME": .local,
        "TUNE": .radio, "SPLIT_ON": .radio, "SPLIT_TOGGLE": .radio, "SPLIT_PROMPT": .radio,
        "PREVIOUS_FREQUENCY": .radio, "SWAP_VFO": .radio, "AUTO_RUN_SP": .local, "COPY_TO_VFO_B": .radio,
        "RIT_UP": .radio, "RIT_DOWN": .radio, "RIT_CLEAR": .radio, "SWITCH_RADIO": .radio, "SO2R_STEREO": .radio,
        "NEXT_ANTENNA": .radio, "CW_KEYBOARD": .keyer, "PASS_CALL": .network, "POP_STACK": .network,
        "ROTOR_TURN": .radio, "ROTOR_LONG": .radio, "ROTOR_STOP": .radio, "BAND_UP": .radio, "BAND_DOWN": .radio,
        "NEXT_SPOT_UP": .spots, "NEXT_SPOT_DOWN": .spots, "NEXT_MULT_UP": .spots, "NEXT_MULT_DOWN": .spots,
        "NEXT_SELF_UP": .spots, "NEXT_SELF_DOWN": .spots, "SPOT_IT": .spots, "SPOT_WITH_COMMENT": .spots,
        "STORE": .spots, "MARK": .spots, "REMOVE_SPOT": .spots, "REMOVE_SPOT_BLACKLIST": .spots,
        "DX_CLUSTER_WINDOW": .spots,
    ]

    @Test func everyShortcutActionHasAnArea() {
        #expect(ShortcutAction.allCases.count == 55)
        #expect(Set(ShortcutAction.allCases.map(\.name)) == Set(Self.runShortcutOrder))
        #expect(Self.runShortcutOrder.count == 55)
        for action in ShortcutAction.allCases {
            #expect(EntryActionAvailability.area(of: action) == Self.expected[action.name], "\(action.name)")
        }
    }

    /// `ON_KEY_UP` (`EP:1388`).
    @Test func onKeyUpActions() {
        let up: [String] = ShortcutAction.allCases.filter(\.onKeyUp).map(\.name)
        #expect(up == ["LOG_WITHOUT_SENDING", "FORCE_LOG", "OPERATOR"])
    }

    @Test func everyCommandKindHasAnArea() {
        let expected: [EntryCommandKind: EntryArea] = [
            .qsy: .local, .otherVfo: .radio, .split: .radio, .splitOff: .radio, .runScript: .local, .rit: .radio,
            .swapVfo: .radio, .changeMode: .local, .login: .local, .wipeLog: .local, .version: .local, .exportAdif: .local,
            .exportCabrillo: .local, .importLog: .windows, .esmOn: .local, .esmOff: .local, .autoRunSp: .local,
            .setTour: .local, .tourOff: .local, .bonusStations: .local, .roverQth: .local, .countyLine: .local,
            .countyLineOff: .local, .spotMe: .spots, .appAction: .local, .toggle: .local, .cutNumbers: .local,
            .openSettingsTab: .windows, .rescore: .local, .openSetup: .windows, .networkOn: .network,
            .networkOff: .network, .invalid: .local, .overflow: .local,
        ]
        #expect(EntryCommandKind.allCases.count == 34)
        #expect(expected.count == 34)
        for kind in EntryCommandKind.allCases {
            #expect(EntryActionAvailability.area(of: kind) == expected[kind], "\(kind)")
        }
    }

    @Test func appActionsByArea() {
        let expected: [CallFieldCommand.Action: EntryArea] = [
            .broadcastLog: .network, .exit: .local, .exitNow: .local, .wipeLogNow: .local, .closeContest: .local,
            .newContest: .local, .openContest: .local, .copyLog: .local, .reload: .local, .reopen: .local, .debugCat: .radio,
            .resetInterfaces: .radio, .loadBeacons: .spots, .logout: .local,
        ]
        #expect(expected.count == CallFieldCommand.Action.allCases.count)
        for action in CallFieldCommand.Action.allCases {
            #expect(EntryActionAvailability.area(of: action) == expected[action], "\(action)")
            #expect(EntryActionAvailability.area(of: .appAction(action: action)) == expected[action])
        }
        #expect(EntryActionAvailability.area(of: .split(txFreqHz: 0)) == .radio)
        #expect(EntryActionAvailability.area(of: .qsy(freqHz: 1)) == .local)
    }

    /// The local, the rig's, the keyer's, the spots' and the network's actions work; the other windows not yet.
    @Test func availableAreas() {
        let available: [EntryArea] = EntryArea.allCases.filter { EntryActionAvailability.isAvailable($0) }
        #expect(available == [.local, .radio, .keyer, .spots, .network])
    }
}
