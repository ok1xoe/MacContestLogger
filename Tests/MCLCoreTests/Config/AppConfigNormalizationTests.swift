import Foundation
import Testing
@testable import MCLCore

/// No Java ancestor as a whole — the Java normalisations have no tests of their own
/// (they are plain getters in `AppConfig.java`), but the behaviour they pin
/// exists in Java and `AppConfig.swift:246-286` is derived from it verbatim.
/// This file gives the eleven normalisers (`cwPitchHz`, `scoreReportingMinutes`,
/// `scoreReportingUrl`, `autoBackupKeep`, `autoBackupMinutes`, `rotatorPort`,
/// `rotorUdpPort`, `radioMode`, `cwSpeedStep`, `tuneStepCwHz`, `tuneStepSsbHz`)
/// at least one assertion — before, they had none, even though they run on every
/// decoding of `AppConfig`. Normalisation happens in `AppConfig.init(from:)`, so
/// it is tested via JSON decoding, not by a direct call (the normalisers are `private`).
@Suite struct AppConfigNormalizationTests {

    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    // MARK: - Seven Int normalisers with the same shape: a value <= 0 falls back to the default,
    // a positive value passes through unchanged. Java: `v <= 0 ? default : v`.

    @Test func nonPositiveIntFieldsFallBackToJavaDefaults() throws {
        #expect(try decode(#"{"cwPitchHz": 0}"#).cwPitchHz == 600)
        #expect(try decode(#"{"cwPitchHz": -1}"#).cwPitchHz == 600)
        #expect(try decode(#"{"autoBackupKeep": 0}"#).autoBackupKeep == 10)
        #expect(try decode(#"{"autoBackupKeep": -3}"#).autoBackupKeep == 10)
        #expect(try decode(#"{"rotatorPort": 0}"#).rotatorPort == 4533)
        #expect(try decode(#"{"rotatorPort": -1}"#).rotatorPort == 4533)
        #expect(try decode(#"{"rotorUdpPort": 0}"#).rotorUdpPort == 12040)
        #expect(try decode(#"{"rotorUdpPort": -1}"#).rotorUdpPort == 12040)
        #expect(try decode(#"{"cwSpeedStep": 0}"#).cwSpeedStep == 2)
        #expect(try decode(#"{"cwSpeedStep": -1}"#).cwSpeedStep == 2)
        #expect(try decode(#"{"tuneStepCwHz": 0}"#).tuneStepCwHz == 20)
        #expect(try decode(#"{"tuneStepCwHz": -1}"#).tuneStepCwHz == 20)
        #expect(try decode(#"{"tuneStepSsbHz": 0}"#).tuneStepSsbHz == 100)
        #expect(try decode(#"{"tuneStepSsbHz": -1}"#).tuneStepSsbHz == 100)
    }

    @Test func nonPositiveIntFieldsPassPositiveValuesThrough() throws {
        #expect(try decode(#"{"cwPitchHz": 700}"#).cwPitchHz == 700)
        #expect(try decode(#"{"autoBackupKeep": 3}"#).autoBackupKeep == 3)
        #expect(try decode(#"{"rotatorPort": 8080}"#).rotatorPort == 8080)
        #expect(try decode(#"{"rotorUdpPort": 12345}"#).rotorUdpPort == 12345)
        #expect(try decode(#"{"cwSpeedStep": 5}"#).cwSpeedStep == 5)
        #expect(try decode(#"{"tuneStepCwHz": 50}"#).tuneStepCwHz == 50)
        #expect(try decode(#"{"tuneStepSsbHz": 250}"#).tuneStepSsbHz == 250)
    }

    // MARK: - Two "floor" normalisations (Java `Math.max(floor, v)`) — unlike
    // the above, a negative/low value is not replaced by the default constant, it is merely
    // raised to the lower bound.

    @Test func scoreReportingMinutesIsClampedToFloorOfTwo() throws {
        #expect(try decode(#"{"scoreReportingMinutes": -5}"#).scoreReportingMinutes == 2)
        #expect(try decode(#"{"scoreReportingMinutes": 0}"#).scoreReportingMinutes == 2)
        #expect(try decode(#"{"scoreReportingMinutes": 1}"#).scoreReportingMinutes == 2)
        #expect(try decode(#"{"scoreReportingMinutes": 2}"#).scoreReportingMinutes == 2)
        #expect(try decode(#"{"scoreReportingMinutes": 10}"#).scoreReportingMinutes == 10)
    }

    @Test func autoBackupMinutesIsClampedToFloorOfZero() throws {
        #expect(try decode(#"{"autoBackupMinutes": -5}"#).autoBackupMinutes == 0)
        #expect(try decode(#"{"autoBackupMinutes": 0}"#).autoBackupMinutes == 0)
        #expect(try decode(#"{"autoBackupMinutes": 30}"#).autoBackupMinutes == 30)
    }

    // MARK: - Two string normalisations: empty/blank falls back to the default, other
    // strings (including just extra spaces around the content) pass through unchanged.

    @Test func scoreReportingUrlFallsBackToDefaultWhenBlank() throws {
        #expect(try decode(#"{"scoreReportingUrl": ""}"#).scoreReportingUrl
            == "https://contestonlinescore.com/post/")
        #expect(try decode(#"{"scoreReportingUrl": "   "}"#).scoreReportingUrl
            == "https://contestonlinescore.com/post/")
        #expect(try decode(#"{"scoreReportingUrl": "https://example.com/post/"}"#).scoreReportingUrl
            == "https://example.com/post/")
    }

    @Test func radioModeFallsBackToSo1vWhenBlank() throws {
        #expect(try decode(#"{"radioMode": ""}"#).radioMode == "SO1V")
        #expect(try decode(#"{"radioMode": "   "}"#).radioMode == "SO1V")
        #expect(try decode(#"{"radioMode": "SO2R"}"#).radioMode == "SO2R")
    }
}
