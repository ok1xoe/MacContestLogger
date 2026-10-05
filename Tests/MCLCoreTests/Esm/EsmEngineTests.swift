import Testing
@testable import MCLCore

/// Port of `esm/EsmEngineTest` (16): rows of the table "ESM Mode Enter Key Actions" from the N1MM+ manual.
@Suite struct EsmEngineTests {

    private typealias Focus = EsmEngine.Focus
    private static let f1 = EsmEngine.f1
    private static let f2 = EsmEngine.f2
    private static let f3 = EsmEngine.f3
    private static let f4 = EsmEngine.f4
    private static let f5 = EsmEngine.f5
    private static let f6 = EsmEngine.f6
    private static let f8 = EsmEngine.f8

    private static let defaults = EsmEngine.Options(spCallOnce: false, workDupes: false)
    private static let bigGun = EsmEngine.Options(spCallOnce: true, workDupes: false)
    private static let workDupes = EsmEngine.Options(spCallOnce: false, workDupes: true)

    /// State: run, empty callsign, dupe, valid exchange, exchange sent, my callsign sent, corrected callsign.
    private static func st(_ run: Bool, _ empty: Bool, _ dupe: Bool, _ valid: Bool, _ exchSent: Bool,
                           _ mySent: Bool, _ corrected: Bool) -> EsmEngine.State {
        EsmEngine.State(run: run, callEmpty: empty, dupe: dupe, exchangeValid: valid,
                        exchangeSent: exchSent, myCallSent: mySent, callCorrected: corrected)
    }

    private static func expect(_ step: EsmEngine.Step, _ keys: [Int], _ log: Bool, _ focus: Focus,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(step.keys == keys, "keys", sourceLocation: sourceLocation)
        #expect(step.log == log, "log entry", sourceLocation: sourceLocation)
        #expect(step.focus == focus, "cursor", sourceLocation: sourceLocation)
    }

    private static func decide(_ state: EsmEngine.State, _ options: EsmEngine.Options) -> EsmEngine.Step {
        EsmEngine.decide(state, options)
    }

    // MARK: - Run

    @Test func runEmptyCallSendsCq() {
        Self.expect(Self.decide(Self.st(true, true, false, false, false, false, false), Self.defaults),
                    [Self.f1], false, .call)
    }

    @Test func runNewCallFirstTimeSendsHisCallAndExchange() {
        Self.expect(Self.decide(Self.st(true, false, false, false, false, false, false), Self.defaults),
                    [Self.f5, Self.f2], false, .exchange)
    }

    @Test func runNewCallRepeatAsksAgain() {
        Self.expect(Self.decide(Self.st(true, false, false, false, true, false, false), Self.defaults),
                    [Self.f8], false, .exchange)
    }

    @Test func runValidExchangeBeforeSendingSendsExchange() {
        Self.expect(Self.decide(Self.st(true, false, false, true, false, false, false), Self.defaults),
                    [Self.f5, Self.f2], false, .exchange)
    }

    @Test func runValidExchangeAfterSendingEndsQsoAndLogs() {
        Self.expect(Self.decide(Self.st(true, false, false, true, true, false, false), Self.defaults),
                    [Self.f3], true, .call)
    }

    @Test func runCorrectedCallIsResentBeforeTu() {
        Self.expect(Self.decide(Self.st(true, false, false, true, true, false, true), Self.defaults),
                    [Self.f5, Self.f3], true, .call)
    }

    @Test func runDupeWithoutExchangeSendsQsoB4() {
        Self.expect(Self.decide(Self.st(true, false, true, false, false, false, false), Self.defaults),
                    [Self.f6], false, .call)
    }

    @Test func runDupeWithValidExchangeIsWorkedAnyway() {
        Self.expect(Self.decide(Self.st(true, false, true, true, false, false, false), Self.defaults),
                    [Self.f5, Self.f2], false, .exchange)
        Self.expect(Self.decide(Self.st(true, false, true, true, true, false, false), Self.defaults),
                    [Self.f3], true, .call)
    }

    @Test func runWorkDupesTreatsDupeAsNewCall() {
        Self.expect(Self.decide(Self.st(true, false, true, false, false, false, false), Self.workDupes),
                    [Self.f5, Self.f2], false, .exchange)
        Self.expect(Self.decide(Self.st(true, false, true, false, true, false, false), Self.workDupes),
                    [Self.f8], false, .exchange)
    }

    // MARK: - S&P

    @Test func spEmptyCallSendsMyCall() {
        Self.expect(Self.decide(Self.st(false, true, false, false, false, false, false), Self.defaults),
                    [Self.f4], false, .call)
    }

    @Test func spNewCallSendsMyCallAndStaysInCall() {
        Self.expect(Self.decide(Self.st(false, false, false, false, false, false, false), Self.defaults),
                    [Self.f4], false, .call)
        // Without Big Gun it calls again and again, the cursor stays.
        Self.expect(Self.decide(Self.st(false, false, false, false, false, true, false), Self.defaults),
                    [Self.f4], false, .call)
    }

    @Test func spBigGunCallsOnceThenAsksAgain() {
        Self.expect(Self.decide(Self.st(false, false, false, false, false, false, false), Self.bigGun),
                    [Self.f4], false, .exchange)
        Self.expect(Self.decide(Self.st(false, false, false, false, false, true, false), Self.bigGun),
                    [Self.f8], false, .exchange)
    }

    @Test func spValidExchangeSendsExchangeAndLogs() {
        Self.expect(Self.decide(Self.st(false, false, false, true, false, true, false), Self.defaults),
                    [Self.f2], true, .call)
    }

    @Test func spExchangeAlreadySentOnlyLogs() {
        Self.expect(Self.decide(Self.st(false, false, false, true, true, true, false), Self.defaults),
                    [], true, .call)
    }

    @Test func spDupeWithoutExchangeDoesNothing() {
        #expect(Self.decide(Self.st(false, false, true, false, false, false, false), Self.defaults).isNothing)
        #expect(Self.decide(Self.st(false, false, true, false, false, false, false), Self.workDupes).isNothing)
    }

    @Test func spDupeWithValidExchangeIsLogged() {
        Self.expect(Self.decide(Self.st(false, false, true, true, false, false, false), Self.defaults),
                    [Self.f2], true, .call)
    }

    // MARK: - Beyond the Java tests: an API for exhaustive traversal

    /// `State(index:)`/`Options(index:)` cover all 512 combinations unambiguously and the bits
    /// correspond to the Java order of the record's components.
    @Test func indexedStatesCoverAllCombinations() {
        var seen: Set<EsmEngine.State> = []
        for index in 0..<EsmEngine.State.count {
            seen.insert(EsmEngine.State(index: index))
        }
        #expect(seen.count == 128)
        #expect(EsmEngine.State(index: 1) == Self.st(true, false, false, false, false, false, false))
        #expect(EsmEngine.State(index: 64) == Self.st(false, false, false, false, false, false, true))
        #expect(EsmEngine.Options(index: 1) == Self.bigGun)
        #expect(EsmEngine.Options(index: 2) == Self.workDupes)
        var config = EsmConfig()
        config.spCallOnce = true
        config.workDupes = false
        #expect(EsmEngine.Options(config) == Self.bigGun)
    }
}
