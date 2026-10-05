import Foundation
import Testing
@testable import MCLCore

/// `MacSpeech.synthesize` against the maintainer-only probe (rows `MS.synth`,
/// `MS.failDeleted`). **The real `say` is not run:** the command line is compared as assembled, the behaviour
/// (cache, exit code, missing output, timeout) is verified over a harmless `/bin/sh` script — the same one
/// the probe slipped to Java via `PATH`.
@Suite struct MacSpeechTests {

    static func java(_ id: String) -> [[String]] {
        ProbeRows.rows(AudioIoMeasured.rows, id)
    }

    static func nullable(_ text: String) -> String? {
        text == "<null>" ? nil : text
    }

    @Test func commandLineMatchesJava() throws {
        let rows = Self.java("MS.synth")
        #expect(rows.count == 11)
        var compared = 0
        for row in rows where row[4] != "<no run>" {
            let speech = MacSpeech(cacheDir: try JavaPath("/d/tts-cache/sub"), voice: Self.nullable(row[0]))
            let text: String = row[1]
            let args: [String] = speech.arguments(text, out: speech.cacheFile(text))
            let log: String = args.map { $0 + "\n" }.joined() + "--\n"
            #expect(log == row[4].replacingOccurrences(of: "<dir>", with: "/d"), "\(row)")
            compared += 1
        }
        #expect(compared == 7)
    }

    /// Java launches `ProcessBuilder("say", …)` — it searches `PATH`; here the same via `ProcessRunner`.
    @Test func defaultExecutableIsSayFromPath() throws {
        let speech = MacSpeech(cacheDir: try JavaPath("/d"), voice: nil)
        #expect(speech.executable == "say")
        #expect(speech.timeoutMs == 20_000)
    }

    /// A `say` stand-in as in the probe: records the arguments, depending on the text creates output / fails / creates nothing /
    /// sleeps (for the timeout).
    static func fakeSay(in dir: URL, log: URL) throws -> String {
        let script = dir.appendingPathComponent("say")
        let text = """
            #!/bin/sh
            for a in "$@"; do printf '%s\\n' "$a" >> '\(log.path)'; done
            printf -- '--\\n' >> '\(log.path)'
            out=''; prev=''
            for a in "$@"; do if [ "$prev" = '-o' ]; then out="$a"; fi; prev="$a"; done
            last=''; for a in "$@"; do last="$a"; done
            case "$last" in
              FAIL*) printf 'x' > "$out"; exit 3 ;;
              NOOUT*) exit 0 ;;
              SLEEP*) printf 'x' > "$out"; exec /bin/sleep 30 ;;
              *) printf 'RIFF' > "$out" ;;
            esac

            """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: dir.path).resolvingSymlinksInPath()
    }

    @Test func synthesizeOverFakeSayMatchesJava() async throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("say-args.log")
        let say = try Self.fakeSay(in: root, log: log)
        let cache = try JavaPath(root.path + "/tts-cache/sub")
        let rows = Self.java("MS.synth")
        let got: [[String]] = await onOwnThread("tts-test") {
            var out: [[String]] = []
            for row in rows {
                try? FileManager.default.removeItem(at: log)
                let speech = MacSpeech(cacheDir: cache, voice: Self.nullable(row[0]), executable: say,
                                       timeoutMs: 20_000)
                guard let text = Self.nullable(row[1]) else {
                    out.append(row) // Java `synthesize(null)` → null; the Swift API takes only `String`
                    continue
                }
                let path = speech.synthesize(text)
                let exists: String = path.map { String(FileManager.default.fileExists(atPath: $0.description)) } ?? "-"
                let args: String = (try? String(contentsOf: log, encoding: .utf8)) ?? "<no run>"
                out.append([row[0], row[1], path?.description ?? "<null>", exists, args])
            }
            return out
        }
        let expected: [[String]] = rows.map { $0.map { $0.replacingOccurrences(of: "<dir>", with: root.path) } }
        #expect(got.count == expected.count)
        for (g, e) in zip(got, expected) {
            #expect(g == e)
        }
        let failed = try #require(Self.java("MS.failDeleted").first)
        let failedFile = MacSpeech(cacheDir: cache, voice: "").cacheFile("FAIL now")
        #expect(failedFile.description == failed[0].replacingOccurrences(of: "<dir>", with: root.path))
        #expect(String(FileManager.default.fileExists(atPath: failedFile.description)) == failed[1])
    }

    /// Java `waitFor(20 s)` → `destroyForcibly`, delete the file, `null` (here with a shorter limit; the stand-in
    /// sleeps 30 s, so the result does not depend on load).
    @Test func timeoutKillsAndDeletesOutput() async throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let say = try Self.fakeSay(in: root, log: root.appendingPathComponent("log"))
        let speech = MacSpeech(cacheDir: try JavaPath(root.path + "/c"), voice: "", executable: say, timeoutMs: 200)
        let result: JavaPath? = await onOwnThread("tts-test") { speech.synthesize("SLEEP") }
        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: speech.cacheFile("SLEEP").description))
    }

    @Test func missingProgramGivesNil() async throws {
        let root = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let speech = MacSpeech(cacheDir: try JavaPath(root.path + "/c"), voice: "",
                               executable: root.path + "/no-such-say", timeoutMs: 20_000)
        let result: JavaPath? = await onOwnThread("tts-test") { speech.synthesize("CQ") }
        #expect(result == nil)
    }
}
