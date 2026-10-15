import Foundation
import os

/// N1MM+'s spectrum datagram (Appendices → External UDP Broadcasts → „Sending Spectrum Data to N1MM+", UDP port
/// 13064), sent by SDR programs (CW Skimmer, Waterfall Bandmap, SDR Server, KE9NS PowerSDR, Flex) and by N1MM+'s own
/// spectrum relay:
///
/// ```xml
/// <?xml version="1.0" encoding="utf-8"?>
/// <Spectrum>
///   <app>WaterfallBandmap</app>
///   <Name>N1MM SDR1</Name>
///   <LowScopeFrequency>14000</LowScopeFrequency>
///   <HighScopeFrequency>14055</HighScopeFrequency>
///   <ScalingFactor>0.3125</ScalingFactor>
///   <DataCount>475</DataCount>
///   <SpectrumData>0,0,0,1,0,…</SpectrumData>
/// </Spectrum>
/// ```
///
/// The frequencies are in kHz (the lowest and highest level), `SpectrumData` holds `DataCount` comma-separated
/// integer levels 0…65535 (whitespace between them allowed) and `ScalingFactor` turns a level into dB.
public struct SpectrumPacket: Equatable, Sendable {
    public static let defaultPort = 13_064

    public let app: String
    /// The source name the receiving window picks.
    public let name: String
    public let lowKHz: Double
    public let highKHz: Double
    public let scalingFactor: Double
    public let levels: [Int]

    public init(app: String, name: String, lowKHz: Double, highKHz: Double, scalingFactor: Double, levels: [Int]) {
        self.app = app
        self.name = name
        self.lowKHz = lowKHz
        self.highKHz = highKHz
        self.scalingFactor = scalingFactor
        self.levels = levels
    }

    /// The levels in dB on the band, ascending from the low frequency.
    public var frame: SpectrumFrame {
        let count: Int = levels.count
        let step: Double = count > 1 ? (highKHz - lowKHz) * 1_000 / Double(count - 1) : 0
        let scale: Double = scalingFactor > 0 && scalingFactor.isFinite ? scalingFactor : 1
        return SpectrumFrame(startHz: lowKHz * 1_000, stepHz: step, levelsDb: levels.map { Double($0) * scale })
    }

    /// The packet of a frame for the relay (N1MM „Broadcast on IP port(s)"): ascending frequencies, levels as
    /// `(dB − the lowest level) / scaling` clamped to 0…65535.
    public static func relay(_ frame: SpectrumFrame, name: String, app: String = "MacContestLogger",
                             scalingFactor: Double = 0.25) -> SpectrumPacket {
        var levels: [Double] = frame.levelsDb
        var low: Double = frame.hz(atBin: 0)
        var high: Double = frame.hz(atBin: Double(Swift.max(0, levels.count - 1)))
        if frame.stepHz < 0 {
            levels.reverse()
            swap(&low, &high)
        }
        let base: Double = (levels.filter(\.isFinite).min() ?? 0).rounded(.down)
        let values: [Int] = levels.map { db in
            guard db.isFinite else { return 0 }
            return Int(Swift.min(65_535, Swift.max(0, ((db - base) / scalingFactor).rounded())))
        }
        return SpectrumPacket(app: app, name: name, lowKHz: low / 1_000, highKHz: high / 1_000,
                              scalingFactor: scalingFactor, levels: values)
    }
}

/// Reading and writing `SpectrumPacket`s.
public enum SpectrumXml {

    /// The packet of a datagram; `nil` when it is not a `<Spectrum>` packet or misses a frequency or the data.
    /// A `DataCount` that disagrees with the data is ignored (the data counts); levels outside 0…65535 are clamped
    /// and a non-number level reads as 0.
    public static func parse(_ bytes: [UInt8]) -> SpectrumPacket? {
        guard let text = String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1),
              text.contains("<Spectrum") else { return nil }
        guard let lowText = element("LowScopeFrequency", in: text), let low = number(lowText),
              let highText = element("HighScopeFrequency", in: text), let high = number(highText),
              let data = element("SpectrumData", in: text) else { return nil }
        let scaling: Double = element("ScalingFactor", in: text).flatMap(number) ?? 1
        let levels: [Int] = data.split(separator: ",").compactMap { part in
            let trimmed: String = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let value = Double(trimmed), value.isFinite else { return 0 }
            return Int(Swift.min(65_535, Swift.max(0, value.rounded())))
        }
        guard !levels.isEmpty else { return nil }
        return SpectrumPacket(app: unescape(element("app", in: text) ?? ""), name: unescape(element("Name", in: text) ?? ""),
                              lowKHz: low, highKHz: high, scalingFactor: scaling, levels: levels)
    }

    /// The datagram of a packet in N1MM's layout.
    public static func serialize(_ packet: SpectrumPacket) -> [UInt8] {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Spectrum>\n"
        xml += "\t<app>" + escape(packet.app) + "</app>\n"
        xml += "\t<Name>" + escape(packet.name) + "</Name>\n"
        xml += "\t<LowScopeFrequency>" + format(packet.lowKHz) + "</LowScopeFrequency>\n"
        xml += "\t<HighScopeFrequency>" + format(packet.highKHz) + "</HighScopeFrequency>\n"
        xml += "\t<ScalingFactor>" + format(packet.scalingFactor) + "</ScalingFactor>\n"
        xml += "\t<DataCount>" + String(packet.levels.count) + "</DataCount>\n"
        xml += "\t<SpectrumData>" + packet.levels.map(String.init).joined(separator: ",") + "</SpectrumData>\n"
        xml += "</Spectrum>\n"
        return Array(xml.utf8)
    }

    /// The text between `<tag>` and `</tag>` (case-sensitive, the first occurrence).
    static func element(_ tag: String, in text: String) -> String? {
        guard let open = text.range(of: "<" + tag + ">"),
              let close = text.range(of: "</" + tag + ">", range: open.upperBound..<text.endIndex) else { return nil }
        return String(text[open.upperBound..<close.lowerBound])
    }

    private static func number(_ text: String) -> Double? {
        let value: Double? = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    /// A number without a trailing `.0` and with at most six decimals (`14000`, `14025.5`, `0.25`).
    static func format(_ value: Double) -> String {
        if value == value.rounded(), Swift.abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text: String = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// The spectrum lines of external programs (UDP 13064) as a spectrum source: every packet is recorded by its source
/// name (the names heard so far are offered to pick from); the picked source (empty = the first one heard) feeds the
/// display, its lines also make the waterfall rows (0…1 over the newest line's median, 40 dB span, like the receiver
/// audio waterfall). Thread-safe: the listener thread adds, the render lane reads.
public final class ExternalSpectrumSource: SpectrumSource {

    /// Waterfall rows kept (as the audio waterfall).
    public static let rows = 300

    private struct State {
        var selected = ""
        var current: String?
        var heard: [String] = []
        var frame: SpectrumFrame?
        var serial = 0
        var history: [[Double]] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// The source name to show (`""` = the first one heard); a change starts the lines over.
    public func select(_ name: String) {
        state.withLock { s in
            guard s.selected != name else { return }
            s.selected = name
            s.current = nil
            s.frame = nil
            s.history = []
        }
    }

    /// The name of the source shown now (`nil` before its first line).
    public var currentName: String? {
        state.withLock { $0.current }
    }

    /// The names heard so far, in the order they first came.
    public var heardNames: [String] {
        state.withLock { $0.heard }
    }

    /// A received packet.
    public func accept(_ packet: SpectrumPacket) {
        let frame: SpectrumFrame = packet.frame
        state.withLock { s in
            if !s.heard.contains(packet.name) {
                s.heard.append(packet.name)
            }
            let wanted: Bool = s.selected.isEmpty ? (s.current == nil || s.current == packet.name)
                : s.selected == packet.name
            guard wanted else { return }
            s.current = packet.name
            if let last = s.frame, last.count != frame.count {
                s.history = []
            }
            s.frame = frame
            s.serial += 1
            s.history.insert(frame.levelsDb, at: 0)
            if s.history.count > Self.rows {
                s.history.removeLast(s.history.count - Self.rows)
            }
        }
    }

    public func latestFrame(tuning: SpectrumTuning) -> (frame: SpectrumFrame, serial: Int)? {
        state.withLock { s in s.frame.map { ($0, s.serial) } }
    }

    public func waterfallRows() -> [[Float]] {
        state.withLock { s in
            guard let first = s.history.first, !first.isEmpty else { return [] }
            let floor: Double = SpectrumTrace.median(first)
            return s.history.map { row in
                row.map { Float(Swift.max(0, Swift.min(1, ($0 - floor) / 40))) }
            }
        }
    }

    /// The external programs send about three to ten lines a second.
    public var secondsPerFrame: Double {
        0.25
    }
}

/// UDP reception of `SpectrumPacket`s (N1MM „Receive spectrum data", port 13064 by default) on its own reader thread;
/// datagrams that are not spectrum packets are dropped. Bound only while the spectrum window is open and the option
/// is on.
public final class SpectrumUdpListener: Sendable {

    let receiver: UdpReceiver

    public init(bindHost: String, bindPort: Int, handler: @escaping @Sendable (SpectrumPacket) -> Void) throws {
        let address: JavaInetAddress = try JavaInetAddress.byName(bindHost)
        receiver = try UdpReceiver.unicast(address: address, port: bindPort, share: true)
        self.handler = handler
    }

    private let handler: @Sendable (SpectrumPacket) -> Void

    public var boundPort: Int {
        receiver.boundPort
    }

    public func start() {
        let handler = self.handler
        receiver.start(name: "spectrum-listener", onDatagram: { data, _ in
            if let packet = SpectrumXml.parse(data) {
                handler(packet)
            }
        }, onError: { _ in })
    }

    public func close() {
        receiver.close()
    }

    public func waitUntilStopped() async {
        await receiver.waitUntilReaderExits()
    }
}
