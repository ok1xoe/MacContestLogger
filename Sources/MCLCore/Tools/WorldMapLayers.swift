/// N1MM Grayline window setup: the optional layers (Sun, Equator, Greenwich meridian, home location), the number of the
/// most recent spots drawn and „Clear All Spots".
public enum WorldMapLayer: String, CaseIterable, Sendable {
    case sun
    case equator
    case meridian
    case home

    /// The Czech menu key of the layer.
    public var titleKey: String {
        switch self {
        case .sun: return "Zobrazit Slunce"
        case .equator: return "Zobrazit rovník"
        case .meridian: return "Zobrazit nultý poledník"
        case .home: return "Zobrazit domácí polohu"
        }
    }

    /// The layers shown by default (the map before the options: the Sun and the station).
    public static let defaults: [String] = [WorldMapLayer.sun.rawValue, WorldMapLayer.home.rawValue]
}

extension WorldMapModel {

    /// N1MM „Number of Spots to Display" (0, 50, 100, 150, 200); `-1` = every spot (MCL's default).
    public static let spotCountOptions: [Int] = [-1, 0, 50, 100, 150, 200]

    /// The spots the map draws: those not cleared, of them the `count` most recent (`spots` is in arrival order,
    /// the newest last); a negative count keeps them all.
    public static func shownSpots(_ spots: [DxSpot], count: Int, cleared: Set<DxSpot>) -> [DxSpot] {
        let kept: [DxSpot] = cleared.isEmpty ? spots : spots.filter { !cleared.contains($0) }
        guard count >= 0 else { return kept }
        return Array(kept.suffix(count))
    }

    /// The horizontal pixel of the Greenwich meridian (the map is centred on the station's longitude).
    public func meridianX(width: Float) -> Float {
        px(lon: 0, width: width)
    }

    /// The vertical pixel of the Equator.
    public func equatorY(height: Float) -> Float {
        py(lat: 0, height: height)
    }
}
