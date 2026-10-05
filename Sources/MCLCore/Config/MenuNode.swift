import Foundation

/// Menu tree node (see `menu.json`). `label == nil` → default label by `id`
/// (see `DefaultMenu.labelFor`).
///
/// The recursive tree does not need `indirect` — `children` is an array, which Swift
/// stores outside the struct's size (on the heap), so the type can refer to itself
/// without infinite size.
///
/// A small deviation from Java: `encode(to:)` is synthesized, so `label ==
/// nil` is written to JSON by omitting the key (Jackson would write `"label":
/// null`). Both sides read the same — `init(from:)` takes a missing key and an
/// explicit `null` for `label` the same (default `nil`) — it is only about the shape of the
/// written file, not about behaviour.
public struct MenuNode: Codable, Equatable, Sendable {
    public var id: String = ""
    public var label: String?
    public var state: MenuState = .enable
    public var children: [MenuNode] = []

    enum CodingKeys: String, CodingKey { case id, label, state, children }

    public init() {}

    public init(id: String, label: String? = nil, state: MenuState = .enable, children: [MenuNode] = []) {
        self.id = id
        self.label = label
        self.state = state
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuNode()
        id = c.value(.id, default: d.id)
        label = c.value(.label, default: d.label)
        state = c.value(.state, default: d.state)
        children = c.value(.children, default: d.children)
    }
}
