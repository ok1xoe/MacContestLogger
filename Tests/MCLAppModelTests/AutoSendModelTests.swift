import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM AutoSend in the entry window: in Run and CW the call goes to the keyer (a recorder, nothing is keyed) as it
/// is typed past the threshold; the ESM Enter then sends the exchange without the call. Off by default.
@MainActor @Suite struct AutoSendModelTests {

    private static func make(threshold: Int, run: Bool = true, mode: Mode = .cw) async throws -> RigApp {
        let rigApp = try await RigApp.make { config, _ in
            config.autoSendThreshold = threshold
            config.esm.enabled = true
            config.cwKeyer.method = .cat
        }
        rigApp.entry.setMode(mode)
        rigApp.model.operating.runMode = run ? .run : .searchAndPounce
        return rigApp
    }

    private static func type(_ entry: EntryModel, _ call: String) {
        var text = ""
        for character in call {
            text.append(character)
            entry.callChanged(text)
        }
    }

    private static func texts(_ keyer: RecordingKeyer) -> [String] {
        keyer.transmissions.compactMap { transmission in
            if case .cw(let message, -1) = transmission {
                return EntryAssist.sentText(message)
            }
            return nil
        }
    }

    @Test func callGoesOutWhileTyped() async throws {
        let rigApp = try await Self.make(threshold: 2)
        Self.type(rigApp.entry, "DL1ABC")
        #expect(Self.texts(rigApp.keyer) == ["DL1AB", "C"])
        #expect(rigApp.entry.esmProgress.sentCall == "DL1ABC")
        rigApp.entry.esmEnter()
        #expect(rigApp.keyer.keys.last == [EsmEngine.f2])
    }

    @Test func offByDefaultAndOnlyInRunCw() async throws {
        let off = try await Self.make(threshold: 0)
        Self.type(off.entry, "DL1ABC")
        #expect(off.keyer.transmissions.isEmpty)
        let sp = try await Self.make(threshold: 1, run: false)
        Self.type(sp.entry, "DL1ABC")
        #expect(sp.keyer.transmissions.isEmpty)
        let ssb = try await Self.make(threshold: 1, mode: .ssb)
        Self.type(ssb.entry, "DL1ABC")
        #expect(ssb.keyer.transmissions.isEmpty)
    }

    /// A new QSO (the call cleared) starts over.
    @Test func clearedCallStartsOver() async throws {
        let rigApp = try await Self.make(threshold: 1)
        Self.type(rigApp.entry, "DL1A")
        rigApp.entry.callChanged("")
        Self.type(rigApp.entry, "OK1X")
        #expect(Self.texts(rigApp.keyer) == ["DL1A", "OK1X"])
    }

    @Test func menuPromptSavesTheThreshold() async throws {
        let rigApp = try await Self.make(threshold: 0)
        MenuActions.applyAutoSend("3", config: rigApp.model.config, status: rigApp.model.status)
        #expect(rigApp.model.config.config.autoSendThreshold == 3)
        MenuActions.applyAutoSend("x", config: rigApp.model.config, status: rigApp.model.status)
        #expect(rigApp.model.config.config.autoSendThreshold == 3)
        #expect(rigApp.status.contains("0–20"))
    }
}
