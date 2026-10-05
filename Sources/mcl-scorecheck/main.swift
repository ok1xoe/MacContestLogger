import Foundation
import MCLCore

// Command line of `mcl-scorecheck`: the logic lives in `ScoreCheckReport` (testable without the binary).

let usage = """
Použití: mcl-scorecheck <soubor|adresář> --contest-data <adresář> [volby]
  --dxcc cty|json      zdroj DXCC (výchozí cty)
  --dxcc-file <cesta>  cty.dat resp. dxcc.json (výchozí ~/dxcc-json/cty.dat resp. dxcc.json)
  --contest-data <dir> adresář s contests/ a multipliers/ (povinné)
  --jobs N             počet vláken (výchozí 1); pořadí výstupu je vždy stejné
  --set <název>        hodnota hlavičky `set` (výchozí název vstupu)
  --out <soubor>       zápis do souboru místo stdout
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parseArguments() -> (input: String, contestData: String, mode: ScoreCheckReport.DxccMode,
                          dxccFile: String?, jobs: Int, setName: String?, outPath: String?) {
    var input: String?
    var contestData: String?
    var mode = ScoreCheckReport.DxccMode.cty
    var dxccFile: String?
    var jobs = 1
    var setName: String?
    var outPath: String?
    let argv = Array(CommandLine.arguments.dropFirst())
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < argv.count else { fail("Chybí hodnota pro \(flag)\n\(usage)") }
        return argv[i]
    }
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "--dxcc":
            guard let m = ScoreCheckReport.DxccMode(rawValue: value(arg)) else { fail("--dxcc: cty nebo json") }
            mode = m
        case "--dxcc-file": dxccFile = value(arg)
        case "--contest-data": contestData = value(arg)
        case "--jobs":
            guard let n = Int(value(arg)), n >= 1 else { fail("--jobs: kladné číslo") }
            jobs = n
        case "--set": setName = value(arg)
        case "--out": outPath = value(arg)
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            if arg.hasPrefix("--") || input != nil { fail("Neznámý argument \(arg)\n\(usage)") }
            input = arg
        }
        i += 1
    }
    guard let input, let contestData else { fail(usage) }
    return (input, contestData, mode, dxccFile, jobs, setName, outPath)
}

let parsed = parseArguments()
let input = parsed.input, contestData = parsed.contestData, mode = parsed.mode
let dxccFile = parsed.dxccFile, jobs = parsed.jobs, setName = parsed.setName, outPath = parsed.outPath
let home = FileManager.default.homeDirectoryForCurrentUser
let dxccURL = dxccFile.map { URL(fileURLWithPath: $0) }
    ?? home.appendingPathComponent("dxcc-json").appendingPathComponent(mode == .cty ? "cty.dat" : "dxcc.json")

let options = ScoreCheckReport.Options(
    input: URL(fileURLWithPath: input), contestData: URL(fileURLWithPath: contestData),
    dxccMode: mode, dxccFile: dxccURL, jobs: jobs, setName: setName)
let started = Date()
do {
    let output = try ScoreCheckReport.run(options)
    let text = Data(output.text.utf8)
    if let outPath {
        do { try text.write(to: URL(fileURLWithPath: outPath)) } catch { fail("Nelze zapsat \(outPath): \(error)", code: 1) }
    } else {
        FileHandle.standardOutput.write(text)
    }
    let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
    let counts = output.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    FileHandle.standardError.write(Data("\(output.rows.count) logů (\(counts)) za \(seconds) s\n".utf8))
} catch {
    fail("\(error)", code: 1)
}
