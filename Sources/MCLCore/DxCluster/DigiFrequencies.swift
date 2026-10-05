import Foundation

/// Frequency ranges of digital modes (FT8, FT4, JT65) — Java `dxcluster.DigiFrequencies`. A spot
/// within the range `[low, high]` of some channel is that mode, even if the comment does not say so; the first match wins.
///
/// The table can be supplied externally in `<contestDataDir>/digi_frequencies.yaml` (`fromDir`); without the file, on a
/// read error and without a usable channel the built-in `defaultTable()` is used (FT8 13, FT4 9, JT65 8
/// channels, dial − 500 … dial + 3 000 Hz).
public struct DigiFrequencies: Sendable {

    private struct Channel: Sendable {
        let mode: String
        let lowHz: Int64
        let highHz: Int64
    }

    private let channels: [Channel]

    private init(_ channels: [Channel]) {
        self.channels = channels
    }

    /// Mode of a digital channel at the given frequency (FT8/FT4/JT65…), or `nil`.
    public func modeAt(_ freqHz: Int) -> String? {
        let freq = Int64(freqHz)
        for channel in channels where freq >= channel.lowHz && freq <= channel.highHz {
            return channel.mode
        }
        return nil
    }

    /// Is the frequency within any digital sub-band?
    public func isDigi(_ freqHz: Int) -> Bool {
        modeAt(freqHz) != nil
    }

    /// Built-in table. Ranges from dial frequencies (dial − 0.5 … dial + 3 kHz), because FT stations
    /// transmit in the 0–3 kHz audio band above the dial.
    public static func defaultTable() -> DigiFrequencies {
        var channels: [Channel] = []
        let ft8: [Int64] = [1_840, 3_573, 5_357, 7_074, 10_136, 14_074, 18_100, 21_074,
                            24_915, 28_074, 50_313, 70_154, 144_174]
        let ft4: [Int64] = [3_575, 7_047, 10_140, 14_080, 18_104, 21_140, 24_919, 28_180, 50_318]
        let jt65: [Int64] = [1_838, 3_570, 7_076, 10_138, 14_076, 21_076, 28_076, 50_310]
        addAll(&channels, "FT8", ft8)
        addAll(&channels, "FT4", ft4)
        addAll(&channels, "JT65", jt65)
        return DigiFrequencies(channels)
    }

    private static func addAll(_ out: inout [Channel], _ mode: String, _ dialsKhz: [Int64]) {
        for dial in dialsKhz {
            let dialHz: Int64 = dial * 1000
            out.append(Channel(mode: mode, lowHz: dialHz - 500, highHz: dialHz + 3_000))
        }
    }

    /// Loads `<contestDataDir>/digi_frequencies.yaml`, otherwise the built-in table.
    ///
    /// As Java: reading and binding via Jackson (`DigiFreqDto`, coercion of numbers from text), a channel without a mode
    /// (Java `isBlank`) or without bounds is skipped, the mode is trimmed with `trim()`, bounds `Math.round(kHz × 1000)`
    /// (`NaN` → 0, saturation); any error → the built-in table.
    public static func fromDir(_ contestDataDir: URL?) -> DigiFrequencies {
        guard let contestDataDir else { return defaultTable() }
        let file = contestDataDir.appendingPathComponent(DigiFreqDto.fileName)
        guard BandPlan.isRegularFile(file) else { return defaultTable() }
        guard let dto = try? DigiFreqDto.read(file), let list = dto.channels, !list.isEmpty else {
            return defaultTable()
        }
        var channels: [Channel] = []
        for maybe in list {
            guard let c = maybe, let mode = c.mode, !JavaText.isBlank(mode),
                  let from = c.fromKhz, let to = c.toKhz else { continue }
            channels.append(Channel(mode: JavaText.trim(mode), lowHz: JavaMath.round(from * 1000.0),
                                    highHz: JavaMath.round(to * 1000.0)))
        }
        if channels.isEmpty {
            return defaultTable()
        }
        return DigiFrequencies(channels)
    }
}

/// Java DTO `DigiFrequencies.Dto`/`DigiFreqFile.Dto` (`channels: List<Ch>`, `Ch {String mode;
/// Double fromKhz; Double toKhz}`) read by Jackson: unknown keys are ignored, a type error fails the whole
/// read, `Double` is an **object** (empty text → `null`).
struct DigiFreqDto: YamlRecord {

    static let fileName = "digi_frequencies.yaml"

    struct Ch: YamlRecord {
        let mode: String?
        let fromKhz: Double?
        let toKhz: Double?

        init(yaml object: YamlObject) {
            mode = object.string("mode")
            fromKhz = object.double("fromKhz")
            toKhz = object.double("toKhz")
        }
    }

    let channels: [Ch?]?

    init(yaml object: YamlObject) {
        channels = object.list("channels", of: Ch.self)
    }

    /// Java `mapper.readValue(Files.newInputStream(file), Dto.class)`; `nil` = the `null` document.
    static func read(_ file: URL) throws -> DigiFreqDto? {
        try YamlDecoder.decode(DigiFreqDto.self, from: try Utf8Text.readFile(file))
    }
}
