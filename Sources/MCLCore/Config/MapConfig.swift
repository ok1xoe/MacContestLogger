import Foundation

/// Appearance settings of the „Čtverce v mapě" window: the base-map colour scheme (`scheme`)
/// and the toggle of political shading of individual countries (`political`). Mirrors
/// `MapConfig.java`.
public struct MapConfig: Codable, Equatable, Sendable {
    public static let defaultScheme = "green"

    /// Empty or whitespace only → `defaultScheme` (same as the Java getter/setter).
    ///
    /// Note: `didSet` does not fire on the first assignment inside the type's own init, so
    /// both initializers normalize `scheme` explicitly via `MapConfig.normalizedScheme`.
    public var scheme: String = MapConfig.defaultScheme {
        didSet {
            let normalized = MapConfig.normalizedScheme(scheme)
            if normalized != scheme { scheme = normalized }
        }
    }
    public var political: Bool = false

    enum CodingKeys: String, CodingKey { case scheme, political }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MapConfig()
        scheme = MapConfig.normalizedScheme(c.value(.scheme, default: d.scheme))
        political = c.value(.political, default: d.political)
    }

    private static func normalizedScheme(_ value: String) -> String {
        JavaText.isBlank(value) ? defaultScheme : value // Java `isBlank()`
    }
}
