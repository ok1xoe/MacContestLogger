import Foundation

/// What `SpotFilter` needs from the analysis: the contest's "can this spot be worked" and where the spotter is.
extension SpotAnalyzer {

    /// Where a spotter is: its continent and whether it sits in my own DXCC entity.
    public struct SpotterOrigin: Equatable, Sendable {
        public let continent: String?
        public let isMyCountry: Bool
    }

    /// `true` outside a contest. In a contest the spot's band must be one of the definition's bands (when it lists
    /// any) and its mode category one of the definition's modes (`isColorRelevant`: an undeterminable mode passes).
    /// A spot without a band cannot be checked and passes. Dupes are workable.
    public func isWorkable(_ spot: DxSpot) -> Bool {
        guard let definition else { return true }
        var allowed: Set<Band> = []
        for case let name? in definition.bands ?? [] {
            if let band = Band.from(adif: name) { allowed.insert(band) }
        }
        if let band = spot.band, !allowed.isEmpty, !allowed.contains(band) { return false }
        return isColorRelevant(spot)
    }

    /// The spotter's location from its call (`-#` / `-n` skimmer and SSID suffixes stripped); `nil` when the DXCC
    /// lookup does not know it.
    public func spotterOrigin(_ spot: DxSpot) -> SpotterOrigin? {
        guard let dxcc, let entity = dxcc.resolve(Self.baseCall(spot.spotter)) else { return nil }
        let mine: DxccEntity? = dxcc.resolve(myCall)
        return SpotterOrigin(continent: entity.primaryContinent,
                             isMyCountry: mine.map { $0.entityCode == entity.entityCode } ?? false)
    }

    /// `DL1ABC-2` / `W3LPL-#` -> `DL1ABC` / `W3LPL`.
    static func baseCall(_ spotter: String) -> String {
        let call: String = JavaText.trim(spotter).uppercased()
        guard let dash = call.lastIndex(of: "-") else { return call }
        let suffix = call[call.index(after: dash)...]
        if suffix == "#" || (!suffix.isEmpty && suffix.allSatisfy(\.isASCII) && suffix.allSatisfy(\.isNumber)) {
            return String(call[..<dash])
        }
        return call
    }
}
