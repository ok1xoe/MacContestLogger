import Foundation

/// Root of `menu.json`: the tree of top-level nodes.
public struct MenuConfig: Codable, Equatable, Sendable {
    public var menu: [MenuNode] = []

    enum CodingKeys: String, CodingKey { case menu }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuConfig()
        menu = c.value(.menu, default: d.menu)
    }
}
