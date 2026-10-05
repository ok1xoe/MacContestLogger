import Testing
@testable import MCLCore

/// `RotorAzimuth` against `AppState.azimuthTo` (`AS:800-806`) and the rotator texts (`AS:667-763`), the numbers from
/// the probe `rig-keying` (`azimuth`, `rotor`).
@Suite struct RotorAzimuthTests {

    /// Resolves every call to one entity with the given coordinates.
    struct FixedLookup: DxccLookup {
        let entity: DxccEntity?

        init(lat: Double, lon: Double) {
            entity = DxccEntity(entityCode: 1, name: "X", countryCode: "X", continents: ["EU"], cq: [15], itu: [28],
                                lat: lat, lon: lon)
        }

        init(entity: DxccEntity?) {
            self.entity = entity
        }

        func resolve(_ callsign: String?) -> DxccEntity? { entity }
        func entities() -> [DxccEntity] { entity.map { [$0] } ?? [] }
    }

    @Test func azimuthMatchesTheJvm() throws {
        let rows = RigKeyingProbeTable.area("azimuth")
        #expect(rows.count == 48)
        for row in rows {
            let parts = row.input.split(separator: " ").map(String.init)
            let lat = try #require(Double(parts[1]))
            let lon = try #require(Double(parts[2]))
            let azimuth = RotorAzimuth.to(call: "W1AW", grid: parts[0], dxcc: FixedLookup(lat: lat, lon: lon))
            #expect(azimuth.map(String.init) == row.result, "\(row.input)")
        }
    }

    @Test func azimuthNeedsACallAGridAndAnEntityWithCoordinates() {
        let lookup = FixedLookup(lat: 40, lon: -75)
        #expect(RotorAzimuth.to(call: " ", grid: "JO70", dxcc: lookup) == nil)
        #expect(RotorAzimuth.to(call: "W1AW", grid: "", dxcc: lookup) == nil)
        #expect(RotorAzimuth.to(call: "W1AW", grid: "JO70", dxcc: nil) == nil)
        #expect(RotorAzimuth.to(call: "W1AW", grid: "JO70", dxcc: FixedLookup(entity: nil)) == nil)
        #expect(RotorAzimuth.to(call: "W1AW", grid: "JO70", dxcc: FixedLookup(lat: .nan, lon: 0)) == nil)
        #expect(RotorAzimuth.to(call: "W1AW", grid: "JO70", dxcc: lookup) == 298)
    }

    @Test func degreesAndLongPathMatchTheJvm() throws {
        let rows = RigKeyingProbeTable.area("rotor")
        #expect(rows.count == 10)
        for row in rows {
            let value = row.input == "NaN" ? Double.nan : try #require(Double(row.input))
            let text = String(RotorAzimuth.degrees(value)) + " "
                + String(RotorAzimuth.degrees(RotctldClient.longPath(value)))
            #expect(text == row.result, "\(row.input)")
        }
    }

    @Test func targetFallsBackToTheLastQso() {
        #expect(RotorAzimuth.target(call: "OK1ABC", lastQsoCall: "W1AW") == "OK1ABC")
        #expect(RotorAzimuth.target(call: "  ", lastQsoCall: "W1AW") == "W1AW")
        #expect(RotorAzimuth.target(call: "", lastQsoCall: nil) == "")
        #expect(RotorAzimuth.heading(90, longPath: false) == 90)
        #expect(RotorAzimuth.heading(90, longPath: true) == 270)
        #expect(RotorAzimuth.heading(300, longPath: true) == 120)
    }

    @Test func udpBandIsTheLowerEdgeInMegahertz() {
        #expect(RotorAzimuth.udpBandMhz(nil) == 0)
        #expect(RotorAzimuth.udpBandMhz(.m20) == 14)
        #expect(RotorAzimuth.udpBandMhz(.m160) == 1)
        // Post-port microwave bands: the lower edge in MHz.
        #expect([Band.cm23, .cm13, .cm9, .cm6, .cm3].map { RotorAzimuth.udpBandMhz($0) }
                == [1240, 2300, 3300, 5650, 10000])
    }

    @Test func rotatorTexts() {
        #expect(RotorAzimuth.notConfigured == .tr("Rotátor nenastaven"))
        #expect(RotorAzimuth.pollStatus(host: " ", port: 7001, azimuth: 10).czech
                == "Rotátor nenastaven (Nastavení → Antennas)")
        #expect(RotorAzimuth.pollStatus(host: "127.0.0.1", port: 7001, azimuth: nil).czech
                == "Rotátor nedostupný (127.0.0.1:7001)")
        #expect(RotorAzimuth.pollStatus(host: "127.0.0.1", port: 7001, azimuth: 0).czech
                == "Rotátor 127.0.0.1:7001")
        #expect(RotorAzimuth.udpTurned(-0.5).czech == "Rotátor (UDP) → 359°")
        #expect(RotorAzimuth.turned(725.7).czech == "Rotátor → 5°")
        #expect(RotorAzimuth.failure("refused").czech == "Rotátor: refused")
        #expect(RotorAzimuth.unknownAzimuth("W1AW").czech
                == "Rotátor: azimut k „W1AW“ neznám (chybí lokátor stanice nebo země)")
        #expect(RotorAzimuth.udpFailure("x").czech == "Rotátor UDP: x")
        #expect(RotorAzimuth.udpStopped.czech == "Rotátor (UDP) zastaven")
        #expect(RotorAzimuth.stopped.czech == "Rotátor zastaven")
        #expect(RotorAzimuth.noClient == "rotátor není nastavený nebo dostupný")
    }
}
