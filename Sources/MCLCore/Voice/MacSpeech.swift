import CryptoKit
import Foundation

/// Speech synthesis via macOS `say` (Java `voice/MacSpeech`): the text is spoken to a wav and stored in a cache
/// by voice and text, so a repeated message is generated only once.
///
/// The cache file name is the same as in Java — `SHA-256(voice.trim() + "|" + text)` in UTF-8, the first
/// **12 bytes** as lower-case hex + `.wav` — so a `.tts-cache` created by the Java version stays valid.
/// `synthesize` runs `say` with the same arguments as Java (measured by the probe
/// a maintainer-only probe over a `say` replacement): `[-v voice] -o <cache> --file-format=WAVE
/// --data-format=LEI16@22050 <text>`; empty text → `nil` without running, an existing file in the cache → without
/// running; at most 20 s, then (or on a non-zero exit code) `SIGKILL`, delete the file and `nil`.
///
/// **Blocks** up to 20 s — call from your own thread/queue (like the Java call from `Dispatchers.IO`), never
/// from Swift's shared pool. `say` is looked up in `PATH` as in Java (`ProcessRunner` = `ProcessBuilder`).
public struct MacSpeech: Sendable {

    public let cacheDir: JavaPath
    /// macOS voice (e.g. Daniel, Samantha, Zuzana); empty = system default.
    public let voice: String
    /// Synthesis program (`say` from `PATH`; tests substitute a harmless replacement, the real `say` is not run in tests).
    let executable: String
    /// Java `waitFor(20, SECONDS)`.
    let timeoutMs: Int

    public init(cacheDir: JavaPath, voice: String?) {
        self.init(cacheDir: cacheDir, voice: voice, executable: "say", timeoutMs: 20_000)
    }

    init(cacheDir: JavaPath, voice: String?, executable: String, timeoutMs: Int) {
        self.cacheDir = cacheDir
        self.voice = voice.map(JavaText.trim) ?? ""
        self.executable = executable
        self.timeoutMs = timeoutMs
    }

    /// `say` arguments (without the program name) for the text and output file — Java `ProcessBuilder`.
    func arguments(_ text: String, out: JavaPath) -> [String] {
        let tail: [String] = ["-o", out.description, "--file-format=WAVE", "--data-format=LEI16@22050", text]
        return voice.isEmpty ? tail : ["-v", voice] + tail
    }

    /// Speaks the text to a wav in the cache (or returns the existing one); `nil` when it is not possible (empty text, `say` failed,
    /// timed out, the cache directory cannot be created). Implementation of `VoiceMessagePlanner.Speech`.
    public func synthesize(_ text: String) -> JavaPath? {
        if JavaText.isBlank(text) {
            return nil
        }
        let out = cacheFile(text)
        if FileManager.default.fileExists(atPath: out.description) {
            return out
        }
        do {
            try ContestRecorder.createDirectories(cacheDir.description)
        } catch {
            return nil
        }
        let runner = ProcessRunner(executable: executable, arguments: arguments(text, out: out), onLine: { _ in })
        do {
            try runner.start()
        } catch {
            return nil
        }
        if !runner.waitForExit(timeoutMs: timeoutMs) || runner.exitCode != 0 {
            if runner.isAlive {
                kill(runner.pid, SIGKILL) // Java destroyForcibly() (not for an exited process — the pid might belong to another)
            }
            try? FileManager.default.removeItem(atPath: out.description)
            return nil
        }
        return FileManager.default.fileExists(atPath: out.description) ? out : nil
    }

    /// File in the cache for a text (hash of voice and text).
    func cacheFile(_ text: String) -> JavaPath {
        let digest = SHA256.hash(data: Data((voice + "|" + text).utf8))
        let hex: String = digest.prefix(12).map { byte in
            let digits = String(byte, radix: 16)
            return byte < 16 ? "0" + digits : digits
        }.joined()
        return cacheDir.resolve(fileName: hex + ".wav")
    }
}
