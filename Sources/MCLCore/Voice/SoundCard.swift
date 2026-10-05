import Darwin
import Foundation

/// Sound card (Java `voice/SoundCard`): wav playback to a chosen output device (the one leading to the
/// transmitter's microphone/data input), recording messages from a chosen input and listing devices for Settings.
///
/// A device is selected by CoreAudio name; `nil`, empty, `Default Audio Device` (a Java pseudo-mixer, may be in
/// `config.json`) and a name not found = system default. Recordings are 16-bit mono PCM
/// 22 050 Hz.
///
/// Threads: `play` blocks the caller (the voice keyer queue) until playback finishes or is cancelled; recording writes on its
/// own serial queue `voice-recorder`. Call none of this from Swift's shared pool.
public enum SoundCard {

    /// Java `RECORD_FORMAT`: 22.05 kHz, 16 bit, mono, signed, little-endian.
    static let recordSampleRate: Int32 = 22_050

    /// Output device names: `Default Audio Device` first, then CoreAudio devices with output
    /// (without duplicates — like the Java mixer listing). Never throws; without an audio subsystem only the pseudo-device.
    public static func outputDevices() -> [String] {
        devices(CoreAudioDevices.names(input: false))
    }

    /// Input device names (analogous to `outputDevices`).
    public static func inputDevices() -> [String] {
        devices(CoreAudioDevices.names(input: true))
    }

    static func devices(_ names: [String]) -> [String] {
        var out: [String] = [CoreAudioDevices.defaultDeviceName]
        for name in names where !out.contains(name) {
            out.append(name)
        }
        return out
    }

    /// Player for `VoiceKeyer`; the device is read at each playback (a change in Settings applies immediately).
    public static func player(deviceName: @escaping @Sendable () -> String?) -> VoiceKeyer.AudioOut {
        player(deviceName: deviceName) { format, device in
            try EngineOutput(format: format, deviceName: device)
        }
    }

    /// `player` over any output (tests substitute a replacement — no device).
    static func player(deviceName: @escaping @Sendable () -> String?,
                       output: @escaping @Sendable (WavFile.PcmFormat, String?) throws -> any SoundOutput)
        -> VoiceKeyer.AudioOut {
        { file, cancelled in
            try play(file, deviceName: deviceName(), cancelled: cancelled, output: output)
        }
    }

    /// Plays a wav (blocks until the end or `cancelled() == true`; cancellation is checked before each block
    /// of 4 096 bytes as in Java).
    public static func play(_ file: JavaPath, deviceName: String?, cancelled: () -> Bool) throws {
        try play(file, deviceName: deviceName, cancelled: cancelled) { format, device in
            try EngineOutput(format: format, deviceName: device)
        }
    }

    /// Core of `play` over any output (tests substitute a replacement — no sound to a device).
    ///
    /// Order as Java `play`: read and parse the file (a file error = Java `FileNotFoundException`,
    /// a non-wav = `IOException("Nepodporovaný formát wav: <jméno>")`), convert to 16-bit PCM, then in blocks of
    /// `4096 − 4096 % frame` bytes: cancelled → `stopAndFlush` and end, otherwise write; finally `drain`; the output is
    /// always closed. **Divergence:** the output is opened only before the first written block (Java opens it right after
    /// parsing) — a message cancelled before the start or a wav without data does not open the device at all, and so does not report
    /// its unavailability.
    static func play(_ file: JavaPath, deviceName: String?, cancelled: () -> Bool,
                     output: SoundOutputFactory) throws {
        let bytes = try readFile(file.description)
        guard let wav = WavFile.parse(bytes) else {
            throw AudioIOError("Nepodporovaný formát wav: " + fileName(file))
        }
        let (format, stream) = wav.playable()
        let step = 4096 - 4096 % max(1, format.frameSize)
        var line: (any SoundOutput)?
        defer { line?.close() }
        var offset = 0
        while offset < stream.count {
            let count = min(step, stream.count - offset)
            if cancelled() {
                line?.stopAndFlush()
                return
            }
            let open = try line ?? output(format, deviceName)
            line = open
            try open.write(stream[offset..<(offset + count - count % max(1, format.frameSize))])
            offset += count
        }
        line?.drain()
    }

    // MARK: - PCM playback (recording segment)

    /// Plays raw signed little-endian PCM (the QSO recording segment, `AppState.playQsoRecording`, `AS:2466-2474`):
    /// Kotlin opens `AudioSystem.getSourceDataLine(AudioCapture.FORMAT)` — the **system default** output, so
    /// `deviceName` is `nil` there — writes the bytes, drains and closes. Blocks until the end or
    /// `cancelled() == true`; call it only from the playback queue, never from Swift's shared pool.
    public static func playPcm(_ bytes: [UInt8], format: WavFile.PcmFormat, deviceName: String?,
                               cancelled: () -> Bool) throws(AudioIOError) {
        try playPcm(bytes, format: format, deviceName: deviceName, cancelled: cancelled) { format, device in
            try EngineOutput(format: format, deviceName: device)
        }
    }

    /// Core of `playPcm` over any output (tests substitute a fake — no sound to a device).
    ///
    /// Like Kotlin the output is opened before anything is written (an unavailable device is reported even for an
    /// empty segment), only whole frames are played (`size - size % frame`, Kotlin `% 2` for 16-bit mono), and the
    /// output is always closed. Kotlin writes the buffer in one call and cannot be stopped; here it goes in blocks of
    /// `4096 − 4096 % frame` bytes with `cancelled` checked before each (cancelled → `stopAndFlush`, no `drain`), and
    /// a cancellation before the start opens nothing (technique — quitting the application).
    static func playPcm(_ bytes: [UInt8], format: WavFile.PcmFormat, deviceName: String?, cancelled: () -> Bool,
                        output: SoundOutputFactory) throws(AudioIOError) {
        if cancelled() {
            return
        }
        let frame = max(1, format.frameSize)
        let end = bytes.count - bytes.count % frame
        let step = 4096 - 4096 % frame
        let line: any SoundOutput
        do {
            line = try output(format, deviceName)
        } catch {
            throw audioError(error)
        }
        defer { line.close() }
        var offset = 0
        while offset < end {
            if cancelled() {
                line.stopAndFlush()
                return
            }
            let count = min(step, end - offset)
            do {
                try line.write(bytes[offset..<(offset + count)])
            } catch {
                throw audioError(error)
            }
            offset += count
        }
        line.drain()
    }

    /// An output error as `AudioIOError` (the outputs throw it already; anything else keeps its description).
    static func audioError(_ error: any Error) -> AudioIOError {
        if let audio = error as? AudioIOError {
            return audio
        }
        return AudioIOError(String(describing: error))
    }

    /// Java `Path.getFileName()` (the last name of a path).
    static func fileName(_ file: JavaPath) -> String {
        let text = file.description
        guard let slash = text.lastIndex(of: "/") else {
            return text
        }
        return String(text[text.index(after: slash)...])
    }

    /// The whole file (Java `FileInputStream`): an open error and a directory = `FileNotFoundException` `path (reason)`.
    static func readFile(_ path: String) throws -> [UInt8] {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            throw AudioIOError.fileNotFound(path, errno)
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw AudioIOError.posix(errno)
        }
        if (info.st_mode & S_IFMT) == S_IFDIR {
            throw AudioIOError.fileNotFound(path, EISDIR)
        }
        var out: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n: Int = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                throw AudioIOError.posix(errno)
            }
            if n == 0 {
                return out
            }
            out.append(contentsOf: buffer[0..<n])
        }
    }

    // MARK: - Recording

    /// A message recording in progress. It writes to a temporary file `<target>.recording` and only after successful
    /// completion overwrites the original recording — a failed attempt does not destroy it.
    public final class Recording: @unchecked Sendable {

        public let target: JavaPath
        private let temp: String
        private let input: AudioInputEngine
        private let queue: DispatchQueue
        /// Writer state — only on `queue`.
        private let writer: WavRecordingFile

        fileprivate init(target: JavaPath, temp: String, input: AudioInputEngine, queue: DispatchQueue,
                         writer: WavRecordingFile) {
            self.target = target
            self.temp = temp
            self.input = input
            self.queue = queue
            self.writer = writer
        }

        /// Ends the recording and saves the file (move over the original). Write error: `Nahrávání selhalo: …`,
        /// the temporary file is deleted.
        public func stop() throws {
            input.stop()
            let failure: AudioIOError? = queue.sync { writer.finish() }
            if let failure {
                unlink(temp)
                throw AudioIOError("Nahrávání selhalo: " + failure.message)
            }
            guard rename(temp, target.description) == 0 else {
                throw AudioIOError(temp + " -> " + target.description + ": " + String(cString: strerror(errno)),
                                   javaClass: "java.nio.file.FileSystemException")
            }
        }

        /// Discards the recording (the original file stays).
        public func cancel() {
            input.stop()
            queue.sync { _ = writer.finish() }
            unlink(temp)
        }
    }

    /// Starts recording from the chosen input into `target` (the directory is created). Input error:
    /// `Záznamové zařízení není dostupné: …`. Blocks (CoreAudio start) — call outside Swift's shared pool.
    public static func record(target: JavaPath, deviceName: String?) throws -> Recording {
        let absolute = URL(fileURLWithPath: target.description).path
        try ContestRecorder.createDirectories((absolute as NSString).deletingLastPathComponent)
        let temp = target.description + ".recording"
        let queue = DispatchQueue(label: "voice-recorder")
        let writer = WavRecordingFile(path: temp, sampleRate: recordSampleRate)
        let input = AudioInputEngine(sampleRate: Double(recordSampleRate), deviceName: deviceName, queue: queue) { pcm in
            writer.append(pcm)
        }
        try queue.sync { try writer.open() }
        do {
            try input.start()
        } catch {
            queue.sync { _ = writer.finish() }
            unlink(temp)
            throw AudioIOError("Záznamové zařízení není dostupné: " + error.message)
        }
        return Recording(target: target, temp: temp, input: input, queue: queue, writer: writer)
    }
}

/// Writing a recording to WAV of unknown length (Java `AudioSystem.write(stream, WAVE, File)`): header
/// with zero length, data, header rewritten at the end — the same bytes as Java `WaveFileWriter` (probe
/// `REC.wav`). Called only from the serial recording queue; the first write error is remembered and further data
/// is discarded (the Java writer thread ends with an exception).
final class WavRecordingFile: @unchecked Sendable {

    private let path: String
    private let sampleRate: Int32
    private var fd: Int32 = -1
    private var dataBytes: Int64 = 0
    private var failure: AudioIOError?

    init(path: String, sampleRate: Int32) {
        self.path = path
        self.sampleRate = sampleRate
    }

    func open() throws(AudioIOError) {
        let opened = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
        guard opened >= 0 else {
            throw AudioIOError.fileNotFound(path, errno)
        }
        fd = opened
        do {
            try ContestRecorder.writeAll(opened, ContestRecorder.wavHeader(sampleRate: sampleRate, data: 0))
        } catch {
            failure = error
        }
    }

    func append(_ pcm: [UInt8]) {
        guard fd >= 0, failure == nil else {
            return
        }
        do {
            try ContestRecorder.writeAll(fd, pcm)
            dataBytes &+= Int64(pcm.count)
        } catch {
            failure = error
        }
    }

    /// Appends the header and closes; returns the first write error (or `nil`). A repeated call does nothing.
    func finish() -> AudioIOError? {
        guard fd >= 0 else {
            return failure
        }
        if failure == nil {
            if lseek(fd, 0, SEEK_SET) < 0 {
                failure = AudioIOError.posix(errno)
            } else {
                do {
                    try ContestRecorder.writeAll(fd, ContestRecorder.wavHeader(sampleRate: sampleRate, data: dataBytes))
                } catch {
                    failure = error
                }
            }
        }
        Darwin.close(fd)
        fd = -1
        return failure
    }
}
