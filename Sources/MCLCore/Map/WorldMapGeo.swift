import Foundation

/// Outlines of the world map for drawing (the base of the Squares-in-map window). Loads polygons
/// from GeoJSON (`~/dxcc-world-map/dxcc.geojson`) into flat arrays `[lon0, lat0, lon1, lat1, …]`.
/// Port of Java `map/WorldMapGeo`.
///
/// Each ring also carries a `group` — the ordinal of the source feature (DXCC entity); rings of the same
/// country have the same group (political colouring).
///
/// JSON is read by the Jackson-style reader `DxccJson` (the same deviations from the RFC as `readTree`: BOM,
/// content after the end of the document, duplicate key = last value at the position of the first occurrence,
/// depth and number length limits). The traversal rules are Java's and measured (reference section
/// `geo.WMAP`):
/// - `features` must be an array; traversing a container that is not an array goes over the **object
///   values** (Java `for (JsonNode x : objectNode)`), a scalar is empty;
/// - only `geometry.type` `"Polygon"`/`"MultiPolygon"` (and non-null `coordinates`) increments the group;
/// - a ring must be an array with at least 2 elements and **each** of its elements an array with at least 2 elements, otherwise
///   the whole ring is dropped;
/// - coordinates go through `JsonNode.asDouble()` (a number; text via `Double.parseDouble` after
///   `trim`, otherwise 0; `true` = 1; `null`/container = 0; the integer `-0` is `+0`) and `(float)`;
/// - a read error → empty.
///
/// Deliberate divergence of the reader: a lone surrogate in an escape (`"\ud800"`) Java accepts, here
/// it is an error of the whole file → empty map (see `DxccJson`).
public struct WorldMapGeo: Sendable {

    /// Ring = flat array `[lon0, lat0, lon1, lat1, …]` in degrees.
    public let rings: [[Float]]
    /// Group (`>= 0`) of the i-th ring — ordinal of the source DXCC entity. Parallel to `rings`.
    public let ringGroups: [Int32]

    public static let empty = WorldMapGeo(rings: [], ringGroups: [])

    /// Loads from `~/dxcc-world-map/dxcc.geojson`, otherwise empty. Like `Files.isRegularFile` (a symlink is
    /// followed) it takes only a regular file — a FIFO or socket is not opened, reading would block.
    public static func loadDefault(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> WorldMapGeo {
        let file: URL = home.appendingPathComponent("dxcc-world-map").appendingPathComponent("dxcc.geojson")
        let values = try? file.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true, let data = try? Data(contentsOf: file) else {
            return empty
        }
        return fromData(data)
    }

    /// Java `fromStream`: parses the content, a read error → empty.
    public static func fromData(_ data: Data) -> WorldMapGeo {
        guard let root = try? DxccJson.parse(data, message: "dxcc.geojson") else {
            return empty
        }
        var rings: [[Float]] = []
        var groups: [Int32] = []
        guard let features = member(root, "features"), case .array(let items) = features else {
            return WorldMapGeo(rings: rings, ringGroups: groups)
        }
        var gid: Int32 = 0
        for feature in items {
            guard let geometry = member(feature, "geometry") else { continue }
            let type: String = text(member(geometry, "type"))
            guard let coordinates = member(geometry, "coordinates") else { continue }
            if type == "Polygon" {
                for ring in children(coordinates) {
                    addRing(&rings, &groups, gid, ring)
                }
            } else if type == "MultiPolygon" {
                for polygon in children(coordinates) {
                    for ring in children(polygon) {
                        addRing(&rings, &groups, gid, ring)
                    }
                }
            } else {
                continue
            }
            gid &+= 1
        }
        return WorldMapGeo(rings: rings, ringGroups: groups)
    }

    private static func addRing(_ out: inout [[Float]], _ groups: inout [Int32], _ gid: Int32, _ ring: DxccJson.Value) {
        guard case .array(let points) = ring, points.count >= 2 else { return }
        var pts: [Float] = []
        pts.reserveCapacity(points.count * 2)
        for point in points {
            guard case .array(let pair) = point, pair.count >= 2 else { continue }
            pts.append(Float(asDouble(pair[0]))) // lon
            pts.append(Float(asDouble(pair[1]))) // lat
        }
        if pts.count == points.count * 2 {
            out.append(pts)
            groups.append(gid)
        }
    }

    /// `JsonNode.get(name)`: the value of an object key (the last one for duplicates), otherwise `nil`.
    private static func member(_ node: DxccJson.Value, _ name: String) -> DxccJson.Value? {
        guard case .object(let object) = node else { return nil }
        return object.entries.last(where: { $0.key == name })?.value
    }

    /// Java iteration `for (JsonNode x : node)`: array elements, object values (order of the first
    /// occurrence of the key, value of the last — `LinkedHashMap.put`), nothing for a scalar.
    private static func children(_ node: DxccJson.Value) -> [DxccJson.Value] {
        switch node {
        case .array(let items):
            return items
        case .object(let object):
            var order: [String] = []
            var values: [String: DxccJson.Value] = [:]
            for entry in object.entries {
                if values.updateValue(entry.value, forKey: entry.key) == nil {
                    order.append(entry.key)
                }
            }
            return order.map { values[$0]! }
        default:
            return []
        }
    }

    /// `node.path("type").asText("")` — it is enough to tell a text value apart; other nodes
    /// cannot come out as `"Polygon"`/`"MultiPolygon"`.
    private static func text(_ node: DxccJson.Value?) -> String {
        if case .some(.string(let value)) = node { return value }
        return ""
    }

    /// `JsonNode.asDouble()` (Jackson 2.22, measured).
    static func asDouble(_ node: DxccJson.Value) -> Double {
        switch node {
        case .number(let text, let isInteger):
            let value: Double = JavaDouble.parseDouble(text) ?? 0
            // An integer literal is `IntNode`/`LongNode`/`BigIntegerNode`: `-0` is zero without a sign.
            return isInteger && value == 0 ? 0 : value
        case .string(let raw):
            return JavaDouble.parseDouble(raw) ?? 0
        case .bool(let flag):
            return flag ? 1 : 0
        case .null, .array, .object:
            return 0
        }
    }
}
