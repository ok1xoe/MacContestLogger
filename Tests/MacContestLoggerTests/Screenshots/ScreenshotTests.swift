import AppKit
import Foundation
import Testing

/// The user guide's screenshots (`docs/screenshots.md`): the manifest covers every image of `docs/img`, and — only
/// when `MCL_SHOTS_DIR` is set (`scripts/shots.sh`) — the rendered windows are written there as PNGs in the language
/// of `MCL_SHOTS_LANG` (`cs` or `en`), optionally only `MCL_SHOTS_ONLY` (comma-separated names).
@MainActor @Suite struct ScreenshotTests {

    nonisolated static let environment: [String: String] = ProcessInfo.processInfo.environment

    @Test func theManifestCoversEveryImageOfTheGuide() throws {
        let manifest = try ShotManifest.load()
        let names: [String] = manifest.shots.map(\.name)
        #expect(Set(names).count == names.count, "a name twice")
        let img: URL = ShotDemo.repository.appendingPathComponent("docs/img")
        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: img.path)
            .filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }
        #expect(Set(files).subtracting(names).sorted() == [], "images without a manifest entry")
        // Every image the pages reference is in the manifest.
        let docs: URL = ShotDemo.repository.appendingPathComponent("docs")
        for page in try FileManager.default.contentsOfDirectory(atPath: docs.path) where page.hasSuffix(".md") {
            let text = try String(contentsOf: docs.appendingPathComponent(page), encoding: .utf8)
            for name in Self.imageNames(text) {
                #expect(names.contains(name), "\(page) shows img/\(name).png, which the manifest does not list")
            }
        }
        for shot in manifest.shots {
            #expect(shot.width >= 100 && shot.height >= 60, "\(shot.name): size")
            #expect(!shot.languages.isEmpty && Set(shot.languages).isSubset(of: ["cs", "en"]), "\(shot.name): languages")
            #expect(!shot.rendered || ShotRenderer.windows.contains(shot.window),
                    "\(shot.name): rendered, but the renderer does not know the window \(shot.window)")
        }
    }

    /// `img/<name>.png` references of a page.
    static func imageNames(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: "img/") {
            rest = rest[range.upperBound...]
            guard let end = rest.range(of: ".png") else { break }
            let name = String(rest[..<end.lowerBound])
            // Only real names (`dx-cluster`), not a placeholder such as `<name>` in a maintainer's text.
            if !name.isEmpty, name.allSatisfy({ ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "-" }) {
                out.append(name)
            }
        }
        return out
    }

    /// Writes the rendered screenshots; skipped unless `MCL_SHOTS_DIR` is set.
    @Test(.enabled(if: ScreenshotTests.environment["MCL_SHOTS_DIR"] != nil))
    func renderTheScreenshots() async throws {
        let out = URL(fileURLWithPath: try #require(Self.environment["MCL_SHOTS_DIR"]), isDirectory: true)
        let language: String = Self.environment["MCL_SHOTS_LANG"] ?? "cs"
        try #require(["cs", "en"].contains(language), "MCL_SHOTS_LANG is cs or en")
        let only: Set<String>? = Self.environment["MCL_SHOTS_ONLY"].flatMap {
            $0.isEmpty ? nil : Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        let shots = try ShotManifest.load().shots.filter { shot in
            shot.rendered && shot.languages.contains(language) && (only?.contains(shot.name) ?? true)
        }
        try #require(!shots.isEmpty, "nothing to render")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for shot in shots {
            // A fresh demo per window, so one window's state (a selection, a zoom) never leaks into another.
            let demo: ShotDemo = try await ShotDemo.make(language: language)
            defer { demo.remove() }
            let png: Data = try await ShotRenderer(demo: demo).render(shot)
            let file: URL = out.appendingPathComponent(shot.name + ".png")
            try png.write(to: file, options: .atomic)
            print("shots: \(language) \(shot.name) → \(file.lastPathComponent) (\(png.count / 1_024) KB)")
        }
    }
}
