import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM `RadioNr`: a QSO is stored with the radio (SO2R) or the VFO window (SO2V) it was logged from; one radio = 1.
@MainActor @Suite struct RadioNrLoggingTests {

    static func log(_ app: RigApp, _ entry: EntryModel, _ call: String, kHz: String) async {
        entry.setFrequency(kHz)
        entry.callChanged(call)
        entry.submit()
        await entry.settle()
        await app.settle()
    }

    @Test(arguments: ["SO2R", "SO2V"])
    func eachWindowLogsItsRadio(mode: String) async throws {
        let app = try await RigApp.make { config, _ in
            config.radioMode = mode
        }
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        await Self.log(app, app.entry, "DL1ABC", kHz: "14025")
        await Self.log(app, second, "OK1AB", kHz: "7010")

        let byCall: [String: Int] = Dictionary(uniqueKeysWithValues: app.model.logbook.rows.map { ($0.call, $0.radioNr) })
        #expect(byCall == ["DL1ABC": 1, "OK1AB": 2])
    }

    @Test func oneRadioLogsRadioOne() async throws {
        let app = try await RigApp.make()
        await Self.log(app, app.entry, "DL1ABC", kHz: "14025")
        #expect(app.model.logbook.rows.map(\.radioNr) == [1])
    }
}
