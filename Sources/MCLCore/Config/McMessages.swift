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
