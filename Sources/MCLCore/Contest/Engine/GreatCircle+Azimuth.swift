extension GreatCircle {

    /// The whole-degree azimuth to a call's DXCC entity, as v1.1.1 computes it in three places (the bandmap label
    /// `BM:120-126`, the contest controller's `azimuthTo` `CC:716-723` and the rotator's `azimuthTo` `AS:800-806`):
    /// `Math.round(bearingDeg(origin, entity)).toInt()` — Java rounding (half up, NaN → 0, clamped to `long`), then
    /// Kotlin's `Long.toInt()` truncation, so 360 is possible. `nil` without an origin, an entity or its coordinates.
    public static func azimuth(from origin: (lat: Double, lon: Double)?, toCall call: String,
                               dxcc: (any DxccLookup)?) -> Int? {
        guard let origin, let entity = dxcc?.resolve(call), entity.hasLatLon else { return nil }
        let bearing: Double = bearingDeg(origin.lat, origin.lon, entity.lat, entity.lon)
        return Int(Int32(truncatingIfNeeded: JavaMath.round(bearing)))
    }
}
