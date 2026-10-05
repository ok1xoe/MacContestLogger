/// `gridLatLon` (`ui/configurer/StationTab.kt:121-127`): latitude and longitude of the locator centre as
/// `String.format(Locale.US, "%.4f", …)`, or `nil` for an invalid or empty locator. Used by the Station tab
/// (display) and by `ConfigurerDraft.applied(to:now:)` (`station.latitude`/`longitude`).
public enum GridLatLon {

    public static func of(_ grid: String) -> (latitude: String, longitude: String)? {
        guard let center = Maidenhead.centerLatLon(grid) else { return nil }
        let lat: String = JavaFormat.format("%.4f", .double(center.lat))
        let lon: String = JavaFormat.format("%.4f", .double(center.lon))
        return (lat, lon)
    }
}
