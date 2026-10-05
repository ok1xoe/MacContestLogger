import Testing
@testable import MCLCore

/// Port of `command/CallFieldCommandsTest` (23 `@Test` + `@ParameterizedTest` with 16 rows of `@CsvSource`,
/// here one method `@Test(arguments:)`).
@Suite struct CallFieldCommandsTests {

    private static let on20m: Int64 = 14_074_000

    private static func parse(_ input: String?, _ freqHz: Int64) throws -> CallFieldCommand {
        try #require(try CallFieldCommands.parse(input, currentFreqHz: freqHz))
    }

    private static func parse(_ input: String, _ freqHz: Int64, _ otherVfoHz: Int64, _ ctrlEnter: Bool) throws
        -> CallFieldCommand {
        try #require(try CallFieldCommands.parse(input, currentFreqHz: freqHz, otherVfoHz: otherVfoHz,
                                                 ctrlEnter: ctrlEnter))
    }

    private static func isEmpty(_ input: String?, _ freqHz: Int64) throws -> Bool {
        try CallFieldCommands.parse(input, currentFreqHz: freqHz) == nil
    }

    private static func qsyHz(_ input: String, _ freqHz: Int64) throws -> Int64? {
        guard case .qsy(let hz) = try parse(input, freqHz) else { return nil }
        return hz
    }

    private static func isInvalid(_ command: CallFieldCommand) -> Bool {
        if case .invalid = command { return true }
        return false
    }

    // MARK: - frequency

    @Test func fullFrequencyInKhzTunesThere() throws {
        #expect(try Self.qsyHz("14025.1", Self.on20m) == 14_025_100)
        #expect(try Self.qsyHz("7012", Self.on20m) == 7_012_000)      // also onto another band
    }

    @Test func commaWorksAsDecimalSeparator() throws {
        #expect(try Self.qsyHz("14025,1", Self.on20m) == 14_025_100)
    }

    @Test func partialFrequencyIsRelativeToLowerBandEdge() throws {
        #expect(try Self.qsyHz("025.1", Self.on20m) == 14_025_100)
        #expect(try Self.qsyHz("250", Self.on20m) == 14_250_000)
        #expect(try Self.qsyHz("300", 144_174_000) == 144_300_000)
    }

    @Test func zeroGoesToBottomOfTheBand() throws {
        #expect(try Self.qsyHz("0", Self.on20m) == 14_000_000)
    }

    @Test func signedValueShiftsByKhz() throws {
        #expect(try Self.qsyHz("+2", Self.on20m) == 14_076_000)
        #expect(try Self.qsyHz("-3", Self.on20m) == 14_071_000)
        #expect(try Self.qsyHz("+0.5", Self.on20m) == 14_074_500)
    }

    @Test func absoluteFrequencyWinsOverPartial() throws {
        // 1830 kHz is a valid 160m → absolute, not 14 000 + 1830.
        #expect(try Self.qsyHz("1830", Self.on20m) == 1_830_000)
    }

    @Test func frequencyOutsideAnyBandIsRejectedNotLogged() throws {
        #expect(Self.isInvalid(try Self.parse("12345", Self.on20m)))   // neither absolute nor within 20m
        #expect(Self.isInvalid(try Self.parse("+500", Self.on20m)))    // a shift outside the band
    }

    @Test func relativeFrequencyNeedsKnownCurrentFrequency() throws {
        #expect(Self.isInvalid(try Self.parse("+2", 0)))
        #expect(Self.isInvalid(try Self.parse("025", 0)))              // without a band there is nothing to count from
        #expect(try Self.qsyHz("14025", 0) == 14_025_000)              // absolute always works
    }

    // MARK: - modes

    @Test(arguments: [
        ("CW", Mode.cw), ("SSB", .ssb), ("USB", .ssb), ("LSB", .ssb), ("AM", .am), ("FM", .fm),
        ("RTTY", .rtty), ("PSK31", .psk), ("PSK63", .psk), ("PSK125", .psk), ("PSK250", .psk),
        ("FT8", .ft8), ("FT4", .ft4), ("JT65", .jt65), ("DIGITAL", .digital), ("DIGI", .digital),
    ] as [(String, Mode)])
    func modeNameSwitchesMode(input: String, expected: Mode) throws {
        #expect(try Self.parse(input, Self.on20m) == .changeMode(mode: expected))
    }

    @Test func modeIsCaseInsensitive() throws {
        #expect(try Self.parse(" cw ", Self.on20m) == .changeMode(mode: .cw))
    }

    // MARK: - other commands

    @Test func keywordCommands() throws {
        let cases: [(String, CallFieldCommand)] = [
            ("WIPELOG", .wipeLog), ("CLEARLOG", .wipeLog), ("VERSION", .version), ("VER", .version),
            ("EXPORT", .exportAdif), ("IMPORT", .importLog), ("WRITELOG", .exportCabrillo),
            ("MAKELOG", .exportCabrillo), ("RESCORE", .rescore), ("AUTORSP", .autoRunSp(enabled: true)),
            ("NOAUTRSP", .autoRunSp(enabled: false)), ("AUTORSPOFF", .autoRunSp(enabled: false)),
            ("ESM", .esmOn), ("ESMON", .esmOn), ("NOESM", .esmOff), ("ESMOFF", .esmOff),
            ("SETUP", .openSetup), ("NETON", .networkOn), ("NET", .networkOn), ("NETOFF", .networkOff),
            ("NONET", .networkOff),
        ]
        for (input, expected) in cases {
            #expect(try Self.parse(input, Self.on20m) == expected, "\(input)")
        }
    }

    @Test func oponAndLoginSignOnOperator() throws {
        #expect(try Self.parse("OPON", Self.on20m) == .login(operator: ""))
        #expect(try Self.parse("opon ok1xoe", Self.on20m) == .login(operator: "OK1XOE"))
        #expect(try Self.parse("LOGIN OK1K", Self.on20m) == .login(operator: "OK1K"))
    }

    // MARK: - callsigns are not commands

    @Test func callsignsAreNeverCommands() throws {
        #expect(try Self.isEmpty("OK1XOE", Self.on20m))
        #expect(try Self.isEmpty("CW1A", Self.on20m))     // starts like a mode
        #expect(try Self.isEmpty("NET1X", Self.on20m))
        #expect(try Self.isEmpty("OPONX", Self.on20m))
        #expect(try Self.isEmpty("4X4AA", Self.on20m))    // starts with a digit
        #expect(try Self.isEmpty("", Self.on20m))
        #expect(try Self.isEmpty("   ", Self.on20m))
        #expect(try Self.isEmpty(nil, Self.on20m))
    }

    @Test func keywordWithTrailingTextIsNotACommand() throws {
        // Only OPON/LOGIN take an argument; "WIPELOG X" must not be executed by mistake.
        #expect(try Self.isEmpty("WIPELOG NOW", Self.on20m))
        #expect(try Self.isEmpty("CW FAST", Self.on20m))
    }

    // MARK: - second VFO and split

    @Test func slashSetsOtherVfo() throws {
        #expect(try Self.parse("/14030", Self.on20m, 0, false) == .otherVfo(freqHz: 14_030_000))
        #expect(try Self.parse("/025", Self.on20m, 0, false) == .otherVfo(freqHz: 14_025_000))
    }

    @Test func slashRelativeIsAgainstOtherVfoWhenKnown() throws {
        #expect(try Self.parse("/+2", Self.on20m, 14_030_000, false) == .otherVfo(freqHz: 14_032_000))
        #expect(try Self.parse("/+2", Self.on20m, 0, false) == .otherVfo(freqHz: 14_076_000))
    }

    @Test func slashOutOfBandIsInvalid() throws {
        #expect(Self.isInvalid(try Self.parse("/99999", Self.on20m, 0, false)))
    }

    @Test func ctrlEnterFrequencyMeansSplitWithTxFrequency() throws {
        #expect(try Self.parse("+2", Self.on20m, 0, true) == .split(txFreqHz: 14_076_000))
        #expect(try Self.parse("14030", Self.on20m, 0, true) == .split(txFreqHz: 14_030_000))
        // without Ctrl it is an ordinary QSY
        #expect(try Self.parse("+2", Self.on20m, 0, false) == .qsy(freqHz: 14_076_000))
    }

    @Test func splitKeywords() throws {
        #expect(try Self.parse("SPLIT", Self.on20m) == .split(txFreqHz: 0))
        #expect(try Self.parse("NOSPLIT", Self.on20m) == .splitOff)
        #expect(try Self.parse("SPLITOFF", Self.on20m) == .splitOff)
        #expect(try Self.parse("SWAP", Self.on20m) == .swapVfo)
    }

    @Test func portableCallIsNotOtherVfo() throws {
        // "/P" etc. are not numbers → a callsign, not a command
        #expect(try CallFieldCommands.parse("/P", currentFreqHz: Self.on20m, otherVfoHz: 0, ctrlEnter: false) == nil)
        #expect(try CallFieldCommands.parse("OK1XOE/P", currentFreqHz: Self.on20m, otherVfoHz: 0, ctrlEnter: false) == nil)
    }

    // MARK: - TOUR, QSO party, SPOTME

    @Test func commandsWithArguments() throws {
        #expect(try Self.parse("TOUR 1200/30", Self.on20m) == .setTour(params: "1200/30"))
        #expect(try Self.parse("tour", Self.on20m) == .setTour(params: ""))
        #expect(try Self.parse("NOTOUR", Self.on20m) == .tourOff)
        #expect(try Self.parse("BONUS K1A, K1B", Self.on20m) == .bonusStations(calls: "K1A, K1B"))
        #expect(try Self.parse("BONUS", Self.on20m) == .bonusStations(calls: ""))
        #expect(try Self.parse("roverqth ham", Self.on20m) == .roverQth(county: "HAM"))
        #expect(try Self.parse("COUNTYLINE DAD,JEF", Self.on20m) == .countyLine(counties: "DAD,JEF"))
        #expect(try Self.parse("NOCOUNTYLINE", Self.on20m) == .countyLineOff)
        #expect(try Self.parse("SPOTME CQ TEST", Self.on20m) == .spotMe(comment: "CQ TEST"))
        #expect(try Self.parse("SPOTME", Self.on20m) == .spotMe(comment: ""))
    }

    @Test func callsignsStartingLikeArgumentCommandsStayCalls() throws {
        #expect(try Self.isEmpty("TOUR1", Self.on20m))
        #expect(try Self.isEmpty("BONUSX", Self.on20m))
    }

    // MARK: - remaining DXLog / N1MM commands

    @Test func programActions() throws {
        #expect(try Self.parse("BCLOG", Self.on20m) == .appAction(action: .broadcastLog))
        #expect(try Self.parse("BYE", Self.on20m) == .appAction(action: .exit))
        #expect(try Self.parse("QUITNOW", Self.on20m) == .appAction(action: .exitNow))
        #expect(try Self.parse("COPYLOG", Self.on20m) == .appAction(action: .copyLog))
        #expect(try Self.parse("BEACONS", Self.on20m) == .appAction(action: .loadBeacons))
        #expect(try Self.parse("OPOFF", Self.on20m) == .appAction(action: .logout))
        #expect(try Self.parse("RELOADNOW", Self.on20m) == .appAction(action: .reload))
    }

    @Test func togglesCutNumbersAndSettingsTabs() throws {
        #expect(try Self.parse("RPT", Self.on20m) == .toggle(setting: .cqRepeat, on: true))
        #expect(try Self.parse("POSTCONTEST", Self.on20m) == .toggle(setting: .postContest, on: true))
        #expect(try Self.parse("NORPT", Self.on20m) == .toggle(setting: .cqRepeat, on: false))
        #expect(try Self.parse("NOWORKDUPE", Self.on20m) == .toggle(setting: .workDupes, on: false))
        #expect(try Self.parse("NORUNSP", Self.on20m) == .autoRunSp(enabled: false))
        #expect(try Self.parse("PROABBREV", Self.on20m) == .cutNumbers(style: .tn))
        #expect(try Self.parse("NOABBREV", Self.on20m) == .cutNumbers(style: nil))
        #expect(try Self.parse("WKEY", Self.on20m) == .openSettingsTab(tabKey: "winkey"))
    }
}
