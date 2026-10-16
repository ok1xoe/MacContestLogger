import AppKit
import Foundation
@testable import MCLAppModel
import MCLCore

/// The demo station of the user guide's screenshots: an app model over a temporary data directory (never the user's)
/// with the repository's contest definitions and DXCC snapshot, the inert hardware and network ports (no rig, serial
/// port, audio or socket is opened), a fixed clock, a CQ WW CW log of a few dozen QSOs, a rig tuned on 20 m and
/// cluster spots. Everything is synthetic and the same on every run.
@MainActor
final class ShotDemo {

    /// The fixed start of the demo contest: 2026-10-24 00:00 UTC (CQ WW SSB weekend; the CW log is just a sample).
    static let start = Date(timeIntervalSince1970: 1_792_800_000)

    /// The repository root (from this file's path).
    nonisolated static let repository: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The clock of the model, moved by hand while the log is filled.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var date: Date { lock.withLock { value } }
        func set(_ date: Date) { lock.withLock { value = date } }
    }

    /// A clock whose short delays (the rescore and score window debounces, up to a second) end on the next main-queue
    /// turn, so settling the models never waits for time; longer ones (periodic ticks: clocks, polls, the night
    /// layer) never fire, so nothing changes while a window is drawn.
    final class ImmediateClock: RescoreClock {
        final class Timer: RescoreTimer {
            var cancelled = false
            func cancel() { cancelled = true }
        }

        func schedule(afterMilliseconds delay: Int, _ fire: @escaping @MainActor @Sendable () -> Void) -> any RescoreTimer {
            let timer = Timer()
            guard delay <= 1_000 else { return timer }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if !timer.cancelled {
                        fire()
                    }
                }
            }
            return timer
        }
    }

    /// A definition fetcher that never reaches the network.
    struct OfflineFetcher: DataFetcher {
        func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
            throw URLError(.notConnectedToInternet)
        }
    }

    let dir: URL
    let model: AppModel
    let clock: Clock
    let language: String

    private init(dir: URL, model: AppModel, clock: Clock, language: String) {
        self.dir = dir
        self.model = model
        self.clock = clock
        self.language = language
    }

    /// Removes the temporary data directory.
    func remove() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The demo app in `language` (`cs` or `en`) with the demo log, rig state and spots.
    static func make(language: String) async throws -> ShotDemo {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-shots-" + UUID().uuidString)
        let dataDir: URL = dir.appendingPathComponent("data")
        let dxccDir: URL = dir.appendingPathComponent("dxcc-json")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dxccDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repository.appendingPathComponent("Tests/MCLCoreTests/Fixtures/scorecheck-reference/dxcc-json/dxcc.json"),
            to: dxccDir.appendingPathComponent("dxcc.json"))
        var config = AppConfig()
        config.contestDataDir = repository.appendingPathComponent("contest-data").path
        config.language = language
        config.station.call = "OK1XOE"
        config.station.name = "Tom"
        config.station.gridSquare = "JO70FD"
        try ConfigWriter.writeFile(config, to: dataDir.appendingPathComponent("config.json"))
        let clock = Clock(start)
        var environment = AppModel.Environment(
            dataDir: dataDir, dxccDir: dxccDir, decimalSeparator: language == "cs" ? "," : ".",
            rescoreClock: ImmediateClock(), geometryClock: MainQueueRescoreClock(),
            now: { clock.date }, appVersion: "1.0.0",
            definitionSource: DataToolsModel.DefinitionSource(fetcher: OfflineFetcher()))
        environment.toolClock = ImmediateClock()
        environment.hardware = .inert
        environment.network = .inert
        let model: AppModel = try await AppModel.bootstrap(environment)
        let demo = ShotDemo(dir: dir, model: model, clock: clock, language: language)
        try await demo.fill()
        return demo
    }

    /// A QSO of the demo log: minutes after the start, the frequency (kHz), the call and the CQ zone.
    struct Contact {
        let minute: Int
        let kHz: String
        let call: String
        let zone: String
    }

    /// The demo log: three bands, a run with a pause, a few multipliers per band.
    static let contacts: [Contact] = {
        let calls: [(String, String)] = [
            ("DL1ABC", "14"), ("OM3RM", "15"), ("SP9KDA", "15"), ("HA8EK", "15"), ("G4BUO", "14"), ("F5IN", "14"),
            ("I2WIJ", "15"), ("EA5RM", "14"), ("OH2BH", "15"), ("SM5AQD", "14"), ("LZ1PM", "20"), ("YO3APJ", "20"),
            ("UA3AB", "16"), ("9A1A", "15"), ("S50A", "15"), ("OE1A", "15"), ("HB9ARF", "14"), ("PA3AAV", "14"),
            ("ON4UN", "14"), ("OZ1ACB", "14"), ("LY2ZZ", "15"), ("YL2KL", "15"), ("ES5TV", "15"), ("W1AW", "5"),
            ("K3LR", "5"), ("VE3EJ", "4"), ("JA1ZLO", "25"), ("4X6TT", "20"), ("CN8KD", "33"), ("EA8AH", "33"),
            ("PY2YU", "11"), ("LU1FAM", "13"), ("ZS6EZ", "38"), ("VK2GR", "30"), ("UN9L", "17"), ("R9DX", "17"),
            ("TA2IJ", "20"), ("SV1DPJ", "20"), ("CT1BOH", "14"), ("EI7M", "14"),
        ]
        var out: [Contact] = []
        for (index, entry) in calls.enumerated() {
            // 20 m, 40 m and 15 m in turn.
            let kHz: Int = [14_010 + index * 2, 7_005 + index, 21_015 + index * 2][index % 3]
            // A break of an hour after the first twenty.
            let minute: Int = index < 20 ? index * 3 : 120 + index * 2
            out.append(Contact(minute: minute, kHz: String(kHz), call: entry.0, zone: entry.1))
        }
        return out
    }()

    /// The spots of the band map and the cluster window (20 m around the tuned frequency).
    static let spots: [(call: String, kHz: Double, spotter: String)] = [
        ("DL1ABC", 14_012.0, "OK1RR"), ("K1LZ", 14_021.5, "DL8DYL"), ("VK2GR", 14_028.1, "OK2PVF"),
        ("JA1ZLO", 14_033.0, "OH6BG"), ("PY2YU", 14_038.4, "SP7GIQ"), ("ZS6EZ", 14_041.2, "G3SXW"),
        ("W1AW", 14_045.0, "OK1RR"), ("9A1A", 14_051.7, "S53M"), ("UN9L", 14_056.3, "RA3CW"),
        ("CN8KD", 14_060.0, "EA5RM"), ("4X6TT", 14_064.9, "OK1XOE"), ("EA8AH", 14_070.2, "CT1BOH"),
    ]

    /// A text command typed in the call field.
    func enter(_ command: String) async {
        model.entry.callChanged(command)
        model.entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        await model.entry.settle()
    }

    /// Logs the demo QSOs through the entry window (as typed), tunes the rig, adds the spots.
    func fill() async throws {
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        let started: Bool = await model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        guard started else { throw ShotError.demo("CQ WW CW does not start: \(model.status.message)") }
        let entry: EntryModel = model.entry
        // The QSO times come from the time field of post-contest entry (a live QSO takes the wall clock).
        await enter("POSTCONTEST")
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd HHmm"
        for contact in Self.contacts {
            let at: Date = Self.start.addingTimeInterval(TimeInterval(contact.minute * 60))
            clock.set(at)
            entry.paperTime = format.string(from: at)
            entry.setFrequency(contact.kHz)
            entry.callChanged(contact.call)
            entry.editContestField("zone", contact.zone)
            entry.submit()
            await entry.settle()
        }
        await model.logbook.settle()
        await enter("NOPOSTCONTEST")
        clock.set(Self.start.addingTimeInterval(TimeInterval(3 * 3_600)))
        model.rig.qsy(14_025_000)
        for spot in Self.spots {
            model.dxCluster.spots.add(DxSpot(spotter: spot.spotter, freqHz: Int(spot.kHz * 1_000), dxCall: spot.call,
                                             comment: "CW"))
        }
        await runMainQueue()
    }
}

enum ShotError: Error, CustomStringConvertible {
    case demo(String)
    case render(String)

    var description: String {
        switch self {
        case .demo(let text): return "demo: " + text
        case .render(let text): return "render: " + text
        }
    }
}

/// One turn of the main queue (what was dispatched before runs).
@MainActor
func runMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
