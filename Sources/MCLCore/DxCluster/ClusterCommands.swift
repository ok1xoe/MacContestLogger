import Foundation

/// The software a DX cluster node runs (N1MM+ Telnet window, Clusters tab: the „DXSpider cluster" checkbox that formats
/// some commands for DXSpider). MCL also recognises the node from its greeting: DXSpider says „running DXSpider",
/// AR-Cluster „AR-Cluster", CC Cluster „CC-Cluster" / „CC Cluster".
public enum ClusterSoftware: String, CaseIterable, Sendable {
    /// Recognise the node from its greeting (DXSpider until it is known).
    case auto
    case dxSpider = "dxspider"
    case arCluster = "arcluster"
    case ccCluster = "cccluster"

    /// The stored value (`DxClusterConfig.clusterSoftware`); an unknown one is `auto`.
    public static func from(_ raw: String) -> ClusterSoftware {
        ClusterSoftware(rawValue: raw.lowercased()) ?? .auto
    }

    /// The node software a received line names, or `nil`.
    public static func detect(_ line: String) -> ClusterSoftware? {
        let upper: String = line.uppercased()
        if upper.contains("DXSPIDER") || upper.contains("DX SPIDER") { return .dxSpider }
        if upper.contains("AR-CLUSTER") || upper.contains("AR CLUSTER") { return .arCluster }
        if upper.contains("CC-CLUSTER") || upper.contains("CC CLUSTER") || upper.contains("CCCLUSTER") {
            return .ccCluster
        }
        return nil
    }

    /// The configured software, else the detected one, else DXSpider (the default buttons are DXSpider commands).
    public static func effective(configured: ClusterSoftware, detected: ClusterSoftware?) -> ClusterSoftware {
        if configured != .auto { return configured }
        return detected ?? .dxSpider
    }

    /// The product name (not translated; `auto` has a translated label in the window).
    public var productName: String {
        switch self {
        case .auto: "Auto"
        case .dxSpider: "DXSpider"
        case .arCluster: "AR-Cluster"
        case .ccCluster: "CC Cluster"
        }
    }
}

/// The cluster commands MCL builds itself (the band map's SH/DX, the spot menu's queries), formatted for the node's
/// software: DXSpider takes the count as a word (`SH/DX 30`), AR-Cluster and CC Cluster as a qualifier (`SH/DX/30`).
public enum ClusterCommandFormat {

    /// N1MM's default number of spots of the band map's SH/DX.
    public static let defaultShowDxCount = 30
    /// The count a node accepts.
    public static let showDxCountRange: ClosedRange<Int> = 1...100

    public static func clampedCount(_ count: Int) -> Int {
        Swift.min(Swift.max(count, showDxCountRange.lowerBound), showDxCountRange.upperBound)
    }

    /// `SH/DX` with `count` spots, optionally only of `call`.
    public static func showDx(count: Int, call: String? = nil, software: ClusterSoftware) -> String {
        let n: Int = clampedCount(count)
        let base: String
        switch software {
        case .arCluster, .ccCluster: base = "SH/DX/" + String(n)
        case .auto, .dxSpider: base = "SH/DX " + String(n)
        }
        guard let call = cleanCall(call) else { return base }
        return base + " " + call
    }

    /// A callsign safe to put into a command: trimmed, upper case, only letters, digits and `/`; `nil` when empty.
    public static func cleanCall(_ call: String?) -> String? {
        guard let call else { return nil }
        let upper: String = KotlinText.trim(call).uppercased()
        guard !upper.isEmpty,
              upper.unicodeScalars.allSatisfy({ ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "/" })
        else { return nil }
        return upper
    }
}

/// The macros of the DX Cluster window's buttons (N1MM Packet/Telnet macros): `{WAIT}` waits 5 seconds before the
/// rest is sent, `{CONN} name` connects to the cluster `name` of the list (N1MM „{CONN} RBN"). Every other text is a
/// command sent as it is; a button sends its parts in order.
public enum ClusterButtonMacro {

    /// One thing a button does.
    public enum Step: Equatable, Sendable {
        case send(String)
        case wait
        case connect(String)
    }

    /// N1MM's fixed `{WAIT}`.
    public static let waitMilliseconds = 5_000

    public static func steps(_ command: String) -> [Step] {
        var steps: [Step] = []
        for (index, part) in split(command, on: "{WAIT}").enumerated() {
            if index > 0 { steps.append(.wait) }
            let pieces: [String] = split(part, on: "{CONN}")
            if let first = pieces.first, !KotlinText.isBlank(first) {
                steps.append(.send(KotlinText.trim(first)))
            }
            for piece in pieces.dropFirst() {
                let name: String = KotlinText.trim(piece)
                if !name.isEmpty { steps.append(.connect(name)) }
            }
        }
        return steps
    }

    /// `text` split at every case-insensitive occurrence of `marker`.
    static func split(_ text: String, on marker: String) -> [String] {
        var parts: [String] = []
        var rest: Substring = text[...]
        while let range = rest.range(of: marker, options: .caseInsensitive) {
            parts.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        parts.append(String(rest))
        return parts
    }

    /// The favourite `{CONN} name` means: the first whose name, host or `host:port` equals `name` (ignoring case).
    public static func favorite(named name: String, in favorites: [DxClusterFavorite]) -> DxClusterFavorite? {
        let wanted: String = KotlinText.trim(name).lowercased()
        guard !wanted.isEmpty else { return nil }
        return favorites.first { KotlinText.trim($0.name).lowercased() == wanted }
            ?? favorites.first { $0.host.lowercased() == wanted || "\($0.host):\($0.port)".lowercased() == wanted }
    }
}

/// A set of the DX Cluster window's buttons as a text file (N1MM saves its telnet button sets as files): one button per
/// line, `label,command`; lines starting with `#` are comments. The label ends at the first comma.
public enum ClusterButtonFile {

    public static let header = "# MacContestLogger DX cluster buttons: label,command"

    public static func encode(_ commands: [DxClusterCommand]) -> String {
        ([header] + commands.map { $0.label.replacingOccurrences(of: ",", with: " ") + "," + $0.command })
            .joined(separator: "\n") + "\n"
    }

    /// The buttons of a file, padded with the defaults or cut to `DxClusterConfig.commandCount`; `nil` when the file
    /// has no button line.
    public static func decode(_ text: String) -> [DxClusterCommand]? {
        var commands: [DxClusterCommand] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line: String = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let label: String
            let command: String
            if let comma = line.firstIndex(of: ",") {
                label = String(line[..<comma])
                command = String(line[line.index(after: comma)...])
            } else {
                label = line
                command = line
            }
            commands.append(ClusterTexts.editedMacro(label: label, command: command))
        }
        guard !commands.isEmpty else { return nil }
        let defaults: [DxClusterCommand] = DxClusterConfig.defaultCommands()
        return (0..<DxClusterConfig.commandCount).map { index in
            index < commands.count ? commands[index] : defaults[index]
        }
    }
}

/// N1MM's cluster queries about one station (its View menu's „Show Last 10 Spots", „Show Station", „Show QSL",
/// „Show Sunrise/Sunset" and the callbook): the command for the node, `nil` for a text that is no callsign.
public enum ClusterCallQuery: CaseIterable, Sendable {
    case lastSpots
    case station
    case qsl
    case sun
    case qrz

    /// N1MM „Show Last 10 Spots".
    public static let lastSpotsCount = 10

    public func command(call: String, software: ClusterSoftware) -> String? {
        guard let call = ClusterCommandFormat.cleanCall(call) else { return nil }
        switch self {
        case .lastSpots: return ClusterCommandFormat.showDx(count: Self.lastSpotsCount, call: call, software: software)
        case .station: return "SH/STATION " + call
        case .qsl: return "SH/QSL " + call
        case .sun: return "SH/SUN " + call
        case .qrz: return "SH/QRZ " + call
        }
    }

    /// The menu item's Czech key (`tr`).
    public var titleKey: String {
        switch self {
        case .lastSpots: "Posledních 10 spotů (SH/DX)"
        case .station: "Stanice (SH/STATION)"
        case .qsl: "QSL informace (SH/QSL)"
        case .sun: "Východ a západ slunce (SH/SUN)"
        case .qrz: "Callbook clusteru (SH/QRZ)"
        }
    }
}
