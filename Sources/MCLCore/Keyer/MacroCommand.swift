import Foundation

/// An F-key macro with a parameter (N1MM `{COMMENT text}`…): a program action like `CwMessage.Action`, carried
/// beside the message's actions and performed by the app. Swift-only.
public enum MacroCommand: Equatable, Sendable {
    /// `{COMMENT text}`: the text goes to the note of the QSO in progress, or of the last logged QSO when the call
    /// field is empty.
    case comment(String)
    /// `{CAT1ASC …}`, `{CATA2HEX …}`, `{CATACTASC …}`…: raw CAT commands for a rig (`CatMacro`).
    case cat(CatMacro)
    /// `{CATDELAY n}`: a pause of n × 50 ms (at most 1 s) after the message's CAT commands, on the rig's lane.
    case catDelay(Int)
    /// `{TELNET cmd}`: a command to the DX cluster (Telnet window).
    case telnet(String)
    /// `{SETWAVDIR text}`: the value of `{WAVDIR}` in the voice messages' paths (`{OPERATOR}` in it is the operator).
    case setWavDir(String)
    /// `{AUXANTSEL nn}`: the antenna with code nn from the antenna table (also announced in the UDP RadioInfo).
    case auxAntenna(Int)
    /// `{ANTRX1TOGGLE}`…`{ANTRX4TOGGLE}`: the rig's antenna port n; the same port again toggles its RX antenna.
    case antennaRx(Int)
    /// `{CTRLF1}`…`{CTRLF12}` (N1MM, SO2R / SO2V): the key's message sent on the other radio (index from 0).
    case otherRadioKey(Int)
    /// `{OTRSP cmd}` / `{OTRSPOTHER cmd}`: a command to the OTRSP device; `RX` is the RX command of the active /
    /// the inactive radio (`other`).
    case otrsp(String, other: Bool)
    /// `{SWAPCONTESTS}` / `{SWAPCONTESTS3}`…`{SWAPCONTESTS6}`: the next of the last n contests opened (2 = the
    /// previous one).
    case swapContests(Int)
    /// `{SWAPCONTESTS name}`: the contest of the Open recent list whose title holds the name.
    case swapContest(String)
    /// `{MESSAGE}` (N1MM multi-user): the rest of the message goes to the network as a talk message instead of the
    /// transmitter; a first word naming a station sends it to that station only, `-` to all.
    case networkMessage(String)
    /// `{PASS name}` / `{PASS kHz}`: the pass frequency of that station was put into the message; it becomes the
    /// last passed frequency (`{LASTPASSEDFREQ}`).
    case passAlert(station: String, hz: Int)
    /// `{PASSMSG name}` / `{PASSMSG kHz}`: the last QSO's call is passed to that station (the argument as written).
    case passLastQso(String)

    /// The command of a parameterized macro (`raw` = the whole macro with its braces); `nil` = not a parameterized
    /// macro this app knows.
    public static func parse(_ raw: String) -> MacroCommand? {
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else { return nil }
        let upper: String = raw.uppercased()
        if let cat = CatMacro.parse(raw) {
            return .cat(cat)
        }
        if upper.hasPrefix("{ANTRX"), upper.hasSuffix("TOGGLE}"), upper.count == 14,
           let port = Int(String(upper.dropFirst(6).prefix(1))), (1...4).contains(port) {
            return .antennaRx(port)
        }
        if upper.hasPrefix("{CTRLF"), let number = Int(upper.dropFirst(6).dropLast()), (1...12).contains(number) {
            return .otherRadioKey(number - 1)
        }
        if upper == "{SWAPCONTESTS}" {
            return .swapContests(2)
        }
        if upper.hasPrefix("{SWAPCONTESTS"), let n = Int(upper.dropFirst(13).dropLast()), (3...6).contains(n) {
            return .swapContests(n)
        }
        guard let (name, argument) = split(raw) else { return nil }
        switch name {
        case "COMMENT":
            return argument.isEmpty ? nil : .comment(argument)
        case "CATDELAY":
            guard let n = Int(argument), n >= 0 else { return nil }
            return .catDelay(min(n, 20))
        case "TELNET":
            return argument.isEmpty ? nil : .telnet(argument)
        case "SETWAVDIR":
            return argument.isEmpty ? nil : .setWavDir(argument)
        case "OTRSP", "OTRSPOTHER":
            guard !argument.isEmpty, argument.count <= 32,
                  argument.allSatisfy({ $0.isASCII && !$0.isNewline }) else { return nil }
            return .otrsp(argument.uppercased(), other: name == "OTRSPOTHER")
        case "SWAPCONTESTS":
            return argument.isEmpty ? nil : .swapContest(argument)
        case "PASSMSG":
            return argument.isEmpty ? nil : .passLastQso(argument)
        case "AUXANTSEL":
            guard let code = Int(argument), (0...63).contains(code) else { return nil }
            return .auxAntenna(code)
        default:
            return nil
        }
    }

    /// `{SETWAVDIR …}`.
    public var isWavDir: Bool {
        if case .setWavDir = self { true } else { false }
    }

    /// A macro whose argument may hold another macro in braces (`{SETWAVDIR {OPERATOR}_2}`): its closing brace is the
    /// one that balances the opening one.
    static func nests(_ upperPrefix: String) -> Bool {
        upperPrefix.hasPrefix("{SETWAVDIR")
    }

    /// `{NAME argument}` → (`NAME` in upper case, the argument as written, trimmed); `nil` without a space.
    static func split(_ raw: String) -> (String, String)? {
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else { return nil }
        let inner: Substring = raw.dropFirst().dropLast()
        guard let space = inner.firstIndex(of: " ") else { return nil }
        let name: String = String(inner[..<space]).uppercased()
        let argument: String = String(inner[inner.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (name, argument)
    }
}

/// N1MM `{VARYMSG1&Primary&Alternate&N&}` / `{VARYMSG2…}`: an alternating message. `N` = 0 sends the primary text
/// every time, 1 the alternate every time, N > 1 the alternate every N-th time. The counter of each macro is kept by
/// the app (`counts[0]` for VARYMSG1, `counts[1]` for VARYMSG2: how many times the macro was sent before).
public enum VaryMessage {

    /// The text with every VARYMSG macro replaced by the text chosen for this send, and the macros used (1, 2).
    public static func expand(_ text: String, counts: [Int]) -> (text: String, used: [Int]) {
        var out: String = ""
        var used: [Int] = []
        var rest: Substring = Substring(text)
        while let match = nextMacro(in: rest) {
            out += rest[..<match.start]
            let count: Int = match.number - 1 < counts.count ? counts[match.number - 1] : 0
            out += alternate(every: match.every, sendNumber: count + 1) ? match.alternate : match.primary
            if !used.contains(match.number) {
                used.append(match.number)
            }
            rest = rest[match.end...]
        }
        out += rest
        return (out, used)
    }

    /// Whether send number `sendNumber` (from 1) takes the alternate text.
    static func alternate(every: Int, sendNumber: Int) -> Bool {
        if every <= 0 {
            return false
        }
        return every == 1 || sendNumber % every == 0
    }

    private struct Match {
        let start: Substring.Index
        let end: Substring.Index
        let number: Int
        let primary: Substring
        let alternate: Substring
        let every: Int
    }

    /// The first well-formed `{VARYMSG<1|2> &a&b&n&}` (ASCII case-insensitive name, spaces before the first `&` and
    /// before `}` allowed). A malformed one is left in the text (and reported as an unknown macro later).
    private static func nextMacro(in text: Substring) -> Match? {
        var search: Substring.Index = text.startIndex
        while let range = text[search...].range(of: "{VARYMSG", options: [.caseInsensitive]) {
            if let match = parse(text, from: range) {
                return match
            }
            search = range.upperBound
        }
        return nil
    }

    private static func parse(_ text: Substring, from range: Range<Substring.Index>) -> Match? {
        var index: Substring.Index = range.upperBound
        guard index < text.endIndex, let number = Int(String(text[index])), number == 1 || number == 2 else {
            return nil
        }
        index = text.index(after: index)
        while index < text.endIndex, text[index] == " " {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "&" else { return nil }
        var fields: [Substring] = []
        var fieldStart: Substring.Index = text.index(after: index)
        var cursor: Substring.Index = fieldStart
        while fields.count < 3, cursor < text.endIndex {
            if text[cursor] == "&" {
                fields.append(text[fieldStart..<cursor])
                fieldStart = text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        guard fields.count == 3 else { return nil }
        cursor = fieldStart
        while cursor < text.endIndex, text[cursor] == " " {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == "}",
              let every = Int(fields[2].trimmingCharacters(in: .whitespaces)), every >= 0 else { return nil }
        return Match(start: range.lowerBound, end: text.index(after: cursor), number: number, primary: fields[0],
                     alternate: fields[1], every: every)
    }
}

/// N1MM's raw CAT macros: `{CAT1ASC …}` / `{CAT1HEX …}` (radio 1, `CAT2…` radio 2), `{CATA1…}` / `{CATA2…}` (only
/// when that radio — the VFO in SO2V — is the active one), `{CATI1…}` / `{CATI2…}` (only when it is the inactive
/// one) and `{CATACTASC …}` / `{CATACTHEX …}` (the active one). Several commands are separated by `\`. ASCII
/// commands may hold bytes as `<2A>`; HEX commands are hex digits (spaces ignored). Each command goes to `rigctld` as
/// `w` (send_cmd) with the bytes hamlib's way (`\0x2A`).
public struct CatMacro: Equatable, Sendable {

    public enum Target: Equatable, Sendable {
        /// Radio (or VFO in SO2V) 0 / 1, always.
        case radio(Int)
        /// Radio 0 / 1, only while it is the active one.
        case ifActive(Int)
        /// Radio 0 / 1, only while it is the inactive one.
        case ifInactive(Int)
        /// The active radio.
        case active
    }

    public var target: Target
    /// The `rigctld` arguments of `w`, one per command (`FA;`, `\0xFE\0xFE\0x6E…`).
    public var commands: [String]

    public init(target: Target, commands: [String]) {
        self.target = target
        self.commands = commands
    }

    private static let names: [(String, Target)] = [
        ("CATACT", .active), ("CATA1", .ifActive(0)), ("CATA2", .ifActive(1)), ("CATI1", .ifInactive(0)),
        ("CATI2", .ifInactive(1)), ("CAT1", .radio(0)), ("CAT2", .radio(1)),
    ]

    static func parse(_ raw: String) -> CatMacro? {
        let inner: String = String(raw.dropFirst().dropLast())
        let upper: String = inner.uppercased()
        for (name, target) in names {
            for (kind, hex) in [("ASC", false), ("HEX", true)] where upper.hasPrefix(name + kind) {
                let payload: String = String(inner.dropFirst(name.count + kind.count))
                let commands: [String] = hex ? hexCommands(payload) : asciiCommands(payload)
                return commands.isEmpty ? nil : CatMacro(target: target, commands: commands)
            }
        }
        return nil
    }

    /// ASCII: leading spaces dropped; `\` splits commands; `<HH>` is a byte; a space or a non-printable character is
    /// written as a byte too (one `rigctld` argument).
    static func asciiCommands(_ payload: String) -> [String] {
        var commands: [String] = []
        for part in payload.drop(while: { $0 == " " }).split(separator: "\\", omittingEmptySubsequences: true) {
            var out: String = ""
            var rest: Substring = part
            while let first = rest.first {
                if first == "<", rest.count >= 4, rest[rest.index(rest.startIndex, offsetBy: 3)] == ">",
                   let byte = UInt8(rest.dropFirst().prefix(2), radix: 16) {
                    out += byteText(byte)
                    rest = rest.dropFirst(4)
                    continue
                }
                if let ascii = first.asciiValue, ascii > 0x20, ascii < 0x7F, first != "\\" {
                    out.append(first)
                } else if let ascii = first.asciiValue {
                    out += byteText(ascii)
                }
                rest = rest.dropFirst()
            }
            if !out.isEmpty {
                commands.append(out)
            }
        }
        return commands
    }

    /// HEX: `\` splits commands; within one, hex digit pairs (spaces ignored); an odd or bad digit drops the command.
    static func hexCommands(_ payload: String) -> [String] {
        var commands: [String] = []
        for part in payload.split(separator: "\\", omittingEmptySubsequences: true) {
            let digits: [Character] = part.filter { $0 != " " }
            guard !digits.isEmpty, digits.count % 2 == 0 else { continue }
            var out: String = ""
            var valid = true
            for index in stride(from: 0, to: digits.count, by: 2) {
                guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else {
                    valid = false
                    break
                }
                out += byteText(byte)
            }
            if valid {
                commands.append(out)
            }
        }
        return commands
    }

    private static func byteText(_ byte: UInt8) -> String {
        let hex: String = String(byte, radix: 16, uppercase: true)
        return "\\0x" + (hex.count == 1 ? "0" + hex : hex)
    }
}
