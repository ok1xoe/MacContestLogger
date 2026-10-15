// Adapted from RYRY's AuxDecoderHub multi-channel part (https://github.com/ok1xoe/RYRY). Copyright 2026 OK1XOE,
// GNU LGPL v3 (third-party/MMTTY/NOTICE.md).
import Foundation

/// The multi-channel receiver of one built-in RTTY receiver (MMTTY / RYRY "channels", N1MM's RTTY browser): its own
/// decoders on the signals found in the receiver's spectrum, at most `maxChannels` (≤ 8), each following its signal
/// with AFC and dropped after `timeout` seconds without one. Receive only.
///
/// The decoders run on the bank's own serial queue, outside the receiver's audio queue; when the queue lags behind
/// by more than 20 s of audio, blocks are dropped.
public final class BuiltinChannelBank: @unchecked Sendable {

    public static let maxChannelLimit = 8

    public struct Config: Equatable, Sendable {
        public var enabled = false
        public var maxChannels = 4
        /// A channel goes after this many seconds without a signal.
        public var timeout: Double = 15
        public var fromHz = 200.0
        public var toHz = 3000.0

        public init() {}

        var channelLimit: Int {
            min(BuiltinChannelBank.maxChannelLimit, max(1, maxChannels))
        }

        var clampedTimeout: Double {
            timeout.isFinite ? min(600, max(1, timeout)) : 15
        }
    }

    /// A channel as the panel shows it.
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: Int
        public let markHz: Double
        /// The channel's decoded text (the last `textLimit` characters, line breaks as spaces).
        public let text: String
    }

    static let textLimit = 400

    private struct Channel {
        let id: Int
        let decoder: BuiltinRttyChannel
        var mark: Double
        var lastSeen: Double
    }

    private let source: BuiltinRttyChannel
    private let queue = DispatchQueue(label: "mcl.builtin-channels", qos: .userInitiated)
    private let maxBacklog: Int
    private let lock = NSLock()
    // Under the lock.
    private var config = Config()
    private var backlog = 0
    private var droppedSamples = 0
    private var rows: [Row] = []
    // Queue only.
    private var channels: [Channel] = []
    private var detector = BuiltinSignalDetector()
    private var samples = 0
    private var nextId = 1
    private var applied = Config()

    /// `source` = the receiver whose spectrum and tuning (shift, speed, reverse) the channels follow.
    public init(source: BuiltinRttyChannel, maxBacklog: Int? = nil) {
        self.source = source
        self.maxBacklog = maxBacklog ?? Int(BuiltinRttyChannel.sampleRate * 20)
    }

    public var configuration: Config {
        lock.withLock { config }
    }

    public func configure(_ config: Config) {
        lock.withLock { self.config = config }
        if !config.enabled {
            queue.async { [self] in
                channels.removeAll()
                detector.reset()
                publish()
            }
        }
    }

    /// The channels now (the panel's refresh).
    public var snapshot: [Row] {
        lock.withLock { rows }
    }

    /// Samples dropped because the queue lagged.
    public var dropped: Int {
        lock.withLock { droppedSamples }
    }

    /// A block of the receiver's audio (its audio queue); ignored while off or transmitting.
    public func feed(_ block: [Double]) {
        let accepted: Bool = lock.withLock {
            guard config.enabled else { return false }
            if backlog + block.count > maxBacklog {
                droppedSamples += block.count
                return false
            }
            backlog += block.count
            return true
        }
        guard accepted, !source.isTransmitting else {
            return
        }
        let spectrum: BuiltinRttyChannel.Spectrum? = source.snapshot.spectrum
        queue.async { [self] in
            process(block, spectrum: spectrum)
            lock.withLock { backlog -= block.count }
        }
    }

    /// Waits until the blocks fed so far are processed (tests).
    public func flush() {
        queue.sync {}
    }

    private func process(_ block: [Double], spectrum: BuiltinRttyChannel.Spectrum?) {
        let config: Config = lock.withLock { self.config }
        guard config.enabled else { return }
        if config.channelLimit < channels.count {
            channels.removeLast(channels.count - config.channelLimit)
        }
        samples += block.count
        let tuning: BuiltinRttyChannel.Tuning = source.tuning
        if let spectrum {
            detector.update(spectrum)
            updateChannels(tuning, config)
        }
        for index in channels.indices {
            let decoder: BuiltinRttyChannel = channels[index].decoder
            let current: BuiltinRttyChannel.Tuning = decoder.tuning
            if current.shiftHz != tuning.shiftHz || current.baud != tuning.baud || current.reverse != tuning.reverse {
                decoder.update { channel in
                    channel.shiftHz = tuning.shiftHz
                    channel.baud = tuning.baud
                    channel.reverse = tuning.reverse
                }
            }
            decoder.receive(block)
            channels[index].mark = decoder.tuning.markHz
        }
        publish()
    }

    private func updateChannels(_ tuning: BuiltinRttyChannel.Tuning, _ config: Config) {
        let now: Double = Double(samples) / BuiltinRttyChannel.sampleRate
        let near: Double = tuning.shiftHz * 0.4
        let marks: [Double] = detector.detect(shift: tuning.shiftHz, fromHz: config.fromHz, toHz: config.toHz,
                                              maxCount: Self.maxChannelLimit)
        for mark in marks {
            if let index = channels.firstIndex(where: { abs($0.mark - mark) < near }) {
                channels[index].lastSeen = now
            } else if channels.count < config.channelLimit, mark >= 100, mark + tuning.shiftHz <= 3000,
                      !channels.contains(where: { abs($0.mark - mark) < tuning.shiftHz }) {
                let decoder = BuiltinRttyChannel()
                let rounded: Double = (mark * 10).rounded() / 10
                decoder.update { channel in
                    channel.shiftHz = tuning.shiftHz
                    channel.baud = tuning.baud
                    channel.reverse = tuning.reverse
                    channel.afc = true
                    channel.markHz = rounded
                }
                channels.append(Channel(id: nextId, decoder: decoder, mark: rounded, lastSeen: now))
                nextId += 1
            }
        }
        // Gone: no signal for longer than the timeout; two channels AFC pulled onto one signal → the older stays.
        var kept: [Channel] = []
        for channel in channels {
            if now - channel.lastSeen > config.clampedTimeout || kept.contains(where: { abs($0.mark - channel.mark) < near }) {
                continue
            }
            kept.append(channel)
        }
        channels = kept
    }

    private func publish() {
        let list: [Row] = channels.map { channel in
            let length: Int32 = channel.decoder.rxLength
            let start: Int32 = max(0, length - Int32(Self.textLimit))
            let text: String = channel.decoder.rxText(start: start, length: length - start)
                .replacingOccurrences(of: "\n", with: " ")
            return Row(id: channel.id, markHz: channel.mark.rounded(), text: text)
        }
        lock.withLock { rows = list }
    }
}
