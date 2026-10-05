import Testing
@testable import MCLCore

/// `ConfigEffectPlan` against `commitConfigurer` (`CD:554-614`) with the inner effects of `saveConfig`
/// (`AS:3726-3736`) and against `loadProfile` (`AS:2509-2522`) of v1.1.1.
@Suite struct ConfigEffectPlanTests {

    private static let commitAbort: ConfigEffect.SaveFailure = .abortPlan(status: .settingsSaveFailed)
    private static let profileAbort: ConfigEffect.SaveFailure = .abortPlan(status: .profileFailed)

    /// Hand-written from `CD:563-612`, statement by statement, with the atomic head of (write first,
    /// then the live-state parts of `applyTo`: config, `I18n.use`, the new antenna instances).
    private static func expectedCommit(_ c: ConfigChanges, reconnectRig: Bool, catConnected: Bool) -> [ConfigEffect] {
        var e: [ConfigEffect] = []
        e.append(.saveConfig(onFailure: Self.commitAbort))
        e.append(.applyConfig)
        e.append(.switchLanguage)
        e.append(.resetAntennaIndex)
        e.append(.saveInner(.dxMyCall))
        e.append(.saveInner(.parallelClusters))
        e.append(.saveInner(.footswitch))
        e.append(.saveInner(.callData))
        e.append(.statusSaved)
        e.append(.cwSpeed)
        e.append(.esm)
        e.append(.runMode)
        e.append(.radioMode)
        e.append(.modeSettings)
        e.append(.checkClock)
        e.append(.keyBindings)
        e.append(.configRevision)
        e.append(.spotBuffer)
        e.append(.minSkimmers)
        e.append(.blacklist)
        e.append(.hamQth)
        if c.cluster { e.append(.restartCluster) }
        if c.broadcast { e.append(.restartBroadcast) }
        if c.wsjtx { e.append(.restartWsjtx) }
        if c.n1mm { e.append(.restartN1mm) }
        if c.adifUdp { e.append(.restartAdifUdp) }
        if c.contestDir { e.append(.reloadContestData) }
        if c.scoringStation { e.append(.rescore) }
        e.append(.writeBandData)
        e.append(.reloadBandData)
        if reconnectRig || (c.rig && catConnected) {
            e.append(.reconnectCat(disconnectFirst: catConnected))
        }
        return e
    }

    private static func changes(_ bits: Int) -> ConfigChanges {
        ConfigChanges(
            cluster: bits & 1 != 0, broadcast: bits & 2 != 0, wsjtx: bits & 4 != 0, n1mm: bits & 8 != 0,
            adifUdp: bits & 16 != 0, contestDir: bits & 32 != 0, rig: bits & 64 != 0, scoringStation: bits & 128 != 0)
    }

    @Test func allFlagCombinationsMatchKotlinOrder() {
        var checked = 0
        for bits in 0..<256 {
            let c: ConfigChanges = Self.changes(bits)
            for reconnect in [false, true] {
                for connected in [false, true] {
                    let plan: [ConfigEffect] = ConfigEffectPlan.commit(c, reconnectRig: reconnect, catConnected: connected)
                    let expected: [ConfigEffect] = Self.expectedCommit(c, reconnectRig: reconnect, catConnected: connected)
                    #expect(plan == expected, "bits \(bits) reconnect \(reconnect) connected \(connected)")
                    checked += 1
                }
            }
        }
        #expect(checked == 1024)
    }

    @Test func nothingChangedIsTheFixedTailOnly() {
        let plan: [ConfigEffect] = ConfigEffectPlan.commit(.none, reconnectRig: false, catConnected: true)
        #expect(plan.count == 23)
        #expect(plan.first == .saveConfig(onFailure: Self.commitAbort))
        #expect(plan.suffix(2) == [.writeBandData, .reloadBandData])
        let restarts: [ConfigEffect] = [.restartCluster, .restartBroadcast, .restartWsjtx, .restartN1mm, .restartAdifUdp]
        #expect(!plan.contains { restarts.contains($0) })
        #expect(!plan.contains(.reloadContestData) && !plan.contains(.rescore))
    }

    @Test func saveIsFirstAndLiveStateChangesOnlyAfterIt() {
        let all = ConfigChanges(
            cluster: true, broadcast: true, wsjtx: true, n1mm: true, adifUdp: true, contestDir: true, rig: true,
            scoringStation: true)
        let plan: [ConfigEffect] = ConfigEffectPlan.commit(all, reconnectRig: true, catConnected: true)
        #expect(Array(plan.prefix(4)) == [.saveConfig(onFailure: Self.commitAbort), .applyConfig, .switchLanguage, .resetAntennaIndex])
        #expect(plan.filter { if case .saveConfig = $0 { true } else { false } }.count == 1)
        #expect(plan.last == .reconnectCat(disconnectFirst: true))
    }

    @Test func catReconnectRules() {
        let rig = ConfigChanges(rig: true)
        // Rig changed but CAT not connected: no reconnect.
        #expect(!ConfigEffectPlan.commit(rig, reconnectRig: false, catConnected: false).contains { Self.isCat($0) })
        // Rig changed and connected: disconnect first, then connect.
        #expect(ConfigEffectPlan.commit(rig, reconnectRig: false, catConnected: true).last == .reconnectCat(disconnectFirst: true))
        // "Uložit a připojit" without a connection: connect only.
        #expect(ConfigEffectPlan.commit(.none, reconnectRig: true, catConnected: false).last == .reconnectCat(disconnectFirst: false))
        // Unchanged rig, connected, plain OK: nothing.
        #expect(!ConfigEffectPlan.commit(.none, reconnectRig: false, catConnected: true).contains { Self.isCat($0) })
    }

    private static func isCat(_ effect: ConfigEffect) -> Bool {
        if case .reconnectCat = effect { return true }
        return false
    }

    @Test func profileLoadIsAtomicAndFollowsLoadProfile() {
        let plan: [ConfigEffect] = ConfigEffectPlan.profileLoad(name: "Doma", replacesAntennas: true)
        let expected: [ConfigEffect] = [
            .saveConfig(onFailure: Self.profileAbort),
            .applyConfig,
            .resetAntennaIndex,
            .saveInner(.dxMyCall), .saveInner(.parallelClusters), .saveInner(.footswitch), .saveInner(.callData),
            .modeSettings, .keyBindings, .radioMode, .runMode, .reloadContestData, .configRevision,
            .profileLoaded(name: "Doma"),
        ]
        #expect(plan == expected)
    }

    @Test func profileWithoutAntennasKeepsTheIndex() {
        let plan: [ConfigEffect] = ConfigEffectPlan.profileLoad(name: "X", replacesAntennas: false)
        #expect(Array(plan.prefix(3)) == [.saveConfig(onFailure: Self.profileAbort), .applyConfig, .saveInner(.dxMyCall)])
        #expect(!plan.contains(.resetAntennaIndex))
    }

    /// No language switch, no ESM, no restarts, no status "saved", no band data, no CAT in a profile load.
    @Test func profileLoadOmitsCommitOnlyEffects() {
        let plan: [ConfigEffect] = ConfigEffectPlan.profileLoad(name: "X", replacesAntennas: true)
        let absent: [ConfigEffect] = [
            .switchLanguage, .esm, .cwSpeed, .statusSaved, .checkClock, .spotBuffer, .minSkimmers,
            .blacklist, .hamQth, .restartCluster, .restartBroadcast, .restartWsjtx, .restartN1mm, .restartAdifUdp,
            .rescore, .writeBandData, .reloadBandData,
        ]
        for effect in absent {
            #expect(!plan.contains(effect), "\(effect)")
        }
        #expect(!plan.contains { Self.isCat($0) })
    }

    private static func isSave(_ effect: ConfigEffect) -> Bool {
        if case .saveConfig = effect { return true }
        return false
    }

    /// Both plans are atomic: exactly one write, it is the first effect and it aborts; every live-state effect
    /// comes after it.
    @Test func saveAbortsAndPrecedesEveryLiveStateEffectInBothPlans() {
        let all = ConfigChanges(
            cluster: true, broadcast: true, wsjtx: true, n1mm: true, adifUdp: true, contestDir: true, rig: true,
            scoringStation: true)
        let plans: [([ConfigEffect], ConfigEffect.SaveFailure)] = [
            (ConfigEffectPlan.commit(all, reconnectRig: true, catConnected: true), Self.commitAbort),
            (ConfigEffectPlan.commit(.none, reconnectRig: false, catConnected: false), Self.commitAbort),
            (ConfigEffectPlan.profileLoad(name: "A", replacesAntennas: true), Self.profileAbort),
            (ConfigEffectPlan.profileLoad(name: "B", replacesAntennas: false), Self.profileAbort),
        ]
        for (plan, abort) in plans {
            #expect(plan.first == .saveConfig(onFailure: abort))
            #expect(plan.filter { Self.isSave($0) }.count == 1)
            #expect(plan.dropFirst().first == .applyConfig)
        }
    }
}
