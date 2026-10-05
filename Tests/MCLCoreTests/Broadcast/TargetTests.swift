import Testing
@testable import MCLCore

/// Port of the Java `broadcast/TargetTest`.
@Suite struct TargetTests {

    @Test func single() {
        #expect(Target.parseAll("127.0.0.1:12060") == [Target(host: "127.0.0.1", port: 12060)])
    }

    @Test func multipleSpaceAndComma() {
        #expect(Target.parseAll("127.0.0.1:12060 10.0.0.2:13063").count == 2)
        #expect(Target.parseAll("a:1, b:2").count == 2)
    }

    @Test func ignoresMalformed() {
        #expect(Target.parseAll("bad").isEmpty)
        #expect(Target.parseAll("host:").isEmpty)
        #expect(Target.parseAll(":123").isEmpty)
        #expect(Target.parseAll("h:70000").isEmpty)
    }

    @Test func nullAndBlank() {
        #expect(Target.parseAll(nil).isEmpty)
        #expect(Target.parseAll("   ").isEmpty)
    }
}
