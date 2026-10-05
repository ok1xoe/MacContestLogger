import Foundation
import MCLCore

// Development tool of the 20k measurement: writes a seeded synthetic CQ WW CW log
// (`SyntheticLog`) into a new logbook database with the contest row and `last_contest_id`, then measures the core
// work the app does over it: open, `findAll`, replay, sort by every key, search, the operating-rules statistics and
// 1,000 inserts through `LogbookMutations`. Measure with a release build:
//
//   swift run -c release mcl-synthlog <out.sqlite> --count 20000 --seed 1 --contest-data <dir>

let usage = """
Usage: mcl-synthlog <out.sqlite> --contest-data <dir> [--count N] [--seed N] [--start-epoch S] [--dxcc-dir <dir>]
                    [--no-measure]
  --contest-data <dir>  directory with contests/ and multipliers/ (required: the contest row and the replay)
  --count N             number of QSOs (default 20000)
  --seed N              generator seed (default 1)
  --start-epoch S       contest start in Unix seconds (default 1795824000 = 2026-11-28 00:00Z); the log spans 48 h
  --dxcc-dir <dir>      DXCC data (cty.dat / dxcc.json; default ~/dxcc-json, read only)
  --no-measure          only write the database
The output file must not exist.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct Arguments {
    var output: String?
    var contestData: String?
    var count = 20_000
    var seed: UInt64 = 1
    var startEpoch: Int64 = 1_795_824_000
    var dxccDir: String?
    var measure = true
}

func parseArguments() -> Arguments {
    var parsed = Arguments()
    let argv = Array(CommandLine.arguments.dropFirst())
    var index = 0
    func value(_ flag: String) -> String {
        index += 1
        guard index < argv.count else { fail("Missing value for \(flag)\n\(usage)") }
        return argv[index]
    }
    while index < argv.count {
        let arg: String = argv[index]
        switch arg {
        case "--contest-data": parsed.contestData = value(arg)
        case "--count":
            guard let count = Int(value(arg)), count >= 0 else { fail("--count: a number ≥ 0") }
            parsed.count = count
        case "--seed":
            guard let seed = UInt64(value(arg)) else { fail("--seed: a number") }
            parsed.seed = seed
        case "--start-epoch":
            guard let epoch = Int64(value(arg)) else { fail("--start-epoch: Unix seconds") }
            parsed.startEpoch = epoch
        case "--dxcc-dir": parsed.dxccDir = value(arg)
        case "--no-measure": parsed.measure = false
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            if arg.hasPrefix("--") || parsed.output != nil { fail("Unknown argument \(arg)\n\(usage)") }
            parsed.output = arg
        }
        index += 1
    }
    return parsed
}

/// Wall-clock milliseconds of `body`.
func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start: UInt64 = DispatchTime.now().uptimeNanoseconds
    let result: T = try body()
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    return (result, elapsed)
}

func report(_ label: String, _ milliseconds: Double, _ detail: String = "") {
    let padded: String = label.padding(toLength: 50, withPad: " ", startingAt: 0)
    let value: String = String(format: "%10.1f ms", milliseconds)
    print(padded + value + (detail.isEmpty ? "" : "  " + detail))
}

let arguments = parseArguments()
guard let outputPath = arguments.output, let contestDataPath = arguments.contestData else { fail(usage) }
let output = URL(fileURLWithPath: outputPath)
if FileManager.default.fileExists(atPath: output.path) {
    fail("\(output.path) exists; choose a new file")
}
let contestData = URL(fileURLWithPath: contestDataPath)
let home: URL = FileManager.default.homeDirectoryForCurrentUser
let dxccDir: String = arguments.dxccDir ?? home.appendingPathComponent("dxcc-json").path

// MARK: - write

let definitionId = "cq-ww-cw"
let contestsDir: URL = contestData.appendingPathComponent("contests")
guard let yaml = ContestRuntime.rawYaml(contestsDir: contestsDir, definitionId: definitionId) else {
    fail("No \(definitionId).yaml in \(contestsDir.path)")
}
var setup = ContestSetup()
setup.sentExchange = ["zone": "15"]
var station = StationConfig()
station.call = "OK1XOE"
// Only `toJSON` is used (the setup and station columns of the contest row); the file is never written.
let configStore = ConfigStore(file: output.appendingPathExtension("config.json"))

let (opening, writeMs): (ContestActivation.Opening, Double) = try timed {
    let repository = try LogbookRepository(url: output)
    defer { repository.close() }
    let store = try ContestStore(repository)
    let created = try ContestActivation.createContest(definitionId: definitionId, yaml: yaml, setup: setup,
                                                      station: station, configStore: configStore, store: store)
    let opening: ContestActivation.Opening
    switch created {
    case .success(let value): opening = value
    case .failure(let message): fail(message.czech)
    }
    try repository.metaSet("last_contest_id", opening.row.contestId)
    let start = Date(timeIntervalSince1970: TimeInterval(arguments.startEpoch))
    let qsos: [Qso] = SyntheticLog.generate(count: arguments.count, seed: arguments.seed,
                                            contestId: opening.row.contestId, start: start)
    try repository.connection.execute("BEGIN")
    for qso in qsos {
        var stored = qso
        try repository.insert(&stored)
    }
    try repository.connection.execute("COMMIT")
    return opening
}
let contestId: String = opening.row.contestId
print("Wrote \(arguments.count) QSOs of \(definitionId) (contest \(contestId)) to \(output.path)")
report("write (contest row + inserts in one transaction)", writeMs)
guard arguments.measure else { exit(0) }

// MARK: - measure

print("")
print("Core measurements (\(arguments.count) QSOs, one run each):")
let (service, openMs): (LogbookService, Double) = try timed {
    let service = LogbookService(repository: try LogbookRepository(url: output))
    service.activeContestId = contestId
    return service
}
report("open database", openMs)
let (all, findMs): ([Qso], Double) = try timed { try service.findAll() }
report("findAll (refresh)", findMs, "\(all.count) rows")
let (_, countMs): (Int, Double) = try timed { try service.count() }
report("count", countMs)

let environment = ContestEnvironment.load(dataRoot: contestData.path, dxccDir: dxccDir,
                                          fallbackDataRoot: contestData.path)
if let dxcc = environment.dxcc, let registry = environment.registry {
    func freshSession() -> ContestSession {
        ContestSession(definition: opening.definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
    }
    let (_, activationMs): ((), Double) = timed {
        ContestRuntime.replayLogged(ContestActivation.replayOrder(all), into: freshSession())
    }
    report("activation replay (replayOrder + replayLogged)", activationMs)
    let (outcome, replayMs): (ContestReplay.Outcome, Double) = timed { ContestReplay.replay(freshSession(), all) }
    let total: Int64 = (try? outcome.session.score().total) ?? -1
    let summary: String = "replayed \(outcome.replayed), skipped \(outcome.skipped), score \(total)"
    report("rescore (ContestReplay)", replayMs, summary)
    let (marks, marksMs): ([Int64: QsoMarks.Mark], Double) = timed { QsoMarks.compute(freshSession(), all) }
    let dupes: Int = marks.values.filter(\.dupe).count
    report("QsoMarks.compute (log table marks)", marksMs, "\(dupes) dupes")
} else {
    print("(no DXCC in \(dxccDir) or no multiplier sets: replay not measured)")
}

let keys: [(String, QsoSort.Key)] = [
    ("time", .time), ("call", .call), ("band", .band), ("mode", .mode), ("rstSent", .rstSent),
    ("rstRcvd", .rstRcvd), ("serialSent", .serialSent), ("serialRcvd", .serialRcvd), ("exchange", .exchange),
    ("note", .note),
]
for (name, key) in keys {
    for ascending in [true, false] {
        let (_, sortMs): ([Qso], Double) = timed { QsoSort.sort(all, key: key, ascending: ascending) }
        report("QsoSort " + name + (ascending ? " ▲" : " ▼"), sortMs)
    }
}
for query in ["dl", "call:OK1", "nr:12", "ex:14", "band:20m", "599", "zzzz"] {
    let (found, searchMs): ([Qso], Double) = timed { QsoSearch.filter(all, query) }
    report("QsoSearch \"" + query + "\"", searchMs, "\(found.count) found")
}

// The operating-rules gate of a contest submit (`EntryModel.operatingViolation`): the station filter, the
// statistics over the whole log and the check (MULTI-OP / ONE: 10 minutes per band).
let rules = OperatingRules.resolve(opening.definition.operating, ["OPERATOR": "MULTI-OP", "TRANSMITTER": "ONE"])
let (_, statsMs): (String?, Double) = timed {
    let mine: [Qso] = all.filter { KotlinStrings.isBlank($0.stationId) || $0.stationId == "" }
    let stats = ContestStats.of(mine)
    return OperatingGuard.check(stats, rules?.bandChange, .m20, JavaInstant(date: Date()), .none, false)
}
report("operating rules (filter + ContestStats + check)", statsMs)

// The entry window's suggestions per keystroke (`SuggestionsModel`): the log call list, worked-before, Check partial
// and N+1 over the log (no master.scp).
let probeCall: String = all.first(where: { $0.call.utf16.count >= 4 })?.call ?? "DL1ABC"
let (logCalls, logCallsMs): ([String], Double) = timed {
    var seen = Set<[UInt16]>()
    return all.map(\.call).filter { seen.insert(Array($0.utf16)).inserted }
}
report("log call list (distinct calls)", logCallsMs, "\(logCalls.count) calls")
let bandOrder: [String] = (opening.definition.bands ?? []).compactMap { $0 }
let (worked, workedMs): (WorkedBefore.Result?, Double) = timed {
    EntrySuggestions.workedBefore(qsos: all, call: probeCall, contestBandOrder: bandOrder)
}
report("worked-before (WorkedBefore.of)", workedMs, "\(worked?.count ?? 0) worked")
let partialQuery = String(probeCall.prefix(3))
let (partial, partialMs): ([PartialCheck.Suggestion], Double) = timed {
    EntrySuggestions.partial(query: partialQuery, logCalls: logCalls, spotCalls: [], scp: .empty())
}
report("check partial over the log", partialMs, "\(partial.count) suggestions")
let (nPlusOne, nPlusOneMs): ([String], Double) = timed {
    EntrySuggestions.nPlusOne(query: probeCall, logCalls: logCalls, spotCalls: [], scp: .empty())
}
report("N+1 over the log", nPlusOneMs, "\(nPlusOne.count) calls")

// 1,000 QSOs logged one by one like the app: insert + count per QSO, the dupe index updated after each.
var mutations = LogbookMutations(existing: all)
let extraStart = Date(timeIntervalSince1970: TimeInterval(arguments.startEpoch + 48 * 3_600))
let extra: [Qso] = SyntheticLog.generate(count: 1_000, seed: arguments.seed &+ 1, contestId: contestId,
                                         start: extraStart)
var worst: Double = 0
var inserted: [Qso] = []
let (_, insertMs): ((), Double) = try timed {
    for qso in extra {
        let (stored, oneMs): (Qso, Double) = try timed {
            let stored: Qso = try LogbookMutations.insert(qso, into: service)
            _ = try service.count()
            return stored
        }
        worst = max(worst, oneMs)
        mutations.didInsert(stored)
        inserted.append(stored)
    }
}
report("1,000 inserts (insert + count, dupe index)", insertMs,
       String(format: "%.2f ms per QSO, worst %.2f ms", insertMs / 1_000, worst))

// The main-thread work of a contest submit after the insert — the operating-rules statistics extended by
// `ContestStats.appending` and the log marks extended by `QsoMarksTracker.append` — over the same 1,000 QSOs.
var stats = ContestStats.of(all)
var statsWorst: Double = 0
var statsFallbacks = 0
let (_, appendStatsMs): ((), Double) = timed {
    for qso in inserted {
        let (next, oneMs): (ContestStats?, Double) = timed { stats.appending(qso) }
        statsWorst = max(statsWorst, oneMs)
        if let next {
            stats = next
        } else {
            statsFallbacks += 1
        }
    }
}
report("1,000 ContestStats.appending (operating rules)", appendStatsMs,
       String(format: "%.3f ms per QSO, worst %.3f ms, %d refused", appendStatsMs / 1_000, statsWorst, statsFallbacks))
if let dxcc = environment.dxcc, let registry = environment.registry {
    func trackerSession() -> ContestSession {
        ContestSession(definition: opening.definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
    }
    let (tracker, recomputeMs): (QsoMarksTracker, Double) = timed {
        QsoMarksTracker.recomputed(fresh: trackerSession(), qsos: all)
    }
    report("QsoMarksTracker.recomputed (fallback)", recomputeMs)
    var marksWorst: Double = 0
    var marksRefused = 0
    let (_, appendMarksMs): ((), Double) = timed {
        for qso in inserted {
            let (appended, oneMs): (Bool, Double) = timed { tracker.append(qso) }
            marksWorst = max(marksWorst, oneMs)
            if !appended {
                marksRefused += 1
            }
        }
    }
    report("1,000 QsoMarksTracker.append (log marks)", appendMarksMs,
           String(format: "%.3f ms per QSO, worst %.3f ms, %d refused", appendMarksMs / 1_000, marksWorst, marksRefused))
}
service.repository.close()
