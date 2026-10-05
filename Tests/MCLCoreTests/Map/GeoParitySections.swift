import Foundation
@testable import MCLCore

/// Swift side of the `geo.*` and `adifudp.FILT` sections of the network reference (maintainer-only probe, format documented with the probe):
/// for the input fields of an `in` row it produces the fields of an `out` row with the same notation as the generator. Called by the gate
/// `JavaNetParityTests`.
///
/// Fields with the prefix `r` are **continuous** (`double` passed through libm) and are compared with the tolerance `matches`, the others
/// exactly (sunrise/sunset seconds, day/night, band levels, bits of the subsolar longitude, `float` bits of the map).
enum GeoParitySections {

    static let names: [String] = [
        "geo.SUN", "geo.TERM", "geo.FOF2", "geo.PROP", "geo.FCST", "geo.WMAP", "adifudp.FILT",
    ]

    /// Tolerance of continuous values: relative 1e-11, at zero absolute 1e-11 (measured maximum 2.6e-13 for short routes,
    /// otherwise ≤ 3.3e-15; margin ~40× for the libm of another macOS version in CI — a change of the constant or formula gives an error orders of magnitude larger). HotSpot's `Math.sin`/`Math.cos` are
    /// intrinsics and Darwin libm differs from them by units up to thousands of ulp (most at elevation near zero, where
    /// the ulp is small —: max 8,023 ulp elevation, 186 ulp MUF). Discrete results derived from them
    /// nevertheless match exactly and the gate compares those without tolerance.
    static let tolerance: Double = 1e-11

    /// Tolerance of the continuous fields of `geo.PROP` for a **degenerate route** (Java length below `degenerateKm`; in the reference
    /// only identical ends — lengths 0, 9.5e-5 and 1.3e-4 km). `distanceKm` is the `acos` of the cosine law and `acos` is badly conditioned
    /// at 1: a 1 ulp difference in the argument gives `sqrt(2 ulp)` ≈ 1.5e-8 rad, i.e. 0 against 9.5e-5 km. The length
    /// is therefore compared absolutely (`degenerateKmTolerance`), the other continuous fields (route midpoint, MUF, LUF)
    /// relatively `degenerateTolerance`. Band levels still match exactly (without tolerance).
    static let degenerateTolerance: Double = 1e-6
    static let degenerateKmTolerance: Double = 2e-4
    static let degenerateKm: Double = 10

    enum Failure: Error, CustomStringConvertible {
        case malformed(String)
        var description: String {
            switch self {
            case .malformed(let why): "malformed reference input: \(why)"
            }
        }
    }

    /// Output fields for section `name` and input row `path` with fields `f`.
    static func output(_ name: String, _ path: String, _ f: [String]) throws -> [String] {
        switch name {
        case "geo.SUN": return try sun(f)
        case "geo.TERM": return try terminator(f)
        case "geo.FOF2": return try fof2(f)
        case "geo.PROP": return try propagation(f)
        case "geo.FCST": return try forecast(f)
        case "geo.WMAP": return try worldMap(path, f)
        case "adifudp.FILT": return try adifFilter(f)
        default: throw Failure.malformed("unknown section \(name)")
        }
    }

    // MARK: - Comparison

    /// Match of output fields: continuous (`r` + 16 hex) with tolerance, others exactly.
    static func matches(_ section: String, _ java: [String], _ swift: [String]) -> Bool {
        guard java.count == swift.count else { return false }
        var degenerate: Bool = false
        if section == "geo.PROP", java.count > 1, let km = continuous(java[1]), abs(km) < degenerateKm {
            degenerate = true
        }
        for index in java.indices where java[index] != swift[index] {
            guard let a = continuous(java[index]), let b = continuous(swift[index]) else { return false }
            if degenerate && index == 1 {
                guard abs(a - b) <= degenerateKmTolerance else { return false }
                continue
            }
            guard close(a, b, degenerate ? degenerateTolerance : tolerance) else { return false }
        }
        return true
    }

    static func continuous(_ field: String) -> Double? {
        guard field.utf8.count == 17, field.hasPrefix("r"), let raw = UInt64(field.dropFirst(), radix: 16) else {
            return nil
        }
        return Double(bitPattern: raw)
    }

    static func close(_ a: Double, _ b: Double, _ limit: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        if a.isInfinite || b.isInfinite { return a == b }
        let scale: Double = Swift.max(1, Swift.max(abs(a), abs(b)))
        return abs(a - b) <= limit * scale
    }

    // MARK: - Helpers

    static func num(_ text: String) throws -> Double {
        guard let value = JavaDouble.parseDouble(text) else { throw Failure.malformed("double \(text)") }
        return value
    }

    static func long(_ text: String) throws -> Int64 {
        guard let value = Int64(text) else { throw Failure.malformed("long \(text)") }
        return value
    }

    /// Bits like the generator: NaN canonically (`Double.doubleToLongBits` → `7ff8000000000000`).
    static func bits(_ d: Double) -> String {
        let pattern: UInt64 = d.isNaN ? 0x7FF8_0000_0000_0000 : d.bitPattern
        let raw = String(pattern, radix: 16)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }

    static func r(_ d: Double) -> String {
        "r" + bits(d)
    }

    static func floatBits(_ f: Float) -> String {
        let raw = String(f.bitPattern, radix: 16)
        return String(repeating: "0", count: 8 - raw.count) + raw
    }

    static func levels(_ row: (Band) -> PropagationModel.Level?) -> String {
        var out: String = ""
        for band in Band.javaV111Cases {
            out += row(band).map { String($0.rawValue) } ?? "?"
        }
        return out
    }

    // MARK: - Sections

    static func sun(_ f: [String]) throws -> [String] {
        let t = SolarTimes.forLocation(try num(f[0]), try num(f[1]), epochDay: try long(f[2]))
        guard let t else { return ["~"] }
        return [String(t.sunrise), String(t.sunset)]
    }

    static func terminator(_ f: [String]) throws -> [String] {
        let lat: Double = try num(f[0])
        let lon: Double = try num(f[1])
        let ms: Int64 = try long(f[2])
        let ss = SolarTerminator.subsolar(epochMillis: ms)
        let night: String = SolarTerminator.isNight(lat, lon, epochMillis: ms) ? "1" : "0"
        return [night, r(SolarTerminator.elevation(lat, lon, ss)), r(ss.lat), bits(ss.lon)]
    }

    static func fof2(_ f: [String]) throws -> [String] {
        [r(PropagationModel.foF2(try num(f[0]), try num(f[1])))]
    }

    static func propagation(_ f: [String]) throws -> [String] {
        let lat1: Double = try num(f[0])
        let lon1: Double = try num(f[1])
        let lat2: Double = try num(f[2])
        let lon2: Double = try num(f[3])
        let ms: Int64 = try long(f[5])
        let ssn: Double = PropagationModel.ssnFromSfi(try num(f[4]))
        let dist: Double = PropagationModel.distanceKm(lat1, lon1, lat2, lon2)
        let mid = PropagationModel.pointAt(lat1, lon1, lat2, lon2, km: dist / 2)
        let muf: Double = PropagationModel.muf(lat1, lon1, lat2, lon2, epochMillis: ms, ssn: ssn)
        let luf: Double = PropagationModel.luf(lat1, lon1, lat2, lon2, epochMillis: ms)
        let row: String = levels { PropagationModel.level($0, muf: muf, luf: luf) }
        return [bits(ssn), r(dist), r(mid.lat), r(mid.lon), r(muf), r(luf), row]
    }

    static func forecast(_ f: [String]) throws -> [String] {
        let seconds: Int64 = try long(f[5])
        let nanos: Int64 = try long(f[6])
        let from = Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9)
        let rows: [[Band: PropagationModel.Level]] = PropagationModel.forecast(
            try num(f[0]), try num(f[1]), try num(f[2]), try num(f[3]),
            from: from, ssn: try num(f[4]), bands: Band.javaV111Cases)
        return rows.map { row in levels { row[$0] } }
    }

    static func adifFilter(_ f: [String]) throws -> [String] {
        let datagram: [UInt8] = try WsjtxParitySections.unhex(f[0])
        return [JavaIoParityFixture.tx(AdifUdpFilter.adif(from: datagram))]
    }

    static func worldMap(_ path: String, _ f: [String]) throws -> [String] {
        let data: Data
        if path.hasPrefix("b") {
            data = Data(try WsjtxParitySections.unhex(f[0]))
        } else {
            data = Data((JavaIoParityFixture.untx(f[0]) ?? "").utf8)
        }
        let geo: WorldMapGeo = WorldMapGeo.fromData(data)
        var out: [String] = [String(geo.rings.count)]
        for (ring, group) in zip(geo.rings, geo.ringGroups) {
            var field: String = String(group)
            for value in ring {
                field += ":" + floatBits(value)
            }
            out.append(field)
        }
        return out
    }
}
