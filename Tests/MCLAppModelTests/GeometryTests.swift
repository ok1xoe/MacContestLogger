import CoreGraphics
import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// AWT ↔ AppKit conversion.
@Suite struct AwtCoordinatesTests {

    @Test func mainDisplayMirrorsOverItsHeight() {
        let awt = CGRect(x: 80, y: 80, width: 621, height: 450)
        let appKit: CGRect = AwtCoordinates.toAppKit(awt, mainScreenHeight: 1200)
        #expect(appKit == CGRect(x: 80, y: 1200 - 80 - 450, width: 621, height: 450))
        #expect(AwtCoordinates.fromAppKit(appKit, mainScreenHeight: 1200) == awt)
    }

    @Test func conversionIsItsOwnInverse() {
        let frames: [CGRect] = [
            CGRect(x: -1920, y: 100, width: 800, height: 600),
            CGRect(x: 0, y: -1080, width: 300, height: 200),
            CGRect(x: 2560, y: 1500, width: 1, height: 1),
        ]
        for frame in frames {
            let there: CGRect = AwtCoordinates.toAppKit(frame, mainScreenHeight: 1117)
            #expect(AwtCoordinates.fromAppKit(there, mainScreenHeight: 1117) == frame)
        }
    }
}

/// `WindowGeometryStore`: placement on displays, debounce and the v1.1.1 config.
@MainActor @Suite struct WindowGeometryStoreTests {

    private static let main = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    private static func store(_ config: AppConfig = AppConfig(), dir: TempDir,
                              writer: ConfigWriter? = nil) -> (WindowGeometryStore, ConfigModel, ManualClock,
                                                               StatusModel) {
        let language = LanguageModel(translator: .source, languageDir: dir.child("language"))
        let status = StatusModel(language: language)
        let file: URL = dir.child("config.json")
        let model = ConfigModel(config: config, store: ConfigStore(file: file),
                                writer: writer ?? ConfigWriter(file: file), status: status)
        let clock = ManualClock()
        return (WindowGeometryStore(config: model, clock: clock), model, clock, status)
    }

    private static func config(_ geometry: [String: WindowGeometry]) -> AppConfig {
        var config = AppConfig()
        config.windowGeometry = geometry
        return config
    }

    @Test func nothingSavedLetsTheSystemPlace() throws {
        let dir = try TempDir()
        let (store, _, _, _) = Self.store(dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main], mainScreenHeight: 1200)
        #expect(frame == nil)
        #expect(store.initialSize(id: "log", defaultSize: CGSize(width: 900, height: 420), persistSize: true)
            == CGSize(width: 900, height: 420))
    }

    @Test func mainDisplay() throws {
        let dir = try TempDir()
        let (store, _, _, _) = Self.store(Self.config(["log": WindowGeometry(x: 80, y: 80, width: 621, height: 450)]),
                                          dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main], mainScreenHeight: 1200)
        #expect(frame == CGRect(x: 80, y: 670, width: 621, height: 450))
    }

    @Test func positionOnlyKeepsTheDefaultSize() throws {
        let dir = try TempDir()
        let (store, _, _, _) = Self.store(Self.config(["main": WindowGeometry(x: 80, y: 80, width: 0, height: 0)]),
                                          dir: dir)
        let frame: CGRect? = store.initialFrame(id: "main", defaultSize: CGSize(width: 820, height: 500),
                                                persistSize: false, screens: [Self.main], mainScreenHeight: 1200)
        #expect(frame == CGRect(x: 80, y: 620, width: 820, height: 500))
    }

    @Test func displayOnTheLeftHasNegativeX() throws {
        let dir = try TempDir()
        let left = CGRect(x: -1680, y: 0, width: 1680, height: 1050)
        let (store, _, _, _) = Self.store(
            Self.config(["log": WindowGeometry(x: -1600, y: 200, width: 600, height: 400)]), dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main, left], mainScreenHeight: 1200)
        // The left display is shorter and bottom-aligned: in AWT it spans y 150…1200.
        #expect(frame == CGRect(x: -1600, y: 600, width: 600, height: 400))
    }

    @Test func displayAboveTheMainHasNegativeAwtY() throws {
        let dir = try TempDir()
        // AppKit: a display above the main one starts at y = 1200; in AWT it lies at negative y.
        let above = CGRect(x: 0, y: 1200, width: 1920, height: 1080)
        let (store, _, _, _) = Self.store(
            Self.config(["log": WindowGeometry(x: 100, y: -900, width: 600, height: 400)]), dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main, above], mainScreenHeight: 1200)
        #expect(frame == CGRect(x: 100, y: 1700, width: 600, height: 400))
        #expect(frame.map { above.contains($0) } == true)
    }

    @Test func disconnectedDisplayFallsBackToTheSystem() throws {
        let dir = try TempDir()
        let (store, _, _, _) = Self.store(
            Self.config(["log": WindowGeometry(x: -1600, y: 100, width: 600, height: 400)]), dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main], mainScreenHeight: 1200)
        #expect(frame == nil)
    }

    @Test func partlyOffscreenIsClampedBack() throws {
        let dir = try TempDir()
        let (store, _, _, _) = Self.store(
            Self.config(["log": WindowGeometry(x: 1700, y: 1000, width: 600, height: 400)]), dir: dir)
        let frame: CGRect? = store.initialFrame(id: "log", defaultSize: CGSize(width: 900, height: 420),
                                                persistSize: true, screens: [Self.main], mainScreenHeight: 1200)
        // AWT clamp to (1320, 800) → AppKit y = 1200 - 800 - 400 = 0.
        #expect(frame == CGRect(x: 1320, y: 0, width: 600, height: 400))
    }

    @Test func changesAreSavedAfter500msOfQuiet() async throws {
        let dir = try TempDir()
        let (store, model, clock, _) = Self.store(dir: dir)
        store.windowChanged(id: "log", frame: CGRect(x: 10, y: 600, width: 900, height: 420), persistSize: true,
                            mainScreenHeight: 1200)
        clock.advance(by: 300)
        store.windowChanged(id: "log", frame: CGRect(x: 20, y: 600, width: 900, height: 420), persistSize: true,
                            mainScreenHeight: 1200)
        clock.advance(by: 499)
        #expect(model.config.windowGeometry["log"] == nil)
        clock.advance(by: 1)
        #expect(model.config.windowGeometry["log"] == WindowGeometry(x: 20, y: 180, width: 900, height: 420))
        await model.flush()
        let saved: AppConfig = ConfigStore(file: dir.child("config.json")).load()
        #expect(saved.windowGeometry["log"] == WindowGeometry(x: 20, y: 180, width: 900, height: 420))
    }

    @Test func positionOnlyWindowsSaveZeroSize() async throws {
        let dir = try TempDir()
        let (store, model, clock, _) = Self.store(dir: dir)
        store.windowChanged(id: "main", frame: CGRect(x: 80.9, y: 620, width: 820, height: 500), persistSize: false,
                            mainScreenHeight: 1200)
        clock.advance(by: 500)
        #expect(model.config.windowGeometry["main"] == WindowGeometry(x: 80, y: 80, width: 0, height: 0))
    }

    @Test func failedSaveReportsInTheStatusLine() async throws {
        struct Boom: Error, CustomStringConvertible { var description: String { "disk full" } }
        let dir = try TempDir()
        let writer = ConfigWriter { _ in throw Boom() }
        let (store, model, clock, status) = Self.store(dir: dir, writer: writer)
        store.windowChanged(id: "log", frame: CGRect(x: 0, y: 0, width: 100, height: 100), persistSize: true,
                            mainScreenHeight: 1200)
        clock.advance(by: 500)
        await model.flush()
        await Task.yield()
        // The status hop is posted to the main queue; give it a turn.
        await MainQueueTurn.wait()
        #expect(status.message == "Uložení geometrie okna selhalo (disk full)")
    }

    @Test func roundTripWithTheV111Config() async throws {
        let dir = try TempDir()
        let config: AppConfig = ConfigStore(file: Fixtures.configV111).load()
        let (store, model, clock, _) = Self.store(config, dir: dir)
        for (id, persist) in [("log", true), ("main", false), ("score", true), ("startup", true)] {
            let original: WindowGeometry = try #require(config.windowGeometry[id])
            let frame: CGRect = try #require(store.initialFrame(
                id: id, defaultSize: CGSize(width: 820, height: 500), persistSize: persist,
                screens: [Self.main], mainScreenHeight: 1200))
            store.windowChanged(id: id, frame: frame, persistSize: persist, mainScreenHeight: 1200)
            clock.advance(by: 500)
            #expect(model.config.windowGeometry[id] == original, "\(id)")
        }
    }

    @Test func flushWritesPendingChangesAtOnce() throws {
        let dir = try TempDir()
        let (store, model, clock, _) = Self.store(dir: dir)
        store.windowChanged(id: "log", frame: CGRect(x: 5, y: 700, width: 900, height: 420), persistSize: true,
                            mainScreenHeight: 1200)
        store.flush()
        #expect(model.config.windowGeometry["log"] == WindowGeometry(x: 5, y: 80, width: 900, height: 420))
        clock.advance(by: 500)
        #expect(clock.pendingCount == 0)
    }
}

/// Waits for one turn of the main dispatch queue (status texts hopped there by `MainHop`).
enum MainQueueTurn {
    @MainActor static func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
