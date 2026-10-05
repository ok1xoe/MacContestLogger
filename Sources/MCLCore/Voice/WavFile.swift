/// A WAV file as read by Java `AudioSystem.getAudioInputStream(File)` (readers `WaveFileReader`,
/// `WaveFloatFileReader`, `WaveExtensibleFileReader`), and the stream that `SoundCard.play` plays from it.
/// Rules measured by the maintainer-only probe (`PLAY.*`):
/// - `RIFF` + `WAVE`, chunks (an odd length is padded with a byte) up to the length from the RIFF header; first `fmt `,
///   then `data` — `data` before `fmt ` or a missing chunk = unsupported format;
/// - encoding: tag 1 PCM (8-bit unsigned, otherwise signed), 3 float (32/64 bit), 6 A-law, 7 μ-law,
///   `0xFFFE` with a PCM/float subformat; other tags and 0 channels = unsupported format; `RIFX` (big-endian) too;
/// - frame size `((bits + 7) / 8) × channels` (not `blockAlign` from the header); frame count = `data` length /
///   frame; reads only to the end of the file and only whole frames;
/// - a format other than signed PCM is converted to 16-bit LE like the Java converters: float and unsigned 8-bit
///   via `float` with an asymmetric scale (`x > 0 ? x/127 : x/128`, `f > 0 ? f×32767 : f×32768`,
///   `(short)` via `(int)` with saturation), A-law/μ-law by the G.711 table.
///
/// **Divergence:** Java also reads an AU, AIFF (and MIDI) file with the extension `.wav`; here only RIFF/WAVE.
public struct WavFile: Equatable {

    enum Encoding: String {
        case pcmSigned = "PCM_SIGNED"
        case pcmUnsigned = "PCM_UNSIGNED"
        case pcmFloat = "PCM_FLOAT"
        case alaw = "ALAW"
        case ulaw = "ULAW"
    }

    let encoding: Encoding
    /// Java `float` from the header (32-bit unsigned).
    let sampleRate: Float
    let bits: Int
    let channels: Int
    let frameSize: Int
    /// Frames according to the header (`data` / frame) — Java `getFrameLength()`.
    let frameLength: Int64
    /// Readable data (whole frames to the end of the file, at most `frameLength`).
    let data: [UInt8]

    /// Format of the stream being played: signed PCM, little-endian.
    public struct PcmFormat: Equatable, Sendable {
        public let sampleRate: Float
        public let bits: Int
        public let channels: Int
        public let frameSize: Int

        public init(sampleRate: Float, bits: Int, channels: Int, frameSize: Int) {
            self.sampleRate = sampleRate
            self.bits = bits
            self.channels = channels
            self.frameSize = frameSize
        }

        /// Java `AudioCapture.FORMAT`: 12 kHz, 16 bit, mono, signed, little-endian — the contest recording.
        public static let capture = PcmFormat(sampleRate: Float(AudioCapture.sampleRate), bits: 16, channels: 1,
                                              frameSize: 2)
    }

    static func parse(_ bytes: [UInt8]) -> WavFile? {
        guard bytes.count >= 12, ascii(bytes, 0) == "RIFF", ascii(bytes, 8) == "WAVE" else {
            return nil
        }
        let riffEnd: Int = min(bytes.count, 8 &+ Int(u32(bytes, 4)))
        var offset = 12
        var fmt: ArraySlice<UInt8>?
        var data: (start: Int, length: Int64)?
        while offset + 8 <= riffEnd {
            let id = ascii(bytes, offset)
            let length = Int64(u32(bytes, offset + 4))
            let start = offset + 8
            if id == "fmt " {
                let end = Int(min(Int64(bytes.count), Int64(start) + length))
                fmt = bytes[start..<end]
            }
            if id == "data" {
                data = (start, length)
                break
            }
            let next = Int64(start) + length + (length & 1)
            guard next <= Int64(Int.max / 2) else { break }
            offset = Int(next)
        }
        guard let fmt, let data, fmt.count >= 16 else {
            return nil
        }
        let base = fmt.startIndex
        var tag = Int(u16(bytes, base))
        let channels = Int(u16(bytes, base + 2))
        let rate = u32(bytes, base + 4)
        let bits = Int(u16(bytes, base + 14))
        if tag == 0xFFFE {
            guard fmt.count >= 26 else { return nil }
            tag = Int(u16(bytes, base + 24)) // the first two bytes of the subformat GUID
        }
        let encoding: Encoding
        switch tag {
        case 1: encoding = bits == 8 ? .pcmUnsigned : .pcmSigned
        case 3:
            guard bits == 32 || bits == 64 else { return nil }
            encoding = .pcmFloat
        case 6: encoding = .alaw
        case 7: encoding = .ulaw
        default: return nil
        }
        guard channels > 0, bits > 0 else {
            return nil
        }
        let frameSize = (bits + 7) / 8 * channels
        let frameLength = data.length / Int64(frameSize)
        let available = Int64(bytes.count - min(bytes.count, data.start))
        let readable = min(available / Int64(frameSize), frameLength) * Int64(frameSize)
        let payload = Array(bytes[data.start..<(data.start + Int(readable))])
        return WavFile(encoding: encoding, sampleRate: Float(rate), bits: bits, channels: channels,
                       frameSize: frameSize, frameLength: frameLength, data: payload)
    }

    /// Stream that `SoundCard.play` sends to the output: signed PCM unchanged, otherwise converted to 16-bit LE.
    func playable() -> (format: PcmFormat, bytes: [UInt8]) {
        if encoding == .pcmSigned {
            return (PcmFormat(sampleRate: sampleRate, bits: bits, channels: channels, frameSize: frameSize), data)
        }
        var out: [UInt8] = []
        out.reserveCapacity(data.count / max(1, frameSize / channels) * 2)
        func put(_ value: Int16) {
            let bits = UInt16(bitPattern: value)
            out.append(UInt8(truncatingIfNeeded: bits))
            out.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        switch encoding {
        case .pcmUnsigned:
            for byte in data {
                let x = Int8(truncatingIfNeeded: Int(byte) - 128)
                let f: Float = x > 0 ? Float(x) / 127 : Float(x) / 128
                put(Self.toShort(f))
            }
        case .pcmFloat:
            let width = bits / 8
            var i = 0
            while i + width <= data.count {
                let f: Float = width == 4
                    ? Float(bitPattern: Self.u32(data, i))
                    : Float(Double(bitPattern: UInt64(Self.u32(data, i)) | UInt64(Self.u32(data, i + 4)) << 32))
                put(Self.toShort(f))
                i += width
            }
        case .alaw:
            for byte in data { put(Self.alaw(byte)) }
        case .ulaw:
            for byte in data { put(Self.ulaw(byte)) }
        case .pcmSigned:
            break
        }
        return (PcmFormat(sampleRate: sampleRate, bits: 16, channels: channels, frameSize: 2 * channels), out)
    }

    /// Java `(short) (f > 0 ? f * 32767 : f * 32768)` (`float` → `int` with saturation, NaN → 0, then truncation).
    static func toShort(_ f: Float) -> Int16 {
        let scaled: Float = f > 0 ? f * 32767 : f * 32768
        let i: Int32
        if scaled.isNaN {
            i = 0
        } else if scaled >= 2_147_483_648 {
            i = .max
        } else if scaled <= -2_147_483_648 {
            i = .min
        } else {
            i = Int32(scaled)
        }
        return Int16(truncatingIfNeeded: i)
    }

    /// G.711 μ-law → 16-bit (Java `UlawCodec`, table `ulaw2linear`).
    static func ulaw(_ byte: UInt8) -> Int16 {
        let u = ~byte
        var t = (Int32(u & 0x0F) << 3) + 0x84
        t <<= Int32((u & 0x70) >> 4)
        return Int16(truncatingIfNeeded: (u & 0x80) != 0 ? 0x84 - t : t - 0x84)
    }

    /// G.711 A-law → 16-bit (Java `AlawCodec`, `alaw2linear`).
    static func alaw(_ byte: UInt8) -> Int16 {
        let a = byte ^ 0x55
        var t = Int32(a & 0x0F) << 4
        let segment = Int32((a & 0x70) >> 4)
        switch segment {
        case 0: t += 8
        case 1: t += 0x108
        default:
            t += 0x108
            t <<= segment - 1
        }
        return Int16(truncatingIfNeeded: (a & 0x80) != 0 ? t : -t)
    }

    private static func ascii(_ bytes: [UInt8], _ at: Int) -> String {
        String(decoding: bytes[at..<(at + 4)], as: UTF8.self)
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
