import Foundation
import Testing
@testable import MCLCore

/// `QsoLogPipeline.plan` against the Kotlin `AppState.log` (`ui/AppState.kt`, v1.1.1) and the contest
/// path of `EntryPanel` (`state.log(qso)` then `contest.log(…)`), read from the source: the order of
/// the steps and which of them an imported QSO skips.
@Suite struct QsoLogPipelineTests {

    private struct Lookup: DxccLookup {
        static let ok = DxccEntity(
            entityCode: 503, name: "Czech Republic", countryCode: "OK", continents: ["EU"],
            cq: [15], itu: [28], lat: 50.0, lon: 15.0)

        func resolve(_ callsign: String?) -> DxccEntity? {
            callsign?.hasPrefix("OK") == true ? Self.ok : nil
        }

        func entities() -> [DxccEntity] {
            [Self.ok]
        }
    }

    private static func qso(_ call: String = "OK1ABC") -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = 14_025_000
        q.mode = .cw
        q.serialSent = 12
        return q
    }

    /// Every optional service on.
    private static func fullContext() -> QsoLogPipeline.Context {
        QsoLogPipeline.Context(
            activeContestId: "cq-ww-cw-2026",
            operatorCall: "OK1XOE",
            dxcc: Lookup(),
            syncStationId: "station-2",
            reservedSerial: 12,
            simulatorActive: true,
            ritHz: 150,
            ritClearAfterLog: true,
            clubLogConfigured: true,
            broadcastActive: true,
            wsjtxActive: true,
            logToContest: true
        )
    }

    /// Free logging (no active contest, a Swift divergence from Kotlin's refusal): the QSO is stored and
    /// prepared as usual, with every local effect, but never published to the cluster and never taking the
    /// cluster's server serial.
    @Test func freeLoggingStoresTheQsoWithoutClusterEffects() {
        for contest in [nil, "", " ", "\u{00A0}"] as [String?] {
            var ctx = Self.fullContext()
            ctx.activeContestId = contest
            ctx.logToContest = false
            let (q, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: ctx)
            #expect(effects == [
                .persist, .bumpRevision, .addDupe, .appendRow, .refreshCount,
                .simulator, .clearRit, .clubLog, .plugin, .broadcast, .wsjtx,
            ], "\(String(describing: contest))")
            #expect(q.operator == "OK1XOE")
            #expect(q.dxccName == "Czech Republic")
        }
    }

    /// The entry window calls `contest.log` right after `state.log`, also in free logging.
    @Test func freeLoggingStillLogsIntoContestWhenAsked() {
        var ctx = Self.fullContext()
        ctx.activeContestId = nil
        let (_, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: true, context: ctx)
        #expect(effects == [.persist, .bumpRevision, .addDupe, .appendRow, .refreshCount, .contestLog])
    }

    @Test func effectOrderMatchesKotlin() {
        let (_, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: Self.fullContext())
        #expect(effects == [
            .persist, .bumpRevision, .addDupe, .appendRow, .consumeReservedSerial, .refreshCount, .publishInsert,
            .simulator, .clearRit, .clubLog, .plugin, .broadcast, .wsjtx, .contestLog,
        ])
    }

    @Test func importedQsoSkipsLiveEffects() {
        let (_, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: true, context: Self.fullContext())
        #expect(effects == [
            .persist, .bumpRevision, .addDupe, .appendRow, .consumeReservedSerial, .refreshCount, .publishInsert,
            .contestLog,
        ])
        let live: Set<String> = ["simulator", "clearRit", "clubLog", "plugin", "broadcast", "wsjtx"]
        #expect(effects.allSatisfy { !live.contains(String(describing: $0)) })
    }

    @Test func singleStationMinimum() {
        let ctx = QsoLogPipeline.Context(activeContestId: "x", operatorCall: "OK1XOE")
        let (q, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: ctx)
        #expect(effects == [.persist, .bumpRevision, .addDupe, .appendRow, .refreshCount, .plugin])
        #expect(q.stationId == "")
        #expect(q.dxccEntity == nil)
    }

    @Test func conditionsOfOptionalEffects() {
        var ctx = Self.fullContext()
        ctx.reservedSerial = 13 // another number than the QSO's
        ctx.ritHz = 0
        let (_, effects) = QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: ctx)
        #expect(!effects.contains(.consumeReservedSerial))
        #expect(!effects.contains(.clearRit))
        ctx.ritHz = -20
        ctx.ritClearAfterLog = false
        #expect(!QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: ctx).1.contains(.clearRit))
        ctx.ritClearAfterLog = true
        #expect(QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: ctx).1.contains(.clearRit))
        var noSerial = Self.qso()
        noSerial.serialSent = nil
        ctx.reservedSerial = 12
        #expect(!QsoLogPipeline.plan(qso: noSerial, isImported: false, context: ctx).1.contains(.consumeReservedSerial))
    }

    @Test func preparesTheQso() {
        let (q, _) = QsoLogPipeline.plan(qso: Self.qso(), isImported: false, context: Self.fullContext())
        #expect(q.operator == "OK1XOE")
        #expect(q.stationId == "station-2")
        #expect(q.dxccEntity == 503)
        #expect(q.dxccName == "Czech Republic")
        #expect(q.continent == "EU")
    }

    /// `qso.operator.isNullOrBlank()` (Kotlin: U+00A0 is blank too); an imported operator stays.
    @Test func operatorOnlyWhenBlank() {
        for (given, expected) in [("", "OK1XOE"), ("  ", "OK1XOE"), ("\u{00A0}", "OK1XOE"), ("OK2ZZ", "OK2ZZ")] {
            var source = Self.qso()
            source.operator = given
            let (q, _) = QsoLogPipeline.plan(qso: source, isImported: true, context: Self.fullContext())
            #expect(q.operator == expected, "\(given)")
        }
    }

    /// `fillDxcc` fills only what is missing.
    @Test func dxccOnlyFillsMissing() {
        var source = Self.qso()
        source.dxccName = "Kept"
        let (q, _) = QsoLogPipeline.plan(qso: source, isImported: false, context: Self.fullContext())
        #expect(q.dxccName == "Kept")
        #expect(q.dxccEntity == 503)
        let (unknown, _) = QsoLogPipeline.plan(qso: Self.qso("W1AW"), isImported: false, context: Self.fullContext())
        #expect(unknown.dxccEntity == nil)
    }
}
