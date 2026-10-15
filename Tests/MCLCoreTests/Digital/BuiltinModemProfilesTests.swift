import Foundation
@testable import MCLCore
import Testing

/// MMTTY's modem profiles for the built-in modem: a receiver's setup saved into a slot and applied to another
/// receiver; the file keeps 16 slots and is never overwritten when unreadable.
@Suite struct BuiltinModemProfilesTests {

    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-profiles-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func profileCarriesTheWholeSetup() throws {
        let source = BuiltinRttyChannel()
        source.update { $0.shiftHz = 425; $0.baud = 75; $0.markHz = 1500; $0.afc = false; $0.net = false }
        source.set("demodType", choice: "pll")
        source.set("squelch", flag: true)
        source.set("firTaps", number: 128)
        let values = source.profileValues()
        #expect(values["echo"] == nil)
        #expect(values["demodType"] == .choice("pll"))
        let target = BuiltinRttyChannel()
        target.apply(profile: values)
        #expect(target.tuning == source.tuning)
        #expect(target.choice("demodType") == "pll")
        #expect(target.flag("squelch") == true)
        #expect(target.number("firTaps") == 128)
        // Unknown and out-of-range values are skipped.
        target.apply(profile: ["nonsense": .flag(true), "baud": .number(5_000), "demodType": .choice("fft")])
        #expect(target.tuning.baud == 75)
        #expect(target.choice("demodType") == "fft")
    }

    @Test func slotsAreStoredAndAnUnreadableFileIsKept() throws {
        let directory: URL = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BuiltinModemProfiles(directory: directory)
        #expect(store.load().count == 16)
        #expect(store.load().allSatisfy { $0 == nil })
        let profile = BuiltinModemProfile(name: "850 Hz", values: ["shift": .number(850)])
        try store.save(profile, slot: 3)
        #expect(BuiltinModemProfiles(directory: directory).load()[3] == profile)
        #expect(throws: BuiltinModemProfiles.Failure.badSlot(16)) { try store.save(profile, slot: 16) }
        try store.save(nil, slot: 3)
        #expect(store.load()[3] == nil)
        try Data("garbage".utf8).write(to: store.url)
        #expect(throws: BuiltinModemProfiles.Failure.unreadable) { try store.save(profile, slot: 0) }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "garbage")
    }
}
