import Foundation

/// Offline locator database by callsign (Java `hamqth.GridDatabase`; CSV `znacka;lokator;pocet`,
/// e.g. from historical WW-DIGI logs). A fast grid source without a network; HamQTH serves as a fallback.
///
/// Key = callsign `trim().toUpperCase()` (port convention: `uppercased()`), equality by UTF-16
/// units like a Java `HashMap`; the **first** occurrence of a callsign wins (`putIfAbsent`); a line
/// with an empty callsign or locator is skipped. For the file format see `CallsignGridCsv`.
public struct GridDatabase: Sendable {

    private let byCall: [JavaStringKey: String]

    private init(_ byCall: [JavaStringKey: String]) {
        self.byCall = byCall
    }

    /// Empty database (when the file is missing).
    public static let empty = GridDatabase([:])

    /// Grid of a callsign, or `nil` (`nil`/`isBlank` callsign → `nil`).
    public func grid(_ call: String?) -> String? {
        guard let call, !JavaText.isBlank(call) else { return nil }
        return byCall[JavaStringKey(JavaText.trim(call).uppercased())]
    }

    public var size: Int {
        byCall.count
    }

    /// Loads `<contestDataDir>/multipliers/ww_digi_grid.csv` (Java `Files.isRegularFile`), otherwise
    /// an empty database (also on a read error).
    public static func fromDir(_ contestDataDir: URL?) -> GridDatabase {
        guard let contestDataDir else { return empty }
        let file = CallsignGridCsv.file(in: contestDataDir)
        guard BandPlan.isRegularFile(file), let data = try? Data(contentsOf: file) else {
            return empty
        }
        return fromCsv(data)
    }

    /// Java `fromCsv(InputStream)` over the whole content.
    public static func fromCsv(_ data: Data) -> GridDatabase {
        var map: [JavaStringKey: String] = [:]
        for row in CallsignGridCsv.rows(data) {
            let call = row.call.uppercased()
            if !call.isEmpty && !row.grid.isEmpty {
                let key = JavaStringKey(call)
                if map[key] == nil {
                    map[key] = row.grid
                }
            }
        }
        return GridDatabase(map)
    }
}
