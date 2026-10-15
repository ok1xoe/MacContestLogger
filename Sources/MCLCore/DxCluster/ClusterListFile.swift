import Foundation

/// The list of clusters as a text file (N1MM imports and exports its cluster list): one cluster per line,
/// `name,host:port[,login]`; lines starting with `#` are comments. Passwords are never written.
public enum ClusterListFile {

    public static let header = "# MacContestLogger DX cluster list: name,host:port[,login]"

    public static func encode(_ favorites: [DxClusterFavorite]) -> String {
        let rows: [String] = favorites.map { fav in
            let name: String = fav.name.replacingOccurrences(of: ",", with: " ")
            var row: String = name + "," + fav.host + ":" + String(fav.port)
            if !KotlinText.isBlank(fav.login) {
                row += "," + KotlinText.trim(fav.login)
            }
            return row
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// The clusters of a file; lines that are not `name,host:port[,login]` with a valid port are skipped.
    public static func decode(_ text: String) -> [DxClusterFavorite] {
        var out: [DxClusterFavorite] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line: String = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields: [String] = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, let colon = fields[1].lastIndex(of: ":") else { continue }
            let host: String = String(fields[1][..<colon])
            guard !host.isEmpty, let port = Int(fields[1][fields[1].index(after: colon)...]),
                  (1...65_535).contains(port) else { continue }
            out.append(DxClusterFavorite(name: fields[0], host: host, port: port,
                                         login: fields.count > 2 ? fields[2] : "", password: ""))
        }
        return out
    }

    /// `imported` appended to `existing`, skipping clusters whose `host:port` is already there (or repeats).
    public static func merge(_ existing: [DxClusterFavorite], _ imported: [DxClusterFavorite]) -> [DxClusterFavorite] {
        var keys: Set<String> = Set(existing.map { $0.connectionKey.lowercased() })
        var out: [DxClusterFavorite] = existing
        for fav in imported where keys.insert(fav.connectionKey.lowercased()).inserted {
            out.append(fav)
        }
        return out
    }
}

/// N1MM „Randomize incoming spot frequencies": tuning to a spot lands a little off its frequency so that the
/// operators clicking the same spot do not all call exactly on it. The offset is never zero: 50–150 Hz in CW and
/// digital modes, 100–250 Hz in phone (within the default tuning tolerance of the call-frame), up or down.
public enum SpotFrequencyJitter {

    public static let cwRange: ClosedRange<Int> = 50...150
    public static let phoneRange: ClosedRange<Int> = 100...250

    /// - Parameter draw: a random integer in the range (injected by tests).
    public static func offsetHz(phone: Bool, draw: (ClosedRange<Int>) -> Int) -> Int {
        let range: ClosedRange<Int> = phone ? phoneRange : cwRange
        let magnitude: Int = Swift.min(Swift.max(draw(range), range.lowerBound), range.upperBound)
        return draw(0...1) == 0 ? -magnitude : magnitude
    }
}

/// The spot buffer saved across a restart (N1MM „Save Spots"): a JSON file in the data directory.
public enum SavedSpotsFile {

    public static let fileName = "spots.json"

    private struct Payload: Codable {
        var version: Int = 1
        var spots: [SpotBuffer.Stored]
    }

    public static func encode(_ spots: [SpotBuffer.Stored]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(spots: spots))
    }

    /// The saved entries, or `nil` for a file that is not one.
    public static func decode(_ data: Data) -> [SpotBuffer.Stored]? {
        try? JSONDecoder().decode(Payload.self, from: data).spots
    }
}

/// Settings → DX Cluster: the favourites of the draft exported to and imported from a cluster list file.
extension ConfigurerDraft {

    /// The draft's favourites as a cluster list file (no passwords).
    public var dxFavoritesFileText: String {
        ClusterListFile.encode(dxFavorites.map { $0.toFavorite() })
    }

    /// Appends the clusters of a list file whose `host:port` the draft does not have yet; returns how many.
    @discardableResult
    public mutating func importDxFavorites(_ text: String) -> Int {
        let existing: [DxClusterFavorite] = dxFavorites.map { $0.toFavorite() }
        let merged: [DxClusterFavorite] = ClusterListFile.merge(existing, ClusterListFile.decode(text))
        let added: ArraySlice<DxClusterFavorite> = merged.dropFirst(existing.count)
        dxFavorites += added.map { DxFavoriteDraft($0) }
        return added.count
    }

    /// „Vybrat ze seznamu": a cluster of the published list as a new favorite, logging in with the station's
    /// callsign. `false` (nothing added) when the draft already has its `host:port`.
    @discardableResult
    public mutating func addDxFavorite(from entry: ClusterDirectory.Entry) -> Bool {
        let login: String = KotlinText.trim(call).uppercased()
        let existing: [DxClusterFavorite] = dxFavorites.map { $0.toFavorite() }
        let merged: [DxClusterFavorite] = ClusterListFile.merge(existing, [entry.favorite(login: login)])
        guard merged.count > existing.count, let added = merged.last else { return false }
        dxFavorites.append(DxFavoriteDraft(added))
        return true
    }
}
