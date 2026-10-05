import Foundation
import Testing
@testable import MCLCore

/// The `java.util.Properties` format (JDK 21) for the `DefinitionUpdater` manifest — Java
/// v1.1.1 and the Swift version share the same data directory, so the manifest must be read
/// and written by both. Expected values were measured by the probe `ProbeProps.java`
/// (maintainer-only probe, modes `store`, `handcrafted`, `store-comment`);
/// the fixtures in `Fixtures/java-properties/` were produced by Java.
@Suite struct JavaPropertiesTests {

    static func fixture(_ name: String) throws -> Data {
        let dir = try #require(Bundle.module.url(forResource: "java-properties", withExtension: nil))
        return try Data(contentsOf: dir.appendingPathComponent(name))
    }

    static func pairs(_ properties: JavaProperties) -> [String] {
        properties.entries.map { "\($0.key)=\($0.value)" }
    }

    /// Pairs the probe saved with `Properties.store` into `store-jdk21.properties`,
    /// in the order Java wrote them (JDK 18+: sorted by key, `String.compareTo`).
    static let storedPairs: [(String, String)] = [
        ("", "empty key"),
        (" lead", "trailing  "),
        ("!bang", "!v"),
        ("#hash", "#v"),
        ("Z", "upper"),
        ("a", "lower"),
        ("back\\slash", "\\end\\"),
        ("bandplan.yaml", "71b61225da5647d865120f3669f36eaf7956d47067860038b6a8a3a53d80b0d0"),
        ("contests/a b.yaml", "  leading spaces"),
        ("contests/abc.yaml", "797484be2df74744ae0ca04e0570a2d8cfe93f657146b441f081bbf32f4a10d3"),
        ("contests/\u{E9}.yaml", "\u{17E}😀"),
        ("emptyvalue", ""),
        ("k:colon", "a:b=c"),
        ("k=eq", "=:#!"),
        ("multipliers/dxcc_entities.yaml", "c781536efadb6fd57b8a962bf99d471f9d3c287e3fbb71813600719aee239468"),
        ("tab\tkey", "multi\nline\r\u{C}\t"),
        ("😀", "\u{0}\u{7F}\u{80}\u{FF}"),
    ]

    static let comment = "Hash naposledy stažených souborů (lokálně upravené se nepřepisují)"

    // MARK: - reading what Java wrote

    @Test func readsManifestStoredByJava() throws {
        let properties = try JavaProperties.load(Self.fixture("store-jdk21.properties"))
        #expect(Self.pairs(properties) == Self.storedPairs.map { "\($0.0)=\($0.1)" })
        #expect(properties["contests/abc.yaml"] == "797484be2df74744ae0ca04e0570a2d8cfe93f657146b441f081bbf32f4a10d3")
        #expect(properties["neni"] == nil)
        #expect(properties.count == 17)
    }

    /// Hand-written input: `#`/`!` comments, `=`/`:`/space separators, line
    /// continuation, CR/LF/CRLF, escapes, Latin-1 bytes. Result = `handcrafted-out.txt`.
    @Test func readsHandcraftedInputLikeJava() throws {
        let properties = try JavaProperties.load(Self.fixture("handcrafted-jdk21.properties"))
        #expect(Self.pairs(properties) == [
            "=novalkey",
            " lead key=v",
            "after-blank-cont=1",
            "blank-cont=a",
            "comment-after-cont=a# not comment",
            "cont-over-crlf=ab",
            "cr-only=y",
            "crlf=x",
            "dup=second",
            "emptysep=",
            "emptyval=",
            "formfeed=ff",
            "indented=yes",
            "k:c=2",
            "k=eq=1",
            "key1=value1",
            "key2=value2",
            "key3=value3",
            "key4=value4",
            "key5=tabbed",
            "key6=continued more",
            "key7=a\\",
            "key9=line1\nline2\tTab\rX\u{C}YqZ",
            // Byte E9 and the UTF-8 pair C3 A9 are both read as Latin-1 (Java `load(InputStream)`).
            "latin1raw=\u{E9}\u{C3}\u{A9}",
            "sep-space-colon=y",
            "sep-twice==x",
            "tail=z",
            "unicode=\u{17E}\u{E9}😀",
            "x#y=hash inside key",
        ])
    }

    @Test func malformedUnicodeEscapeFailsLikeJava() {
        for text in ["k=\\u12G4\n", "k=\\u12", "\\uZZZZ=v"] {
            #expect(throws: JavaPropertiesError(message: "Malformed \\uxxxx encoding.")) {
                try JavaProperties.load(Data(text.utf8))
            }
        }
    }

    /// Regression: `\uXXXX` near U+FFFF (also upper/lower case) overflowed
    /// the intermediate sum in `UInt16` and the app crashed (SIGTRAP); Java reads them.
    @Test func unicodeEscapesNearFFFFDoNotOverflow() throws {
        let text = "a=\\uFFFD\nb=\\uffff\nc=\\uFFBF\nd=\\uFFCF\ne=\\uffd0\nf=\\uFfFf\ng=\\u9999\n"
        let properties = try JavaProperties.load(Data(text.utf8))
        #expect(properties["a"] == "\u{FFFD}")
        #expect(properties["b"] == "\u{FFFF}")
        #expect(properties["c"] == "\u{FFBF}")
        #expect(properties["d"] == "\u{FFCF}")
        #expect(properties["e"] == "\u{FFD0}")
        #expect(properties["f"] == "\u{FFFF}")
        #expect(properties["g"] == "\u{9999}")
        // Writing goes back unchanged (upper-case hex as in Java).
        let stored = String(decoding: properties.store(comments: nil, dateLine: "D"), as: UTF8.self)
        #expect(stored == "#D\na=\\uFFFD\nb=\\uFFFF\nc=\\uFFBF\nd=\\uFFCF\ne=\\uFFD0\nf=\\uFFFF\ng=\\u9999\n")
    }

    @Test func emptyInputIsEmpty() throws {
        #expect(try JavaProperties.load(Data()).count == 0)
        #expect(try JavaProperties.load(Data("# jen komentář\n\n   \n".utf8)).count == 0)
    }

    // MARK: - writing that Java reads

    /// Swift writes the same pairs **byte-identically** to Java's `Properties.store`
    /// (the date line is substituted so it can be compared). The Java probe read the file
    /// written by Swift with the same pairs.
    @Test func storeIsByteIdenticalToJava() throws {
        var properties = JavaProperties()
        for (key, value) in Self.storedPairs.reversed() {
            properties[key] = value
        }
        let data = properties.store(comments: Self.comment, dateLine: "Wed Sep 30 18:57:58 CEST 2026")
        #expect(data == (try Self.fixture("store-jdk21.properties")))
    }

    /// Comments: characters above U+00FF as `\uXXXX`, Latin-1 characters raw, a line break
    /// gets `#` unless the next character is `#`/`!` (`comment-out.txt`).
    @Test func commentsAreWrittenLikeJava() {
        let cases: [(String?, [UInt8])] = [
            ("a\nb", Array("#a\n#b\n".utf8)),
            ("a\n#b", Array("#a\n#b\n".utf8)),
            ("a\n!b", Array("#a\n!b\n".utf8)),
            ("a\r\nb", Array("#a\n#b\n".utf8)),
            ("a\rb", Array("#a\n#b\n".utf8)),
            ("x\n", Array("#x\n#\n".utf8)),
            ("ž é😀", Array("#\\u017E ".utf8) + [0xE9] + Array("\\uD83D\\uDE00\n".utf8)),
            ("", Array("#\n".utf8)),
            (nil, []),
        ]
        var properties = JavaProperties()
        properties["k"] = "v"
        for (comment, header) in cases {
            let expected = header + Array("#D\nk=v\n".utf8)
            #expect(Array(properties.store(comments: comment, dateLine: "D")) == expected, "\(String(describing: comment))")
        }
    }

    /// The date line = Java `Date.toString()` (`EEE MMM dd HH:mm:ss zzz yyyy`,
    /// in English). ICU gives the zone abbreviation the same as Java only in some places (EDT yes,
    /// CEST no — Swift writes `GMT+2` there); Java skips the line when reading.
    @Test func dateLineMatchesJavaFormat() throws {
        var properties = JavaProperties()
        properties["k"] = "v"
        let date = Date(timeIntervalSince1970: 1_790_787_478)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let text = String(decoding: properties.store(comments: nil, date: date, timeZone: newYork), as: UTF8.self)
        #expect(text == "#Wed Sep 30 12:57:58 EDT 2026\nk=v\n")
    }

    // MARK: - map properties

    /// Keys are compared like Java `String.equals` (by UTF-16), not canonically:
    /// NFC and NFD `é` are two different keys and both survive writing and reading.
    @Test func keysAreComparedByUTF16() throws {
        var properties = JavaProperties()
        properties["\u{E9}"] = "nfc"
        properties["e\u{301}"] = "nfd"
        #expect(properties.count == 2)
        #expect(properties["\u{E9}"] == "nfc")
        #expect(properties["e\u{301}"] == "nfd")
        let back = try JavaProperties.load(properties.store(comments: nil, dateLine: "D"))
        #expect(back == properties)
        #expect(Self.pairs(back) == ["e\u{301}=nfd", "\u{E9}=nfc"])
    }

    @Test func setToNilRemovesKey() {
        var properties = JavaProperties()
        properties["a"] = "1"
        properties["a"] = nil
        #expect(properties.count == 0)
    }

    /// A lone surrogate (`\uD800`) survives reading and writing unchanged; the getter shows it
    /// as U+FFFD, because a Swift `String` cannot hold a surrogate.
    @Test func loneSurrogateSurvivesRoundTrip() throws {
        let properties = try JavaProperties.load(Data("k=\\uD800x\n".utf8))
        #expect(properties["k"] == "\u{FFFD}x")
        let text = String(decoding: properties.store(comments: nil, dateLine: "D"), as: UTF8.self)
        #expect(text == "#D\nk=\\uD800x\n")
    }

    @Test func roundTripOfArbitraryPairs() throws {
        var properties = JavaProperties()
        for (key, value) in Self.storedPairs {
            properties[key] = value
        }
        properties["  two lead"] = " \\ \u{1F}\u{7E}"
        properties["\u{FFFD}klíč\u{FFFF}"] = "\u{FFFD}\u{FFBF}\u{FFFF}"
        let back = try JavaProperties.load(properties.store(comments: Self.comment, date: Date()))
        #expect(back == properties)
    }
}
