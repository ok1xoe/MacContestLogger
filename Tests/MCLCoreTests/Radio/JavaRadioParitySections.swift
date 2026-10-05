import Foundation
import Testing
@testable import MCLCore

/// Items of the logic arm of the Java parity suite — each function mirrors the same-named method of
/// a maintainer-only probe (row order, output format), takes inputs from the reference
/// (`Inputs`) and computes its own file fingerprints itself.
enum JavaRadioParitySections {

    typealias F = JavaRadioParityFixture
    typealias Entry = F.Entry

    /// Data shared by items: corpus rows and the reference (DSP compares dB with a tolerance against Java rows).
    struct Context: Sendable {
        let corpus: [String]
        let reference: [String: Entry]
    }

    static let names: [String] = [
        "hamlib-modes", "mode-control", "cw-builder", "cut-style", "split", "frequency-steps", "antenna",
        "band-notes", "transverter", "audio-to-rf", "voice", "mac-speech", "rx-text", "text-tokens",
        "recent-calls", "xmlrpc", "rig-list", "rig-model-filter", "serial-params", "normalize-device",
        "rotator", "otrsp", "edge-detector", "contest-recorder", "to-samples", "dsp",
    ]

    /// Corpus markers per item (`new Sec(name, tags…)`).
    static let corpusTags: [String: [String]] = [
        "hamlib-modes": ["hm.mode"], "cw-builder": ["cw.t"], "split": ["split.c"],
        "antenna": ["ant.bands", "ant.sector"],
        "voice": ["vmp.exists", "vmp.plan", "vmp.call", "vmp.phonetic", "vmp.tts", "vmp.expand", "vmp.record", "vmp.dir"],
        "mac-speech": ["vmp.voice", "vmp.text"], "xmlrpc": ["xr.value", "xr.doc"], "rig-list": ["rl.edge"],
        "rig-model-filter": ["rmf.model", "rmf.query"], "normalize-device": ["pm.device"], "rotator": ["rot.name"],
    ]

    static func run(_ name: String, _ context: Context) throws -> Entry {
        let reference: Entry = context.reference[name] ?? Entry(relative: name, sha256: "", lines: [])
        var b = F.Builder(name, F.Inputs(reference))
        if let tags = corpusTags[name] {
            b.own("/corpus", [F.corpusDigest(context.corpus, tags)])
        }
        switch name {
        case "hamlib-modes": hamlibModes(&b)
        case "mode-control": modeControl(&b)
        case "cw-builder": try cwBuilder(&b)
        case "cut-style": cutStyle(&b)
        case "split": split(&b)
        case "frequency-steps": frequencySteps(&b)
        case "antenna": antenna(&b)
        case "band-notes": bandNotes(&b)
        case "transverter": transverter(&b)
        case "audio-to-rf": audioToRf(&b)
        case "voice": try voice(&b, context.corpus)
        case "mac-speech": try macSpeech(&b)
        case "rx-text": rxText(&b)
        case "text-tokens": textTokens(&b)
        case "recent-calls": recentCalls(&b)
        case "xmlrpc": xmlRpc(&b)
        case "rig-list": try rigList(&b)
        case "rig-model-filter": rigModelFilter(&b)
        case "serial-params": serialParams(&b)
        case "normalize-device": normalizeDevice(&b)
        case "rotator": rotator(&b)
        case "otrsp": otrsp(&b)
        case "edge-detector": edgeDetector(&b)
        case "contest-recorder": try contestRecorder(&b)
        case "to-samples": toSamples(&b)
        case "dsp": try dsp(&b, reference)
        default: break
        }
        return b.entry()
    }

    // MARK: - 1. HamlibModes

    static let dataModes: [Mode?] = [.digital, .ft8, .ssb, nil]

    static func mappings() -> [HamlibModeMapping] {
        var out: [HamlibModeMapping] = []
        for afsk in [false, true] {
            for dm in dataModes {
                out.append(HamlibModeMapping(dataMode: dm, rttyAfsk: afsk))
            }
        }
        return out
    }

    static func hamlibModes(_ b: inout F.Builder) {
        let maps = mappings()
        for path in b.inputs.children("/cfg/") {
            b.input(path)
        }
        for path in b.inputs.children("/s/") {
            b.input(path)
            let text: String? = b.inputs.values(path)[0]
            let modes: [String] = maps.map { $0.toMode(text)?.rawValue ?? "~" }
            b.out(path + "/to", modes.joined(separator: ","))
        }
        for path in b.inputs.children("/m/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let mode: Mode? = F.mode(f[0])
            let freq: Int64 = F.int64(f[1])
            let texts: [String] = maps.map { F.tx($0.toHamlib(mode, freqHz: freq)) }
            b.out(path + "/to", texts.joined(separator: ","))
        }
    }

    // MARK: - 2. ModeControl

    static func modeControl(_ b: inout F.Builder) {
        for path in b.inputs.children("/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let rule: ModeControl.Rule? = f[0] == "~" ? nil : ModeControl.Rule(rawValue: f[0])
            let category: BandPlan.ModeCategory? = f[2] == "~" ? nil : BandPlan.ModeCategory(rawValue: f[2])
            let mode = ModeControl.loggedMode(rule, radio: F.mode(f[1]), bandplan: category, always: F.mode(f[3]))
            b.out(path + "/m", mode?.rawValue ?? "~")
        }
    }

    // MARK: - 3. CwMessageBuilder, CwTiming, Winkeyer, CatCwKeyer

    static func cwContext(_ inputs: F.Inputs, _ k: Int) -> CwMessageBuilder.Context {
        let v: [String?] = inputs.values("/ctx/\(k)")
        let f: [String] = inputs.fields("/ctx/\(k)")
        func s(_ i: Int) -> String { v[i] ?? "" }
        let station = CwMessageBuilder.StationData(name: s(10), grid: s(11), cqZone: s(12), ituZone: s(13),
                                                   state: s(14), operator: s(15))
        let county: [String] = inputs.values("/ctx/\(k)/county").map { $0 ?? "" }
        let keys: [String] = inputs.values("/ctx/\(k)/fkeys").map { $0 ?? "" }
        let now: Date? = f[16] == "~" ? nil : F.date(millis: F.int64(f[16]))
        return CwMessageBuilder.Context(
            myCall: s(0), hisCall: s(1), lastLogged: s(2), serial: F.int(f[3]), rst: s(4), exchange: s(5),
            cutNumbers: F.bool(f[6]), leadingZeros: F.bool(f[7]), roverQth: s(8), countyLine: county,
            cutStyle: CutStyle(rawValue: f[9]) ?? .tn, station: station, functionKeys: keys, now: now)
    }

    static func describe(_ message: CwMessage) -> String {
        let wpms: [Int] = [3, 5, 20, 28, 60]
        let ms: [String] = wpms.map { String(CwTiming.estimateMillis(message, wpm: $0)) }
        return KeyerProbe.describe(message) + " ms=" + ms.joined(separator: "/")
    }

    static func cwBuilder(_ b: inout F.Builder) throws {
        var contexts: [CwMessageBuilder.Context] = []
        for k in 0..<6 {
            b.input("/ctx/\(k)")
            b.input("/ctx/\(k)/county")
            b.input("/ctx/\(k)/fkeys")
            contexts.append(cwContext(b.inputs, k))
        }
        b.input("/fuzz")
        let transport = PipeTransport()
        let keyer = WinkeyerKeyer(transport: transport)
        defer { keyer.close() }
        for path in b.inputs.children("/t/") {
            b.input(path)
            let template: String? = b.inputs.values(path)[1]
            for (k, context) in contexts.enumerated() {
                b.out(path + "/\(k)", F.tx(describe(CwMessageBuilder.build(template, context))))
            }
            let message = CwMessageBuilder.build(template, contexts[0])
            var hexes: [String] = []
            for wpm in [28, 3, 120] {
                transport.resetSent()
                try keyer.send(message, wpm: wpm)
                hexes.append(F.hex(transport.sent))
            }
            b.out(path + "/wk", hexes.joined(separator: "|"))
            let rig = KeyerRecordingRig()
            let cat = CatCwKeyer(rig: { rig })
            let result: String = KeyerProbe.safe {
                try cat.send(message, wpm: 28)
                try cat.send(message, wpm: 28)
                try cat.send(message, wpm: 30)
                return "ok"
            }
            b.out(path + "/cat", F.tx(result + " " + F.javaList(rig.calls)))
        }
    }

    // MARK: - 4. CutStyle

    static func cutBlock(_ style: CutStyle, zeros: Bool, block: Int) -> String {
        var text = ""
        text.reserveCapacity(8_000)
        for n in (block * 1000)..<((block + 1) * 1000) {
            var digits = String(n)
            if zeros && digits.utf8.count < 3 {
                digits = String(repeating: "0", count: 3 - digits.utf8.count) + digits
            }
            text += style.apply(digits)
            text += "\n"
        }
        return F.sha256(Data(text.utf8))
    }

    static func cutStyle(_ b: inout F.Builder) {
        b.input("/range")
        let extraPaths: [String] = b.inputs.children("/x/")
        for path in extraPaths {
            b.input(path)
        }
        let extra: [String] = extraPaths.map { b.inputs.values($0)[0] ?? "" }
        for style in CutStyle.allCases {
            for zeros in [false, true] {
                for block in 0..<100 {
                    let path = "/" + style.rawValue + "/" + (zeros ? "z" : "p") + "/" + JavaIoParityFixture.pad(block, 2)
                    b.out(path, cutBlock(style, zeros: zeros, block: block))
                }
            }
            b.out("/x/" + style.rawValue, extra.map { F.tx(style.apply($0)) }.joined(separator: "|"))
        }
    }

    // MARK: - 5. SplitFromComment

    static func split(_ b: inout F.Builder) {
        b.input("/spots")
        b.input("/defaults")
        b.input("/fuzz")
        let spots: [Int] = b.inputs.fields("/spots").map(F.int)
        let defaults: [Int] = b.inputs.fields("/defaults").map(F.int)
        for path in b.inputs.children("/c/") {
            b.input(path)
            let comment: String? = b.inputs.values(path)[1]
            var results: [String] = []
            for spot in spots {
                for up in defaults {
                    let r: Int? = SplitFromComment.parse(comment, spotFreqHz: spot, defaultUpHz: up)
                    results.append(r.map { String($0) } ?? "-")
                }
            }
            b.out(path + "/r", F.tx(results.joined(separator: " ")))
        }
    }

    // MARK: - 6. FrequencySteps, AntennaSelector, BandNotes, TransverterRig, AudioToRf

    static func frequencySteps(_ b: inout F.Builder) {
        for mode in Mode.allCases {
            b.out("/step/" + mode.rawValue, String(FrequencySteps.stepHz(mode)))
        }
        b.out("/step/~", String(FrequencySteps.stepHz(nil)))
        for band in Band.javaV111Cases {
            b.out("/warc/" + band.rawValue, F.flag(FrequencySteps.isWarc(band)))
        }
        let modes: [Mode?] = [.cw, .ssb, nil]
        let huge: Int = Int(Int32.max / 1000)
        for path in b.inputs.children("/w/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let freq: Int = F.int(f[0])
            let notches: Int = F.int(f[1])
            let alt: Bool = F.bool(f[2])
            let ctrl: Bool = F.bool(f[3])
            var results: [String] = []
            for mode in modes {
                if notches == huge && (alt || ctrl) {
                    results.append("skip")
                    continue
                }
                results.append(String(FrequencySteps.wheel(freq, mode: mode, notches: notches, alt: alt, ctrl: ctrl)))
            }
            b.out(path + "/r", results.joined(separator: " "))
        }
        var alloweds: [[Band]] = []
        for path in b.inputs.children("/allowed/") {
            b.input(path)
            alloweds.append(b.inputs.fields(path).compactMap { Band(rawValue: $0) })
        }
        for path in b.inputs.children("/nb/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let current: Band? = F.band(f[0])
            let direction: Int = F.int(f[1])
            let next: [String] = alloweds.map {
                FrequencySteps.nextBand(current, allowed: $0, direction: direction)?.rawValue ?? "-"
            }
            b.out(path + "/r", next.joined(separator: " "))
        }
    }

    static func antenna(_ b: inout F.Builder) {
        for path in b.inputs.children("/b/") {
            b.input(path)
            let entry = AntennaEntry(code: 1, name: "A", bands: b.inputs.values(path)[0] ?? "", sector: "")
            let covered: [String] = Band.javaV111Cases.filter { AntennaSelector.covers(entry, $0) }.map(\.rawValue)
            b.out(path + "/covers", covered.joined(separator: " "))
        }
        b.input("/az")
        let azimuths: [Int] = b.inputs.fields("/az").map(F.int)
        for path in b.inputs.children("/s/") {
            b.input(path)
            let sector: String = b.inputs.values(path)[0] ?? ""
            let flags: String = azimuths.map { F.flag(AntennaSelector.inSector(sector, $0)) }.joined()
            b.out(path + "/in", F.tx(flags))
        }
        var all: [AntennaEntry] = []
        for path in b.inputs.children("/t/") {
            b.input(path)
            let v = b.inputs.values(path)
            all.append(AntennaEntry(code: F.int(v[0] ?? ""), name: v[1] ?? "", bands: v[2] ?? "", sector: v[3] ?? ""))
        }
        b.input("/selaz")
        let selAz: [Int?] = b.inputs.fields("/selaz").map { $0 == "~" ? nil : F.int($0) }
        for band in Band.javaV111Cases {
            let sel: [String] = selAz.map { az in
                AntennaSelector.select(all, band: band, azimuth: az).map { String($0) } ?? "-"
            }
            let currents: [Int?] = [nil] + all.indices.map { Optional($0) }
            let next: [String] = currents.map { cur in
                AntennaSelector.next(all, band: band, currentIndex: cur).map { String($0) } ?? "-"
            }
            b.out("/sel/" + band.rawValue, sel.joined(separator: " "))
            b.out("/next/" + band.rawValue, next.joined(separator: " "))
        }
    }

    static func bandNotes(_ b: inout F.Builder) {
        var notes: [BandNote] = []
        for path in b.inputs.children("/n/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let note = BandNote(band: F.untx(f[0]) ?? "", freqKHz: F.double(bits: f[1]), text: F.untx(f[2]) ?? "")
            notes.append(note)
            b.out(path + "/band", BandNotes.bandOf(note)?.rawValue ?? "-")
        }
        for band in Band.javaV111Cases {
            b.out("/for/" + band.rawValue, F.list(BandNotes.forBand(notes, band: band).map(\.text)))
        }
        for path in b.inputs.children("/near/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let note = BandNotes.near(notes, freqHz: F.int(f[0]), toleranceHz: F.int(f[1]))
            b.out(path + "/r", F.tx(note?.text ?? "-"))
        }
    }

    static func transverter(_ b: inout F.Builder) {
        var list: [TransverterEntry] = []
        for path in b.inputs.children("/x/") {
            b.input(path)
            let f = b.inputs.fields(path)
            list.append(TransverterEntry(name: f[0], ifLowKHz: F.int(f[1]), ifHighKHz: F.int(f[2]),
                                         offsetKHz: F.int(f[3]), enabled: F.bool(f[4])))
        }
        let first: [TransverterEntry] = Array(list.prefix(1))
        for path in b.inputs.children("/f/") {
            b.input(path)
            let f: Int64 = F.int64(b.inputs.fields(path)[0])
            let parts: [Int64] = [TransverterRig.fromRig(f, list), TransverterRig.toRig(f, list),
                                  TransverterRig.fromRig(f, first), TransverterRig.toRig(f, [])]
            b.out(path + "/r", parts.map { String($0) }.joined(separator: " "))
        }
    }

    static func audioToRf(_ b: inout F.Builder) {
        b.input("/audio")
        let audios: [Double] = b.inputs.fields("/audio").map { F.double(bits: $0) }
        for path in b.inputs.children("/") where path != "/audio" {
            b.input(path)
            let f = b.inputs.fields(path)
            let raw: String? = F.untx(f[0])
            let dial: Int64 = F.int64(f[1])
            let pitch: Int32 = F.int32(f[2])
            let rf: [String] = audios.map {
                String(AudioToRf.rfHz(dialHz: dial, rawMode: raw, audioHz: $0, cwPitch: pitch))
            }
            b.out(path + "/r", rf.joined(separator: " "))
        }
    }

    // MARK: - 7. VoiceMessagePlanner, MacSpeech

    static func path(_ text: String) throws -> JavaPath {
        try JavaPath(text)
    }

    /// Java `safe`: the result text, or `EXC class: message`.
    static func safe(_ body: () throws -> String) -> String {
        do {
            return try body()
        } catch let error as JavaInvalidPathError {
            return "EXC InvalidPathException: " + error.message
        } catch let error as JavaIllegalArgumentError {
            return "EXC IllegalArgumentException: " + error.message
        } catch {
            return "EXC " + String(describing: error)
        }
    }

    static func voice(_ b: inout F.Builder, _ corpus: [String]) throws {
        for path in b.inputs.children("/ph/") {
            b.input(path)
            b.out(path + "/r", F.tx(VoiceMessagePlanner.phonetic(b.inputs.values(path)[0])))
        }
        b.input("/ttsctx")
        let t = b.inputs.fields("/ttsctx")
        let ttsContext = VoiceMessagePlanner.Context(operatorCall: t[0], myCall: t[1], hisCall: t[2],
                                                     serial: F.int32(t[3]), freqHz: F.int64(t[4]))
        for path in b.inputs.children("/tts/") {
            b.input(path)
            b.out(path + "/r", F.tx(VoiceMessagePlanner.ttsText(b.inputs.values(path)[0] ?? "", ttsContext)))
        }
        for path in b.inputs.children("/freq/") {
            b.input(path)
            b.out(path + "/r", F.tx(VoiceMessagePlanner.frequency(F.int64(b.inputs.fields(path)[0]))))
        }
        for path in b.inputs.children("/exp/") {
            b.input(path)
            let v = b.inputs.values(path)
            b.out(path + "/r", F.tx(VoiceMessagePlanner.expandPath(v[0] ?? "", v[1])))
        }
        let existing: Set<String> = Set(corpus.filter { $0.hasPrefix("vmp.exists\t") }.map {
            ProbeRows.unescape(String($0.dropFirst("vmp.exists\t".count)))
        })
        let wav = try path("/wav")
        let letters = try path("/wav/L")
        let speech: VoiceMessagePlanner.Speech = { text in
            text.contains("fail") ? nil : try? JavaPath("/tts/\(text.utf16.count).wav")
        }
        let callPaths: [String] = b.inputs.children("/call/")
        for p in callPaths {
            b.input(p)
        }
        let calls: [String] = callPaths.map { b.inputs.values($0)[0] ?? "" }
        for planPath in b.inputs.children("/plan/") {
            b.input(planPath)
            let text: String? = b.inputs.values(planPath)[0]
            for (c, call) in calls.enumerated() {
                let ctx = VoiceMessagePlanner.Context(operatorCall: "ok1xoe", myCall: "AB1", hisCall: call, serial: 104,
                                                      freqHz: 14_250_050)
                let result: String = safe {
                    let plan = try VoiceMessagePlanner.plan(text, ctx: ctx, wavDir: wav, lettersDir: letters,
                                                            exists: { existing.contains($0.description) }, speech: speech)
                    return F.javaList(plan.files.map(\.description)) + " " + F.javaList(plan.missing)
                }
                b.out(planPath + "/" + JavaIoParityFixture.pad(c, 2), F.tx(result))
            }
        }
        for p in b.inputs.children("/rec/") {
            b.input(p)
            let v = b.inputs.values(p)
            let result: String = safe {
                let target = try VoiceMessagePlanner.recordTarget(v[0], operatorCall: v[1], wavDir: wav)
                return target.map { "Optional[\($0)]" } ?? "Optional.empty"
            }
            b.out(p + "/r", F.tx(result))
        }
        for p in b.inputs.children("/dir/") {
            b.input(p)
            let v = b.inputs.values(p)
            let result: String = safe {
                try VoiceMessagePlanner.resolveDir(v[0] ?? "", operatorCall: v[1], wavDir: wav).description
            }
            b.out(p + "/r", F.tx(result))
        }
    }

    static func macSpeech(_ b: inout F.Builder) throws {
        let voicePaths: [String] = b.inputs.children("/v/")
        let textPaths: [String] = b.inputs.children("/t/")
        let cache = try path("/c")
        for (v, voicePath) in voicePaths.enumerated() {
            b.input(voicePath)
            let speech = MacSpeech(cacheDir: cache, voice: b.inputs.values(voicePath)[0])
            for (t, textPath) in textPaths.enumerated() {
                if v == 0 { b.input(textPath) }
                let text: String = b.inputs.values(textPath)[0] ?? ""
                b.out(voicePath + "/\(t)", F.tx(speech.cacheFile(text).description))
            }
        }
    }

    // MARK: - 8. RxTextStream, TextTokens, RecentCalls

    static func rxText(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let spec = b.inputs.fields(path)
            let rx = RxTextStream(maxChars: F.int32(spec[0]))
            var res = ""
            for op in spec.dropFirst() {
                let kind = op.prefix(1)
                let arg = String(op.dropFirst())
                if kind == "a" {
                    rx.append(F.untx(arg))
                } else if kind == "p" {
                    let span = rx.pending(F.int32(arg))
                    res += span.map { "\($0.start)+\($0.length)" } ?? "-"
                    res += " "
                } else {
                    rx.clear()
                }
                res += "[" + JavaIoParityFixture.tx(units: rx.textUnits) + "] "
            }
            b.out(path + "/r", res)
        }
    }

    static func tokens(_ list: [TextTokens.Token]) -> String {
        list.map { "\($0.start):\($0.end):" + F.tx($0.word) + " " }.joined()
    }

    static func textTokens(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let text: String? = b.inputs.values(path)[0]
            b.out(path + "/w", tokens(TextTokens.words(text)))
            b.out(path + "/l", TextTokens.byLine(text).map { "{" + tokens($0) + "}" }.joined())
        }
    }

    static func recentCalls(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let spec = b.inputs.fields(path)
            let calls = RecentCalls(max: F.int32(spec[0]))
            var res = ""
            for op in spec.dropFirst() {
                if op == "c" {
                    calls.clear()
                } else {
                    calls.offer(F.untx(String(op.dropFirst())))
                }
                res += F.list(calls.calls) + " "
            }
            b.out(path + "/r", res)
        }
    }

    // MARK: - 9. XmlRpc and others

    static func describeXml(_ xml: String) -> String {
        do {
            switch try XmlRpc.parseResponse(xml) {
            case nil: return "<null>"
            case .string(let s): return "String:" + s
            case .int(let n): return "Integer:" + String(n)
            case .double(let d): return "Double:" + F.javaDouble(d)
            case .bool(let v): return "Boolean:" + String(v)
            case .bytes(let bytes): return "byte[]:" + F.hex(bytes)
            }
        } catch {
            // The cause text from the parser (Xerces × libxml2) is not compared; DOCTYPE is.
            if (try? XMLDocument(data: Data(xml.utf8), options: [.nodeLoadExternalEntitiesNever])) == nil {
                return "EXC IllegalStateException: " + XmlRpc.invalidPrefix + "<parser>"
            }
            return "EXC IllegalStateException: " + error.message
        }
    }

    static func param(_ spec: String) -> XmlRpc.Param {
        let arg = String(spec.dropFirst())
        switch spec.prefix(1) {
        case "s": return .string(F.untx(arg))
        case "i": return .int(F.int64(arg))
        case "d": return .double(F.double(bits: arg))
        case "b": return .bool(F.bool(arg))
        default: return .string(nil)
        }
    }

    static func xmlRpc(_ b: inout F.Builder) {
        for path in b.inputs.children("/call/") {
            b.input(path)
            let spec = b.inputs.fields(path)
            let method: String = F.untx(spec[0]) ?? ""
            b.out(path + "/r", F.tx(XmlRpc.call(method, params: spec.dropFirst().map(param))))
        }
        for path in b.inputs.children("/doc/") {
            b.input(path)
            b.out(path + "/r", F.tx(describeXml(b.inputs.values(path)[0] ?? "")))
        }
    }

    static func rigModel(_ model: RigModel?) -> String {
        guard let model else { return "-" }
        return "\(model.number)|\(model.mfg)|\(model.model)|\(model.description)"
    }

    static func rigList(_ b: inout F.Builder) throws {
        b.own("/file", [F.sha256(try HamlibRigListFixture.data())])
        var all: [RigModel] = []
        for (i, line) in try HamlibRigListFixture.lines().enumerated() {
            let model = HamlibRigList.parseLine(line)
            if let model { all.append(model) }
            b.out("/l/" + JavaIoParityFixture.pad(i, 3), F.tx(rigModel(model)))
        }
        for path in b.inputs.children("/e/") {
            b.input(path)
            b.out(path + "/r", F.tx(rigModel(HamlibRigList.parseLine(b.inputs.values(path)[0] ?? ""))))
        }
        for path in b.inputs.children("/scan/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let bauds: [Int] = f.dropFirst(2).map(F.int)
            let candidates = RigScanner.buildCandidates(selectedModel: F.int(f[0]), selectedLabel: F.untx(f[1]) ?? "",
                                                        all: all, bauds: bauds)
            b.out(path + "/r", candidates.map { "\($0.model)@\($0.baud)=" + F.tx($0.label) + " " }.joined())
        }
    }

    static func rigModelFilter(_ b: inout F.Builder) {
        b.input("/fuzz")
        var models: [RigModel] = []
        for path in b.inputs.children("/m/") {
            b.input(path)
            let f = b.inputs.fields(path)
            models.append(RigModel(number: F.int(f[0]), mfg: F.untx(f[1]) ?? "", model: F.untx(f[2]) ?? ""))
        }
        b.out("/manufacturers", F.list(RigModelFilter.manufacturers(models)))
        for path in b.inputs.children("/q/") {
            b.input(path)
            let v = b.inputs.values(path)
            let found = RigModelFilter.filter(models, manufacturer: v[0], query: v[1])
            b.out(path + "/r", found.map { "\($0.number)," }.joined())
        }
    }

    static func serialParams(_ b: inout F.Builder) {
        for path in b.inputs.children("/") {
            b.input(path)
            let f = b.inputs.fields(path)
            let v = b.inputs.values(path)
            let params = SerialParams(dataBits: F.int(f[0]), stopBits: F.int(f[1]), parity: v[2], handshake: v[3],
                                      rts: v[4], dtr: v[5])
            b.out(path + "/r", F.tx(params.toSetConf()))
        }
    }

    static func normalizeDevice(_ b: inout F.Builder) {
        for path in b.inputs.children("/") {
            b.input(path)
            b.out(path + "/r", F.tx(RigctldProcessManager.normalizeDevice(b.inputs.values(path)[0]) ?? "null"))
        }
    }

    static func rotator(_ b: inout F.Builder) {
        b.input("/range")
        for k in -8000...8000 {
            let a: Double = Double(k) * 0.05
            b.out("/k/\(k)", F.javaDouble(RotctldClient.normalize(a)), RotctldClient.turnCommand(a),
                  F.javaDouble(RotctldClient.longPath(a)))
        }
        let names: [String?] = b.inputs.children("/name/").map { b.inputs.values($0)[0] }
        for (i, path) in b.inputs.children("/sp/").enumerated() {
            b.input(path)
            let a: Double = F.double(bits: b.inputs.fields(path)[0])
            let rotor: String? = names.isEmpty ? nil : names[i % names.count]
            let message = N1mmRotorUdp.turnMessage(rotor: rotor, azimuth: a, bandMhz: Int32(i - 3))
            b.out(path + "/r", F.javaDouble(RotctldClient.normalize(a)), RotctldClient.turnCommand(a),
                  F.javaDouble(RotctldClient.longPath(a)), F.tx(message))
        }
        for path in b.inputs.children("/name/") {
            b.input(path)
            b.out(path + "/stop", F.tx(N1mmRotorUdp.stopMessage(rotor: b.inputs.values(path)[0])))
        }
    }

    /// A collector of `Otrsp` messages (Java `sent::add`).
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func add(_ item: String) {
            lock.lock()
            items.append(item)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    static func otrsp(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let sink = Sink()
            let o = Otrsp(sink: { sink.add($0) })
            var res = ""
            for op in b.inputs.fields(path) {
                let kind = op.prefix(1)
                let parts: [Substring] = op.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
                let radio: Int32 = F.int32(String(parts[0]))
                let stereo: Bool = parts[1] == "1"
                let value: Int32 = F.int32(String(parts[2]))
                let result: String = safe {
                    switch kind {
                    case "t": try o.tx(radio)
                    case "l": try o.rx(radio, stereo: stereo)
                    case "f": try o.focus(radio, stereo: stereo)
                    default: try o.aux(radio, value: value)
                    }
                    return "ok"
                }
                res += F.tx(result) + " "
            }
            o.close()
            b.out(path + "/r", res + F.list(sink.all))
        }
    }

    static func edgeDetector(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let f = b.inputs.fields(path)
            let detector = Footswitch.EdgeDetector(stableSamples: F.int32(f[0]))
            var out = ""
            for unit in f[1].utf8 {
                switch detector.sample(unit == UInt8(ascii: "1")) {
                case nil: out += "n"
                case true?: out += "t"
                case false?: out += "f"
                }
            }
            b.out(path + "/r", out)
        }
    }

    static func contestRecorder(_ b: inout F.Builder) throws {
        let rec = ContestRecorder(dir: try path("/r"), sampleRate: 12_000)
        let rec2 = ContestRecorder(dir: try path("/a/b/../c"), sampleRate: 48_000)
        for p in b.inputs.children("/h/") {
            b.input(p)
            let size: Int64 = F.int64(b.inputs.fields(p)[0])
            b.out(p + "/r", F.hex(rec.header(size)), F.hex(rec2.header(size)))
        }
        b.input("/fuzz")
        for p in b.inputs.children("/f/") {
            b.input(p)
            let at = F.date(millis: F.int64(b.inputs.fields(p)[0]))
            b.out(p + "/r", F.tx(rec.fileFor(at).description), F.tx(rec2.fileFor(at).description))
        }
    }

    static func bytes(hex: String) -> [UInt8] {
        let units: [UInt8] = Array(hex.utf8)
        var out: [UInt8] = []
        var i = 0
        while i + 1 < units.count {
            out.append(UInt8(String(decoding: units[i..<(i + 2)], as: UTF8.self), radix: 16) ?? 0)
            i += 2
        }
        return out
    }

    static func toSamples(_ b: inout F.Builder) {
        b.input("/fuzz")
        for path in b.inputs.children("/") where path != "/fuzz" {
            b.input(path)
            let samples = AudioCapture.toSamples(bytes(hex: b.inputs.fields(path)[0]))
            b.out(path + "/r", samples.map { F.javaDouble($0) + " " }.joined())
        }
    }

    // MARK: - 10. DSP over PCM fixtures

    static let signals: [String] = ["cw18", "cw25", "cw32", "cw40", "noise", "tones"]

    /// The largest dB and brightness deviations against Java (for the assertion report).
    final class Deviation: @unchecked Sendable {
        var db = 0.0
        var norm = 0.0
    }

    static let deviation = Deviation()

    static func dsp(_ b: inout F.Builder, _ reference: Entry) throws {
        let javaOut: [String: [String]] = F.outputs(reference)
        b.input("/seed")
        for name in signals {
            let p = "/" + name
            let file = try F.wav(name)
            let toneBits: String = b.inputs.fields(p).dropFirst().first ?? "0"
            b.own(p, [F.sha256(file), toneBits])
            let tone: Double = F.double(bits: toneBits)
            let samples: [Double] = AudioCapture.toSamples(Array(file.dropFirst(44)))
            var text = ""
            let decoder = CwDecoder(sampleRate: 12_000, toneHz: tone, out: { text.append($0) })
            let waterfall = Waterfall(sampleRate: 12_000, maxHz: 3000, rows: 5)
            var rowsAdded = 0
            var block = 0
            var i = 0
            let half: Int = samples.count / 1024 / 2
            while i < samples.count {
                let chunk: [Double] = Array(samples[i..<min(samples.count, i + 1024)])
                let before: Int = text.utf16.count
                decoder.add(chunk)
                let added: Bool = waterfall.add(chunk)
                var peak = "-"
                if added {
                    rowsAdded += 1
                    let peaks: [Double] = [waterfall.peakHz(lo: 200, hi: 2800), waterfall.peakHz(lo: 0, hi: waterfall.maxHz),
                                           waterfall.peakHz(lo: 990, hi: 1010)]
                    peak = peaks.map(F.javaDouble).joined(separator: " ")
                }
                let fresh = String(decoding: Array(text.utf16).dropFirst(before), as: UTF16.self)
                b.out(p + "/b/" + JavaIoParityFixture.pad(block, 3), F.tx(fresh), String(decoder.wpm()), peak)
                if block == half { decoder.setTone(tone + 15) }
                i += 1024
                block += 1
            }
            b.out(p + "/text", F.tx(text), String(rowsAdded))
            for (r, row) in waterfall.normalizedRows().enumerated() {
                let path = p + "/norm/\(r)"
                let line = F.reconcile(java: javaOut[path]?.first, swift: row.map { Double($0) }, tolerance: 1e-6,
                                       maxDeviation: &deviation.norm)
                b.out(path, line)
            }
            for frame in [0, 3, 7] {
                let from: Int = frame * 4096
                guard from + 2048 <= samples.count else { continue }
                let db: [Double] = try Fft.magnitudesDb(Array(samples[from..<(from + 2048)]))
                let path = p + "/db/\(frame)"
                b.out(path, F.reconcile(java: javaOut[path]?.first, swift: db, tolerance: 1e-9,
                                        maxDeviation: &deviation.db))
            }
        }
    }
}
