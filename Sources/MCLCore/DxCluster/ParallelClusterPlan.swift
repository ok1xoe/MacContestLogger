extension DxClusterFavorite {

    /// Connection identity (Java `connectionKey()`): `host.trim().toLowerCase() + ":" + port` — by
    /// it concurrent connections are kept and dropped.
    public var connectionKey: String {
        JavaText.toLowerCase(JavaText.trim(host)) + ":" + String(port)
    }
}

/// Which concurrent DX cluster connections to open and which to close (Java `dxcluster.ParallelClusterPlan`;
/// DXLog.net DXC: several nodes and skimmers at once). Concurrent are favorites with `parallel` enabled
/// and a filled-in server; the main connection (DX Cluster window) is not duplicated.
public enum ParallelClusterPlan {

    public struct Plan: Equatable, Sendable {
        public let toConnect: [DxClusterFavorite]
        public let toDisconnect: [String]

        public init(toConnect: [DxClusterFavorite], toDisconnect: [String]) {
            self.toConnect = toConnect
            self.toDisconnect = toDisconnect
        }
    }

    /// - Parameters:
    ///   - open: keys (`connectionKey`) of the currently open concurrent connections (Java `Set`)
    ///   - primary: key of the main connection, `nil` = none
    ///
    /// Keys are compared by UTF-16 units like Java `String.equals` (`JavaStringKey`), the first
    /// favorite with a given key wins (`putIfAbsent` into `LinkedHashMap`), `toConnect` is in favorite
    /// order and `toDisconnect` is sorted by Java `sorted()` (by UTF-16 units, not Swift `<`).
    public static func plan(_ favorites: [DxClusterFavorite], open: [String], primary: String?) -> Plan {
        var wantedKeys: [JavaStringKey] = []
        var wanted: [JavaStringKey: DxClusterFavorite] = [:]
        let primaryKey = JavaStringKey(primary)
        for favorite in favorites where favorite.parallel && !JavaText.isBlank(favorite.host) {
            let key = JavaStringKey(favorite.connectionKey)
            if key == primaryKey || wanted[key] != nil { continue }
            wanted[key] = favorite
            wantedKeys.append(key)
        }
        let openKeys: Set<JavaStringKey> = Set(open.map { JavaStringKey($0) })
        var connect: [DxClusterFavorite] = []
        for key in wantedKeys where !openKeys.contains(key) {
            if let favorite = wanted[key] {
                connect.append(favorite)
            }
        }
        var disconnect: [String] = []
        for key in openKeys where wanted[key] == nil {
            disconnect.append(key.text ?? "")
        }
        disconnect.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        return Plan(toConnect: connect, toDisconnect: disconnect)
    }
}
