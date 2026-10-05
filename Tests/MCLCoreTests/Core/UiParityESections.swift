import Foundation
import Testing
@testable import MCLCore

/// Swift side of the Java parity suite (maintainer-only probe, fixture `e`): replays the input rows of `ui-e-java.json.gz` against the
/// rig and keying core:
///
/// - `cat.STATUS` — `CatStatusLine.format`;
/// - `rig.TUNE` — `TuningState` (`qsy`, `tuneTo`, `updateTuned`, `returnToPrevious`, `stepBand`, `tuneStep`,
///   `wheel`, `bandsForStepping`, `tuneStepHz`), `BandStepping.target` (the product's band step with its QSY
///   rounding), `RitState`, `RunModeTracker` and `RigTexts`, composed in the order of `RigModel`, `EntryModel` and
///   `OperatingModel` (`Radio` below);
/// - `vfo.SWITCH` — `VfoState` (`syncRadioMode`, `toggleStereo`, `activeCatIndex`) and the product composition
///   `VfoActivation.apply` that `RigModel.activateVfo` calls;
/// - `wf.HEAT` — `WaterfallPalette.heat` and `WaterfallPixels.render`;
/// - `rec.SEG` — `ContestRecorder.segment` and `RecordingPlayback.read` over the same synthetic hour files, written
///   into a temporary directory.
///
/// The rig of a "connected" CAT is the generator's in-memory stub: the calls it receives (`F` frequency, `M` mode, `R`
/// RIT, `V` VFO, prefixed by the rig number) are an output, a failing `setRit`/`selectVfo` comes from the row. Calls
/// with a frequency ≤ 0 are not compared (Swift sends nothing to CAT, Kotlin sends the value).
enum UiParityESections {

    typealias Entry = JavaYamlParityTests.ReferenceFile
    typealias Rows = [(String, [String])]
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["cat.STATUS", "rig.TUNE", "vfo.SWITCH", "wf.HEAT", "rec.SEG"]

    // MARK: - replay

    final class Ctx {
        var radios: [String: Radio] = [:]
        var work: URL?
    }

    static func replay(_ java: Entry) throws -> Entry {
        let ctx = Ctx()
        defer {
            if let work = ctx.work {
                try? FileManager.default.removeItem(at: work)
            }
        }
        var lines: [String] = []
        lines.reserveCapacity(java.lines.count)
        for line in java.lines {
            let fields: [String] = JavaEngineParityTests.fields(line)
            guard fields.count >= 2, fields[1] == "in" else { continue }
            lines.append(line)
            let inputs: [String] = Array(fields.dropFirst(2))
            do {
                for (outPath, out) in try compute(java.relative, fields[0], inputs, ctx) {
                    lines.append(F.line(outPath, "out", out))
                }
            } catch {
                lines.append(F.line(fields[0], "out", ["SWIFT ERROR", String(describing: error)]))
            }
        }
        let sum: String = F.checksum(definition: nil, registry: "", lines: lines)
        return Entry(relative: java.relative, sha256: sum, lines: lines)
    }

    static func replayAll(_ reference: [Entry]) async throws -> [Entry] {
        try await withThrowingTaskGroup(of: (Int, Entry).self) { group in
            for (index, entry) in reference.enumerated() {
                group.addTask {
                    let replayed = try await JavaNetParityFixture.onGateThread(entry.relative) {
                        try replay(entry)
                    }
                    return (index, replayed)
                }
            }
            var results = [Entry?](repeating: nil, count: reference.count)
            for try await (index, entry) in group {
                results[index] = entry
            }
            return results.compactMap { $0 }
        }
    }

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "cat.STATUS": return try statusRow(path, f)
        case "rig.TUNE": return try tuneRow(path, f, ctx)
        case "vfo.SWITCH": return try vfoRow(path, f, ctx)
        case "wf.HEAT": return try heatRow(path, f)
        case "rec.SEG": return try segmentRow(path, f, ctx)
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    static func text(_ field: String) -> String {
        X.text(field) ?? ""
    }

    static func int64(_ field: String) throws -> Int64 {
        guard let value = Int64(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func int(_ field: String) throws -> Int {
        guard let value = Int(field) else { throw X.Malformed(text: field) }
        return value
    }

    static func mode(_ field: String) throws -> Mode {
        guard let value = Mode(rawValue: field) else { throw X.Malformed(text: "mode \(field)") }
        return value
    }

    static func band(_ field: String) throws -> Band? {
        if field == "~" { return nil }
        guard let value = Band.from(adif: field) else { throw X.Malformed(text: "band \(field)") }
        return value
    }

    static func bandList(_ bands: [Band]) -> String {
        bands.map(\.adif).joined(separator: " ")
    }

    // MARK: - cat.STATUS

    static func statusRow(_ path: String, _ f: [String]) throws -> Rows {
        guard f.count == 3 else { throw X.Malformed(text: path) }
        let mode: Mode? = f[1] == "~" ? nil : try Self.mode(f[1])
        let state = RigState(freqHz: try int64(f[0]), mode: mode, rawMode: text(f[2]), passband: 0)
        return [(path, [F.tx(CatStatusLine.format(state))])]
    }

    // MARK: - the rig, tuning and VFO composition

    /// The state `RigModel` + `OperatingModel` + the entry window keep for one run, with the generator's rig stub.
    final class Radio {
        var config = AppConfig()
        var tuning = TuningState()
        var rit = RitState()
        var vfo: VfoState
        let tracker = RunModeTracker()
        var runMode: RunMode = .searchAndPounce
        var connected: [Bool]
        var stepping: [Band] = []
        var focusRequest: Int?
        var status: EntryStatus?
        var calls: [String] = []
        /// The failure message of the rig for this step (`nil` = success).
        var failure: String?

        init(radioMode: String, connected: [Bool]) {
            config.radioMode = radioMode
            vfo = VfoState(radioMode: config.radioMode)
            self.connected = connected
        }

        var activeRig: Int {
            vfo.activeCatIndex
        }

        func record(_ call: String) {
            calls.append(String(activeRig + 1) + ":" + call)
        }

        /// `RigModel.qsy` (nothing to CAT for ≤ 0) and the mode after it.
        func qsy(_ hz: Int64, mode: Mode?) {
            let effect: TuneEffect = tuning.qsy(hz)
            guard let rigHz = effect.rig, connected[activeRig] else { return }
            record("F" + String(rigHz))
            if let mode {
                record("M" + mode.rawValue + "@" + String(rigHz))
            }
        }

        /// `RigModel.tuneTo`.
        func tuneTo(_ hz: Int64) {
            guard let effect = tuning.tuneTo(hz), let rigHz = effect.rig, connected[activeRig] else { return }
            record("F" + String(rigHz))
        }

        /// `RigModel.returnToPrevious`.
        func returnToPrevious() {
            guard tuning.previousFreqHz > 0 else {
                status = RigTexts.noPreviousFrequency
                return
            }
            qsy(tuning.previousFreqHz, mode: nil)
        }

        /// `OperatingModel.jumpToCqFrequency` + the QSY of `EntryModel.jumpToCqFrequency`.
        func jumpToCq(_ band: Band?) {
            guard let cq = tracker.cqFrequency(band) else {
                status = RigTexts.noCqOnBand(band)
                return
            }
            runMode = .run
            qsy(Int64(cq), mode: nil)
        }

        func tuneStepHz(_ mode: Mode) -> Int64 {
            TuningState.tuneStepHz(mode, cwHz: config.tuneStepCwHz, ssbHz: config.tuneStepSsbHz)
        }

        /// `RigModel.setRit`.
        func setRit(_ offsetHz: Int) {
            let value: Int = RitState.clamp(offsetHz)
            guard connected[activeRig] else {
                status = RigTexts.ritNeedsCat
                return
            }
            if let failure {
                status = RigTexts.ritFailure(failure)
                return
            }
            record("R" + String(value))
            rit.applied(value)
            status = RigTexts.rit(value)
        }

        /// `EntryModel.stepBand` → `EntryModel.qsy(toKHz:mode:)`: the product's `BandStepping.target` (the kHz of
        /// the field and the rounded Hz of the QSY).
        func stepBand(_ direction: Int, mode: Mode, band: Band?) -> String {
            guard let target = BandStepping.target(tuning: tuning, band: band, mode: mode, allowed: stepping,
                                                   direction: direction) else {
                return "~"
            }
            let field: String = FrequencyText.formatKHz(target.kHz)
            qsy(target.hz, mode: mode)
            return F.tx(field)
        }

        /// `EntryModel.tuneStep`.
        func tuneStep(_ direction: Int, mode: Mode, fieldHz: Int64) -> String {
            guard let next = TuningState.tuneStep(fieldHz: fieldHz, mode: mode, direction: direction,
                                                  cwHz: config.tuneStepCwHz, ssbHz: config.tuneStepSsbHz) else {
                return "~"
            }
            tuneTo(next)
            return F.tx(CatStatusLine.fieldText(next))
        }

        /// `EntryModel.wheel` (the active window).
        func wheel(_ direction: Int, alt: Bool, ctrl: Bool, mode: Mode, fieldHz: Int64) -> String {
            guard let next = TuningState.wheel(fieldHz: fieldHz, mode: mode, direction: direction, alt: alt,
                                               ctrl: ctrl) else {
                return "~"
            }
            tuneTo(next)
            return F.tx(CatStatusLine.fieldText(next))
        }

        /// `RigModel.activateVfo`: the product's `VfoActivation.apply` (the OTRSP controller is never open in the
        /// gate); only the CAT half (`selectVfo` on the stub rig) is the gate's.
        func activate(_ index: Int, force: Bool) {
            guard let outcome = VfoActivation.apply(&vfo, &tuning, index: index, force: force,
                                                    hasOtrsp: false) else { return }
            switch outcome.hardware {
            case .otrspFocus:
                status = outcome.status
            case .selectVfo(let b):
                guard connected[activeRig] else { return }
                if let failure {
                    status = RigTexts.so2vFailure(failure)
                    return
                }
                record("V" + (b ? "B" : "A"))
                status = RigTexts.activeVfo(b: b)
            }
        }

        /// `RigModel.syncRadioModeFromConfig` (the OTRSP port is blank in every row).
        func syncRadioMode(_ mode: String, otrspPort: String) throws {
            config.radioMode = mode
            config.otrspPort = otrspPort
            guard KotlinStrings.isBlank(config.otrspPort) else { throw X.Malformed(text: "an OTRSP port") }
            if vfo.syncRadioMode(config.radioMode) {
                activate(0, force: true)
            }
        }

        func lastOnBand() -> String {
            Band.javaV111Cases.compactMap { band in
                tuning.lastFrequency(on: band).map { band.adif + "=" + String($0) }
            }.joined(separator: ";")
        }

        func takeCalls() -> String {
            defer { calls.removeAll() }
            return calls.joined(separator: ";")
        }

        func statusText() -> String {
            F.tx(status?.czech ?? "")
        }
    }

    // MARK: - rig.TUNE

    static func tuneRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let parts: [Substring] = path.split(separator: "/")
        if parts.count == 2 {
            guard f.count == 4 else { throw X.Malformed(text: path) }
            let radio = Radio(radioMode: "SO1V", connected: [f[2] == "1", false])
            radio.config.tuneStepCwHz = try int(f[0])
            radio.config.tuneStepSsbHz = try int(f[1])
            let grid: [Band]? = f[3] == "-" ? nil : try f[3].split(separator: " ").map { field in
                guard let band = try band(String(field)) else { throw X.Malformed(text: f[3]) }
                return band
            }
            radio.stepping = TuningState.bandsForStepping(contestBands: grid)
            ctx.radios[path] = radio
            return [(path, [bandList(radio.stepping)])]
        }
        guard parts.count == 3, let radio = ctx.radios[parts[0] + "/" + parts[1]], f.count >= 3 else {
            throw X.Malformed(text: path)
        }
        radio.status = nil
        radio.failure = f[f.count - 2] == "ok" ? nil : text(f[f.count - 1])
        let field: String = try tuneStep(radio, f)
        let out: [String] = [
            String(radio.tuning.tunedFreqHz), String(radio.tuning.previousFreqHz), radio.lastOnBand(),
            String(radio.rit.ritHz), radio.runMode.rawValue, radio.statusText(), field, radio.takeCalls(),
        ]
        return [(path, out)]
    }

    /// One step of `rig.TUNE`; returns the field text of an entry-window operation (`~` = none).
    static func tuneStep(_ radio: Radio, _ f: [String]) throws -> String {
        switch f[0] {
        case "Q":
            radio.qsy(try int64(f[1]), mode: f[2] == "~" ? nil : try mode(f[2]))
        case "T":
            radio.tuneTo(try int64(f[1]))
        case "U":
            _ = radio.tuning.updateTuned(try int64(f[1]))
        case "P":
            radio.returnToPrevious()
        case "C":
            radio.jumpToCq(try band(f[1]))
        case "S":
            radio.runMode = radio.tracker.onCq(Int(clamping: try int64(f[1])))
        case "R":
            radio.setRit(try int(f[1]))
        case "r":
            let step: Int64 = radio.tuneStepHz(try mode(f[2]))
            radio.setRit(radio.rit.step(direction: try int(f[1]), stepHz: step))
        case "B":
            return radio.stepBand(try int(f[1]), mode: try mode(f[2]), band: try band(f[3]))
        case "A":
            return radio.tuneStep(try int(f[1]), mode: try mode(f[2]), fieldHz: try int64(f[3]))
        case "W":
            return radio.wheel(try int(f[1]), alt: f[2] == "1", ctrl: f[3] == "1", mode: try mode(f[4]),
                               fieldHz: try int64(f[5]))
        default:
            throw X.Malformed(text: "operation \(f[0])")
        }
        return "~"
    }

    // MARK: - vfo.SWITCH

    static func vfoRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let parts: [Substring] = path.split(separator: "/")
        if parts.count == 2 {
            guard f.count == 3 else { throw X.Malformed(text: path) }
            let radio = Radio(radioMode: text(f[0]), connected: [f[1] == "1", f[2] == "1"])
            ctx.radios[path] = radio
            return [(path, vfoOutputs(radio))]
        }
        guard parts.count == 3, let radio = ctx.radios[parts[0] + "/" + parts[1]], f.count >= 3 else {
            throw X.Malformed(text: path)
        }
        radio.status = nil
        radio.failure = f[f.count - 2] == "ok" ? nil : text(f[f.count - 1])
        switch f[0] {
        case "M":
            try radio.syncRadioMode(text(f[1]), otrspPort: text(f[2]))
        case "A":
            radio.activate(try int(f[1]), force: f[2] == "1")
        case "F":
            let index: Int = try int(f[1])
            radio.activate(index, force: false)
            radio.focusRequest = index
        case "X":
            radio.status = RigTexts.so2rStereo(radio.vfo.toggleStereo())
        case "Q":
            radio.qsy(try int64(f[1]), mode: nil)
        case "U":
            _ = radio.tuning.updateTuned(try int64(f[1]))
        default:
            throw X.Malformed(text: "operation \(f[0])")
        }
        return [(path, vfoOutputs(radio))]
    }

    static func vfoOutputs(_ radio: Radio) -> [String] {
        let v: VfoState = radio.vfo
        let bits: String = [v.so2v, v.so2r, v.stereo, v.twoEntryWindows].map { $0 ? "1" : "0" }.joined()
        return [
            String(v.activeVfo), String(v.vfoFreq[0]), String(v.vfoFreq[1]), String(radio.tuning.tunedFreqHz), bits,
            radio.focusRequest.map { String($0) } ?? "~", radio.statusText(), radio.takeCalls(),
        ]
    }

    // MARK: - wf.HEAT

    static func heatRow(_ path: String, _ f: [String]) throws -> Rows {
        if path.hasPrefix("h/") {
            guard f.count == 1, let bits = UInt32(f[0], radix: 16) else { throw X.Malformed(text: path) }
            return [(path, [String(WaterfallPalette.heat(Float(bitPattern: bits)), radix: 16)])]
        }
        guard f.count == 3 else { throw X.Malformed(text: path) }
        let count: Int = try int(f[0])
        let width: Int = try int(f[1])
        let rows: [[Float]] = try floatRows(f[2], count: count, width: width)
        guard let image = WaterfallPixels.render(rows: rows) else { return [(path, ["~"])] }
        var digest: [UInt8] = []
        digest.reserveCapacity(image.pixels.count * 4)
        for pixel in image.pixels {
            digest.append(contentsOf: [UInt8(pixel >> 24 & 0xFF), UInt8(pixel >> 16 & 0xFF),
                                       UInt8(pixel >> 8 & 0xFF), UInt8(pixel & 0xFF)])
        }
        var out: Rows = [(path, [String(image.width), String(image.height),
                                 JavaYamlParityTests.sha256Hex(Data(digest))])]
        guard image.width <= 64 else { return out }
        for y in 0..<count {
            let row: ArraySlice<UInt32> = image.pixels[(y * image.width)..<((y + 1) * image.width)]
            out.append((path + "/" + String(format: "%03d", y), [row.map(hex6).joined()]))
        }
        return out
    }

    static func hex6(_ pixel: UInt32) -> String {
        let digits = String(pixel, radix: 16)
        return String(repeating: "0", count: Swift.max(0, 6 - digits.count)) + digits
    }

    static func floatRows(_ hex: String, count: Int, width: Int) throws -> [[Float]] {
        let units: [UInt8] = Array(hex.utf8)
        guard units.count == count * width * 8 else { throw X.Malformed(text: "rows \(count)×\(width)") }
        var rows: [[Float]] = []
        rows.reserveCapacity(count)
        for y in 0..<count {
            var row: [Float] = []
            row.reserveCapacity(width)
            for x in 0..<width {
                let start: Int = (y * width + x) * 8
                guard let bits = UInt32(String(decoding: units[start..<(start + 8)], as: UTF8.self), radix: 16) else {
                    throw X.Malformed(text: "row \(y)")
                }
                row.append(Float(bitPattern: bits))
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - rec.SEG

    static let hourMillis: Int64 = 3_600_000
    /// 2026-10-02 00:00 UTC.
    static let baseMillis: Int64 = 1_790_899_200_000

    /// Byte `p` of a synthetic recording file (the generator's `fileByte`).
    static func fileByte(_ p: Int64, salt: Int64) -> UInt8 {
        UInt8(truncatingIfNeeded: (p &* 131 &+ salt &* 7 &+ (p >> 8)) & 0xFF)
    }

    static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    static func segmentRow(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        guard let count = f.first.flatMap({ Int($0) }), f.count == 1 + count * 3 + 3 else {
            throw X.Malformed(text: path)
        }
        let manager = FileManager.default
        if ctx.work == nil {
            let work: URL = manager.temporaryDirectory.appendingPathComponent("ui-e-gate-" + UUID().uuidString)
            try manager.createDirectory(at: work, withIntermediateDirectories: true)
            ctx.work = work
        }
        guard let work = ctx.work else { throw X.Malformed(text: path) }
        let dir: URL = work.appendingPathComponent(path.replacingOccurrences(of: "/", with: "-"))
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: dir) }
        let recorder = ContestRecorder(dir: try JavaPath(dir.path), sampleRate: 12_000)
        for i in 0..<count {
            let hour: Int64 = try int64(f[1 + i * 3])
            let length: Int64 = try int64(f[2 + i * 3])
            let salt: Int64 = try int64(f[3 + i * 3])
            let file: JavaPath = recorder.fileFor(date(baseMillis + hour * hourMillis))
            var bytes = [UInt8](repeating: 0, count: Int(length))
            for p in 0..<bytes.count {
                bytes[p] = fileByte(Int64(p), salt: salt)
            }
            try Data(bytes).write(to: URL(fileURLWithPath: file.description))
        }
        let millis: Int64 = try int64(f[1 + count * 3])
        let before = Int32(try int(f[2 + count * 3]))
        let after = Int32(try int(f[3 + count * 3]))
        guard let segment = recorder.segment(qsoTime: date(millis), beforeSec: before, afterSec: after) else {
            return [(path, ["~"])]
        }
        let name: String = segment.file.description.split(separator: "/").last.map(String.init) ?? ""
        var out: [String] = [F.tx(name), String(segment.offsetBytes), String(segment.lengthBytes)]
        do {
            let played: [UInt8] = try RecordingPlayback.read(segment: segment)
            out.append(String(played.count))
            out.append(JavaYamlParityTests.sha256Hex(Data(played)))
        } catch {
            out.append(F.tx("THROW " + String(describing: error)))
        }
        return [(path, out)]
    }
}
