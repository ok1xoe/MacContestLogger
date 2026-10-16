import Foundation

/// `docs/screenshots.json`: every screenshot of the user guide (`docs/img/<name>.png`, English `docs/img/en/<name>.png`)
/// with the window and state it shows, its window size in points and its languages. `rendered` = the offscreen
/// renderer can produce it already; the others are still the older captures.
struct ShotManifest: Decodable {

    struct Shot: Decodable, Equatable {
        /// The image name without `.png`.
        let name: String
        /// The window the renderer shows (`ShotRenderer.windows`).
        let window: String
        /// What the image shows (for maintainers; the demo state is in `ShotDemo`).
        let state: String
        let width: Double
        let height: Double
        let languages: [String]
        let rendered: Bool
    }

    let shots: [Shot]

    static var file: URL {
        ShotDemo.repository.appendingPathComponent("docs/screenshots.json")
    }

    static func load() throws -> ShotManifest {
        try JSONDecoder().decode(ShotManifest.self, from: Data(contentsOf: file))
    }
}
