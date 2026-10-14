/// N1MM message files (`.mc`): one message per line, `Label,Text` (the first comma separates them); empty lines and
/// lines starting with `#` are skipped. Used for the Digital Interface's message buttons.
public enum McMessages {

    public static func parse(_ text: String) -> [FunctionKeyMessage] {
        var out: [FunctionKeyMessage] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if let comma = line.firstIndex(of: ",") {
                out.append(FunctionKeyMessage(label: String(line[..<comma]).trimmingCharacters(in: .whitespaces),
                                              text: String(line[line.index(after: comma)...])
                                                .trimmingCharacters(in: .whitespaces)))
            } else {
                out.append(FunctionKeyMessage(label: line, text: ""))
            }
        }
        return out
    }

    public static func format(_ messages: [FunctionKeyMessage]) -> String {
        "# MacContestLogger Digital Interface buttons\n"
            + messages.map { $0.label + "," + $0.text }.joined(separator: "\n") + "\n"
    }
}

/// The three F-key message sets of the app, as N1MM keeps one `.mc` file each (CW, SSB, digital).
public enum FunctionKeyKind: String, CaseIterable, Codable, Equatable, Sendable {
    case cw = "CW"
    case ssb = "SSB"
    case digital = "DIGI"

    /// The Run and S&P messages of this kind in the configuration.
    public func messages(in config: AppConfig) -> FunctionKeySet {
        switch self {
        case .cw: return FunctionKeySet(run: config.cwKeyer.runMessages, sp: config.cwKeyer.spMessages)
        case .ssb: return FunctionKeySet(run: config.voiceKeyer.runMessages, sp: config.voiceKeyer.spMessages)
        case .digital: return FunctionKeySet(run: config.digital.runMessages, sp: config.digital.spMessages)
        }
    }

    /// Replaces the Run and S&P messages of this kind (each set is padded / cut to the key count by its config).
    public func set(_ keys: FunctionKeySet, in config: inout AppConfig) {
        switch self {
        case .cw:
            config.cwKeyer.runMessages = keys.run
            config.cwKeyer.spMessages = keys.sp
        case .ssb:
            config.voiceKeyer.runMessages = keys.run
            config.voiceKeyer.spMessages = keys.sp
        case .digital:
            config.digital.runMessages = keys.run
            config.digital.spMessages = keys.sp
        }
    }
}

/// N1MM function key files (`.mc`, N1MM „Function Key Editor"): every line not starting with `#` in the first column is
/// a message — blank lines too — `Label,Message` (the first comma separates them; no comma = an empty message). The
/// position alone decides the key: lines 1–12 are the Run messages F1–F12, lines 13–24 the S&P messages; a missing
/// S&P message repeats the Run one of the same key. `&&` in a label is one `&`. A label starting with its own key name
/// (`F1 Cq`, as in N1MM's default files) loses that prefix, because the button shows the key name itself.
public enum McFunctionKeys {

    public static let keyCount: Int = 12

    /// The Run and S&P sets of the file; `nil` = no message line at all.
    public static func parse(_ text: String) -> FunctionKeySet? {
        var lines: [String] = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.hasPrefix("\u{FEFF}") == true {
            lines[0] = String(lines[0].dropFirst())
        }
        var messages: [FunctionKeyMessage] = []
        for line in lines where !line.hasPrefix("#") {
            messages.append(message(line, index: messages.count % keyCount))
        }
        // Blank lines at the end of the file are its line ends, not messages.
        while let last = messages.last, last.label.isEmpty, last.text.isEmpty {
            messages.removeLast()
        }
        guard !messages.isEmpty else { return nil }
        var run: [FunctionKeyMessage] = Array(messages.prefix(keyCount))
        while run.count < keyCount {
            run.append(FunctionKeyMessage(label: "Empty", text: ""))
        }
        var sp: [FunctionKeyMessage] = Array(messages.dropFirst(keyCount).prefix(keyCount))
        while sp.count < keyCount {
            sp.append(run[sp.count])
        }
        return FunctionKeySet(run: run, sp: sp)
    }

    private static func message(_ line: String, index: Int) -> FunctionKeyMessage {
        let label: String
        let text: String
        if let comma = line.firstIndex(of: ",") {
            label = String(line[..<comma])
            text = String(line[line.index(after: comma)...])
        } else {
            label = line
            text = ""
        }
        var clean: String = label.replacingOccurrences(of: "&&", with: "&").trimmingCharacters(in: .whitespaces)
        let prefix: String = "F" + String(index + 1) + " "
        if clean.uppercased().hasPrefix(prefix) {
            clean = String(clean.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return FunctionKeyMessage(label: clean, text: text.trimmingCharacters(in: .whitespaces))
    }

    /// The file N1MM reads: a comment header, the 12 Run messages, then the 12 S&P ones, labels as `F1 Cq` with `&`
    /// doubled. A comma in a label (the file's separator) becomes a space.
    public static func format(_ keys: FunctionKeySet, title: String) -> String {
        var out: String = "# " + title + "\n# RUN Messages\n"
        out += lines(keys.run)
        out += "# S&P Messages\n"
        out += lines(keys.sp)
        return out
    }

    private static func lines(_ messages: [FunctionKeyMessage]) -> String {
        var out: String = ""
        for index in 0..<keyCount {
            let message: FunctionKeyMessage = index < messages.count ? messages[index]
                : FunctionKeyMessage(label: "Empty", text: "")
            let label: String = message.label.replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "&", with: "&&")
            out += "F" + String(index + 1) + " " + label + "," + message.text.replacingOccurrences(of: "\n", with: " ")
                + "\n"
        }
        return out
    }
}
