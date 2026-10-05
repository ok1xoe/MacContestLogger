import Foundation

/// Reading/writing `digi_frequencies.yaml` for editing in the UI (Java `dxcluster.DigiFreqFile`): a list of channels
/// mode + range in kHz. The format corresponds to `DigiFrequencies`.
public enum DigiFreqFile {

    /// Java record `Channel(String mode, double fromKhz, double toKhz)`: `double` equality as
    /// `Double.compare` (`NaN == NaN`, `0.0 != -0.0`).
    public struct Channel: Sendable, Hashable {
        public let mode: String
        public let fromKhz: Double
        public let toKhz: Double

        public init(mode: String, fromKhz: Double, toKhz: Double) {
            self.mode = mode
            self.fromKhz = fromKhz
            self.toKhz = toKhz
        }

        public static func == (lhs: Channel, rhs: Channel) -> Bool {
            guard JavaText.equals(lhs.mode, rhs.mode) else { return false }
            return bits(lhs.fromKhz) == bits(rhs.fromKhz) && bits(lhs.toKhz) == bits(rhs.toKhz)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(mode)
            hasher.combine(Self.bits(fromKhz))
            hasher.combine(Self.bits(toKhz))
        }

        /// Java `Double.doubleToLongBits` (canonical `NaN`).
        private static func bits(_ value: Double) -> UInt64 {
            value.isNaN ? 0x7FF8_0000_0000_0000 : value.bitPattern
        }
    }

    public struct Table: Sendable, Hashable {
        public let channels: [Channel]

        public init(channels: [Channel]) {
            self.channels = channels
        }
    }

    /// Reads the table; a missing directory, file or broken content gives an **empty** table (no error).
    /// A channel without a mode (Java `isBlank`) or without bounds is skipped, the mode is trimmed with `trim()`.
    public static func read(_ contestDataDir: URL?) -> Table {
        var channels: [Channel] = []
        guard let contestDataDir else { return Table(channels: channels) }
        let file = contestDataDir.appendingPathComponent(DigiFreqDto.fileName)
        guard BandPlan.isRegularFile(file), let dto = try? DigiFreqDto.read(file), let list = dto.channels else {
            return Table(channels: channels)
        }
        for maybe in list {
            guard let c = maybe, let mode = c.mode, !JavaText.isBlank(mode),
                  let from = c.fromKhz, let to = c.toKhz else { continue }
            channels.append(Channel(mode: JavaText.trim(mode), fromKhz: from, toKhz: to))
        }
        return Table(channels: channels)
    }

    /// Writes the table the way Jackson writes it (`writerWithDefaultPrettyPrinter`,
    /// `yaml-probe.txt`): `---`, mode **always quoted**, bounds with Java `Double.toString`
    /// (`14077.0`, `1.0E-5`, `NaN`, `-0.0`). The directory is created, an existing file is overwritten.
    public static func write(_ contestDataDir: URL, _ table: Table) throws {
        var items: [YamlValue] = []
        for channel in table.channels {
            var row = YamlMapping()
            row.set("mode", .string(channel.mode))
            row.set("fromKhz", .double(channel.fromKhz))
            row.set("toKhz", .double(channel.toKhz))
            items.append(.mapping(row))
        }
        var root = YamlMapping()
        root.set("channels", .sequence(items))
        try FileManager.default.createDirectory(at: contestDataDir, withIntermediateDirectories: true)
        try YamlWriter.write(.mapping(root))
            .write(to: contestDataDir.appendingPathComponent(DigiFreqDto.fileName), atomically: false, encoding: .utf8)
    }
}
