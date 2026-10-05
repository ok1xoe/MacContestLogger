import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `ResourceCheck` over fake app bundles in temporary directories.
@Suite struct ResourceCheckTests {

    private static let validLanguage = Data(#"{"_name":"English","Soubor":"File"}"#.utf8)
    private static let validMenu = Data(#"{"menu":[{"id":"file","label":"Soubor","children":[]}]}"#.utf8)

    /// A temporary directory removed at the end of the test.
    private final class TempDir {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcl-resource-check-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// Writes a resource bundle in the macOS layout (`Contents/Resources`) at `url`.
    private static func makeBundle(at url: URL, language: Data? = validLanguage, menu: Data? = validMenu) throws {
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if let language {
            try language.write(to: resources.appendingPathComponent("lang_en.json"))
        }
        if let menu {
            try menu.write(to: resources.appendingPathComponent("menu.json"))
        }
    }

    private static func makeApp(in dir: URL) throws -> URL {
        let app = dir.appendingPathComponent("MacContestLogger.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Resources", isDirectory: true), withIntermediateDirectories: true)
        return app
    }

    private static func bundleInResources(_ app: URL) -> URL {
        app.appendingPathComponent("Contents/Resources/" + CoreResources.bundleName, isDirectory: true)
    }

    @Test func completeAppPasses() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        try Self.makeBundle(at: Self.bundleInResources(app))
        #expect(ResourceCheck.verify(bundleURL: app) == [])
    }

    @Test func missingBundleIsReported() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        let problems: [String] = ResourceCheck.verify(bundleURL: app)
        #expect(problems == ["Chybí balíček zdrojů aplikace: " + Self.bundleInResources(app).path])
    }

    @Test func bundleOutsideTheAppIsReported() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        let outside = dir.url.appendingPathComponent("build/" + CoreResources.bundleName, isDirectory: true)
        try Self.makeBundle(at: outside)
        try FileManager.default.createSymbolicLink(at: Self.bundleInResources(app), withDestinationURL: outside)
        let problems: [String] = ResourceCheck.verify(bundleURL: app)
        #expect(problems == ["Balíček zdrojů leží mimo aplikaci: " + outside.resolvingSymlinksInPath().path])
    }

    @Test func bundleAtTheAppRootIsReportedAsMisplaced() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        let atRoot = app.appendingPathComponent(CoreResources.bundleName, isDirectory: true)
        try Self.makeBundle(at: atRoot)
        #expect(ResourceCheck.verify(bundleURL: app) == ["Balíček zdrojů leží mimo Contents/Resources: " + atRoot.path])
    }

    @Test func emptyEnglishLanguageIsReported() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        try Self.makeBundle(at: Self.bundleInResources(app), language: Data())
        #expect(ResourceCheck.verify(bundleURL: app) == ["Vestavěný jazyk je prázdný nebo poškozený: lang_en.json"])
    }

    @Test func missingLanguageAndMenuAreBothReported() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        try Self.makeBundle(at: Self.bundleInResources(app), language: nil, menu: Data("{}".utf8))
        #expect(ResourceCheck.verify(bundleURL: app) == [
            "Chybí vestavěný jazyk: lang_en.json",
            "Chybí nebo je poškozené vestavěné menu: menu.json",
        ])
    }

    @Test func bundleBesideACommandLineExecutablePasses() throws {
        let dir = try TempDir()
        try Self.makeBundle(at: dir.url.appendingPathComponent(CoreResources.bundleName, isDirectory: true))
        #expect(ResourceCheck.verify(bundleURL: dir.url) == [])
    }

    @Test func runningTestProcessPassesThroughTheFallback() {
        #expect(ResourceCheck.verify(bundleURL: Bundle.main.bundleURL) == [])
    }

    @Test func selfCheckReportsProblemsAndExitsWithOne() throws {
        let dir = try TempDir()
        let app = try Self.makeApp(in: dir.url)
        var lines: [String] = []
        #expect(SelfCheck.run(bundleURL: app, report: { lines.append($0) }) == 1)
        #expect(lines.count == 1)
        try Self.makeBundle(at: Self.bundleInResources(app))
        lines = []
        #expect(SelfCheck.run(bundleURL: app, report: { lines.append($0) }) == 0)
        #expect(lines.isEmpty)
    }
}
