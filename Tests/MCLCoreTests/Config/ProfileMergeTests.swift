import Foundation
import Testing
@testable import MCLCore

/// `ProfileMerge` in readable hand-written cases; every expectation is a case of the JVM probe
/// (maintainer-only probe, number in brackets), the whole table is the parity suite `ProfileMergeJavaParityTests`.
@Suite struct ProfileMergeTests {

    static let source: String = "[Source: REDACTED (`StreamReadFeature.INCLUDE_SOURCE_IN_LOCATION` disabled); "

    static func merge(_ current: AppConfig, _ json: String) throws(ProfileMergeError) -> AppConfig {
        try ProfileMerge.merge(current: current, profileData: Data(json.utf8))
    }

    static func custom() -> AppConfig {
        var config = AppConfig()
        config.rig.host = "rig.local"
        config.rig.port = 4600
        config.keyBindings = ["log": "Ctrl+L", "run": "F1"]
        config.antennas = [AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "")]
        config.language = "en"
        config.contestDataDir = "/tmp/contest-data"
        return config
    }

    /// A nested object is merged field by field: a missing key keeps the current value (#2, #28).
    @Test func missingNestedKeyKeepsTheCurrentValue() throws {
        let merged = try Self.merge(Self.custom(), #"{"rig":{"port":4700}}"#)
        #expect(merged.rig.port == 4700)
        #expect(merged.rig.host == "rig.local")
        #expect(merged.language == "en")
    }

    /// A missing map keeps the current one, a present map replaces it whole (#5, #6, #31, #32).
    @Test func mapIsKeptWhenMissingAndReplacedWhole() throws {
        #expect(try Self.merge(Self.custom(), "{}").keyBindings == ["log": "Ctrl+L", "run": "F1"])
        #expect(try Self.merge(Self.custom(), #"{"keyBindings":{"cq":"F2"}}"#).keyBindings == ["cq": "F2"])
        #expect(try Self.merge(Self.custom(), #"{"keyBindings":{}}"#).keyBindings == [:])
    }

    /// An empty list replaces the current list, also inside a merged object (#4, #30, #33).
    @Test func emptyListReplacesTheCurrentList() throws {
        #expect(try Self.merge(Self.custom(), #"{"antennas":[]}"#).antennas.isEmpty)
        var current = Self.custom()
        current.dxCluster.favorites = [DxClusterFavorite()]
        current.dxCluster.minSkimmers = 3
        let merged = try Self.merge(current, #"{"dxCluster":{"favorites":[]}}"#)
        #expect(merged.dxCluster.favorites.isEmpty)
        #expect(merged.dxCluster.minSkimmers == 3)
    }

    /// `null` sets what the Java setter and getter make of it (#19, #20, #23, #26, #45, #46, #52; `ntpServer`: the
    /// `PROP` row `=""`). A nested object that Java leaves `null` (`rig`) is Swift's default — Java would crash later.
    @Test func nullSetsWhatTheJavaAccessorsMakeOfIt() throws {
        let current = Self.custom()
        #expect(try Self.merge(current, #"{"rig":null}"#).rig == RigConfig())
        #expect(try Self.merge(current, #"{"dxCluster":null}"#).dxCluster == DxClusterConfig())
        #expect(try Self.merge(current, #"{"language":null}"#).language == "cs")
        #expect(try Self.merge(current, #"{"ntpServer":null}"#).ntpServer == "")
        #expect(try Self.merge(current, #"{"contestDataDir":null}"#).contestDataDir == nil)
        // `port` is a primitive `int`: `null` sets 0 (the `PROP` row `=0`), read like a stored 0.
        let zeroPort = try JSONDecoder().decode(RigConfig.self, from: Data(#"{"port":0}"#.utf8)).port
        #expect(try Self.merge(current, #"{"rig":{"port":null}}"#).rig.port == zeroPort)
    }

    /// An unknown key fails with Jackson's message; the keys before it stay applied (#15).
    @Test func unknownKeyFailsAfterApplyingTheKeysBefore() throws {
        let current = AppConfig()
        let error = try #require(throws: ProfileMergeError.self) {
            try Self.merge(current, #"{"language":"de","unknownKey":1,"themeMode":"DARK"}"#)
        }
        #expect(error.javaClass == "com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException")
        let message = try #require(error.javaMessage)
        #expect(message.hasPrefix("Unrecognized field \"unknownKey\" (class cz.ok1xoe.maccontestlogger.config.AppConfig),"
                                  + " not marked as ignorable (73 known properties: \"windowGeometry\", \"recordContest\""))
        #expect(message.hasSuffix("\"rotatorPort\" [truncated])\n at " + Self.source + "line: 1, column: 32]"
                                  + " (through reference chain: cz.ok1xoe.maccontestlogger.config.AppConfig[\"unknownKey\"])"))
        #expect(error.partial.language == "de")
        #expect(error.partial.themeMode == current.themeMode)
    }

    /// A value of a wrong type fails with Jackson's message and location (#18).
    @Test func wrongTypeFailsWithJacksonsMessage() throws {
        let error = try #require(throws: ProfileMergeError.self) {
            try Self.merge(AppConfig(), #"{"language":"de","cwPitchHz":"abc"}"#)
        }
        #expect(error.javaClass == "com.fasterxml.jackson.databind.exc.InvalidFormatException")
        #expect(error.javaMessage == "Cannot deserialize value of type `int` from String \"abc\": not a valid `int` value\n at "
                + Self.source + "line: 1, column: 30] (through reference chain:"
                + " cz.ok1xoe.maccontestlogger.config.AppConfig[\"cwPitchHz\"])")
        #expect(error.partial.language == "de")
    }

    /// An empty (or only white-space) file fails before anything is applied (#12, #13).
    @Test func emptyFileFails() throws {
        for text in ["", " \n\t "] {
            let error = try #require(throws: ProfileMergeError.self) { try Self.merge(Self.custom(), text) }
            #expect(error.javaClass == "com.fasterxml.jackson.databind.exc.MismatchedInputException")
            #expect(error.javaMessage == "No content to map due to end-of-input\n at " + Self.source + "line: 1]")
            #expect(error.partial == Self.custom())
        }
    }

    /// Jackson's streaming quirk: an array where an object is merged is not consumed — the rest of the file is read
    /// inside it and the merge ends silently (#1611); a scalar there is ignored (#1619).
    @Test func arrayWhereAnObjectIsMergedEndsTheMerge() throws {
        #expect(try Self.merge(AppConfig(), #"{"rig":[1,2],"language":"en"}"#).language == "cs")
        #expect(try Self.merge(AppConfig(), #"{"rig":"x","language":"en"}"#).language == "en")
    }

    /// A profile written by Swift (`ConfigProfiles.save`) merges back key by key into any configuration. Red after
    /// adding a Swift-only configuration field: add it to `ProfileMergeSchema.swiftOnlyProperties`.
    @Test func profileSavedBySwiftMergesBack() throws {
        let saved = Self.custom()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(saved)
        #expect(try ProfileMerge.merge(current: AppConfig(), profileData: data) == saved)
    }

    /// Non-finite doubles in the live configuration survive an unrelated profile, as in Java's live object
    /// (probe cases #1728–#1730 on the base `N`); they never make the merge start from an empty configuration.
    @Test func nonFiniteDoublesInTheCurrentConfigurationAreKept() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            var current = Self.custom()
            current.runMode.repeatSeconds = value
            current.bandNotes = [BandNote(band: "20m", freqKHz: value, text: "x")]
            let merged = try Self.merge(current, #"{"language":"de"}"#)
            #expect(merged.language == "de")
            #expect(merged.rig == current.rig)
            #expect(merged.station == current.station)
            #expect(merged.keyBindings == current.keyBindings)
            #expect(merged.antennas == current.antennas)
            #expect(Self.same(merged.runMode.repeatSeconds, current.runMode.repeatSeconds))
            #expect(Self.same(try #require(merged.bandNotes.first).freqKHz, value))
        }
    }

    static func same(_ left: Double, _ right: Double) -> Bool {
        left == right || (left.isNaN && right.isNaN)
    }

    /// A Swift-only configuration field goes into `ProfileMergeSchema.swiftOnlyProperties`; with it, a profile
    /// carrying the key merges, without it the key is unknown to Jackson's schema.
    @Test func swiftOnlyPropertiesExtendTheGeneratedSchema() throws {
        let root = ProfileMergeSchema.root
        let extra = [root: [ProfileMergeSchema.Property("swiftOnlyFlag", .boolean, .fieldDefault)]]
        let extended = ProfileMergeSchema.extending(ProfileMergeSchema.generatedClasses, with: extra)
        let bean = try #require(extended[root])
        #expect(bean.known.last == "swiftOnlyFlag")
        #expect(bean.property("swiftOnlyFlag")?.kind == .boolean)
        let profile = Data(#"{"language":"de","swiftOnlyFlag":true}"#.utf8)
        var fields = try ProfileMerge.fields(of: AppConfig())
        try JacksonMergeReader(data: profile, rootDefaults: [:], classes: extended).mergeRoot(into: &fields)
        #expect(fields["swiftOnlyFlag"] == .bool(true))
        #expect(fields["language"] == .string("de"))
        #expect(throws: JacksonFailure.self) {
            var plain = try ProfileMerge.fields(of: AppConfig())
            try JacksonMergeReader(data: profile, rootDefaults: [:]).mergeRoot(into: &plain)
        }
        // The shipped extension table only adds properties to existing classes.
        #expect(Set(ProfileMergeSchema.swiftOnlyProperties.keys).isSubset(of: ProfileMergeSchema.generatedClasses.keys))
    }

    // MARK: - Names

    @Test func nameFromFileIsTheJsonSuffixCaseSensitively() {
        #expect(ProfileMerge.nameFromFile("Doma.json") == "Doma")
        #expect(ProfileMerge.nameFromFile(".json") == "")
        #expect(ProfileMerge.nameFromFile("a.json.json") == "a.json")
        #expect(ProfileMerge.nameFromFile("x.JSON") == nil)
        #expect(ProfileMerge.nameFromFile("json") == nil)
        #expect(ProfileMerge.nameFromFile("y.json.bak") == nil)
    }

    /// `String.compareTo`: UTF-16 units (upper case before lower case, a supplementary character before U+FF21).
    @Test func sortedNamesCompareUtf16Units() {
        #expect(ProfileMerge.sortedNames(["b", "a", "Z", "\u{FF21}", "\u{1F600}", "10", "9", ""])
                == ["", "10", "9", "Z", "a", "b", "\u{1F600}", "\u{FF21}"])
    }

    @Test func invalidNameCarriesJavasMessage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let profiles = ConfigProfiles<AppConfig>(dir: dir)
        let error = try #require(throws: ConfigProfilesError.self) { try profiles.save("a/b", AppConfig()) }
        #expect(error.javaMessage == "Neplatné jméno profilu: a/b")
        #expect(ConfigProfilesError.notFound("Doma").javaMessage == "Profil neexistuje: Doma")
    }

    /// A file name stored decomposed (NFD) is listed composed (NFC), as the JDK on macOS reports it, and sorts as
    /// U+00E9 (after `f`), not as `e` + U+0301 (before `f`).
    @Test func listComposesDecomposedFileNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["d.json", "e\u{301}.json", "f.json"] {
            try Data("{}".utf8).write(to: dir.appendingPathComponent(name))
        }
        let listed = ConfigProfiles<AppConfig>(dir: dir).list()
        #expect(listed == ["d", "f", "\u{E9}"])
        #expect(listed.last.map { Array($0.unicodeScalars) } == ["\u{E9}"])
    }

    @Test func listOfAMissingDirectoryIsEmpty() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(ConfigProfiles<AppConfig>(dir: dir).list().isEmpty)
    }
}
