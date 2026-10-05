import Testing
@testable import MCLCore

/// `digital/` against tables measured on Java (`VoiceAudioMeasured`; probes `research/ProbeP6.java`
/// and `voice-audio/ProbeVoiceAudio.java`): XML-RPC, `RxTextStream`, `TextTokens`,
/// `RecentCalls`.
@Suite struct DigitalMeasuredTests {

    static func research(_ id: String) -> [[String]] {
        ProbeRows.rows(VoiceAudioMeasured.research, id)
    }

    static func extra(_ id: String) -> [[String]] {
        ProbeRows.rows(VoiceAudioMeasured.extra, id)
    }

    // MARK: - XmlRpc

    @Test func callMatchesJava() {
        let research = XmlRpc.call(
            "m&<>", .string("a&b<c>\"'"), .int(5), .int(5), .double(1.5), .double(1.5), .bool(true), .bool(false),
            .string(nil), .string("c"), .double(1e20), .double(-0.0), .double(.nan))
        #expect(research == Self.research("XR.call")[0][0])
        #expect(XmlRpc.call("main.tx") == Self.extra("XR.callEmpty")[0][0])
        let long = XmlRpc.call(
            "x", .int(.max), .int(Int64(Int32.min)), .double(0.1), .double(1e7), .double(1e-3), .double(123_456_789.0),
            .double(-.infinity), .double(.leastNonzeroMagnitude), .string(""), .string("\u{17E}\n\t]]>"))
        #expect(long == Self.extra("XR.callLong")[0][0])
    }

    /// Java `getClass().getSimpleName() + ":" + value` (probe), `byte[]` as hex.
    static func describe(_ xml: String) -> String {
        do {
            switch try XmlRpc.parseResponse(xml) {
            case nil: return "<null>"
            case .string(let s): return "String:" + s
            case .int(let n): return "Integer:" + String(n)
            case .double(let d): return "Double:" + JavaDouble.toString(d)
            case .bool(let b): return "Boolean:" + String(b)
            case .bytes(let bytes):
                return "byte[]:" + bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
            }
        } catch {
            return "EXC IllegalStateException: " + error.message
        }
    }

    /// Parser error texts from Xerces — Swift has different ones (libxml2), only the prefix is compared.
    static let xercesMessages: Set<String> = [
        "Premature end of file.",
        "Content is not allowed in prolog.",
        "XML document structures must start and end within the same entity.",
        "The element type \"x\" must be terminated by the matching end-tag \"</x>\".",
        "The entity \"unknown\" was referenced, but not declared.",
        "The markup in the document following the root element must be well-formed.",
    ]

    static func check(_ got: String, _ expected: String, _ input: String) {
        let prefix = "EXC IllegalStateException: " + XmlRpc.invalidPrefix
        if expected.hasPrefix(prefix), xercesMessages.contains(String(expected.dropFirst(prefix.count))) {
            #expect(got.hasPrefix(prefix), "\(input): \(got)")
        } else {
            #expect(got == expected, "\(input)")
        }
    }

    @Test func parseValuesMatchJava() {
        let rows = Self.research("XR.parse") + Self.extra("XR.parse")
        #expect(rows.count == 58)
        for row in rows {
            let xml = FldigiClientTests.response(row[0])
            Self.check(Self.describe(xml), row[1], row[0])
        }
    }

    @Test func parseDocumentsMatchJava() {
        let rows = Self.research("XR.parseDoc") + Self.extra("XR.parseDoc")
        #expect(rows.count == 26)
        for row in rows {
            Self.check(Self.describe(row[0]), row[1], row[0])
        }
    }

    // MARK: - RxTextStream

    @Test func rxTextStreamMatchesJava() {
        let rx = RxTextStream(maxChars: 5)
        let first = Self.research("RX.pending")[0]
        #expect([Self.span(rx.pending(3)), Self.span(rx.pending(-1))] == first)
        rx.append("ab\u{1F600}cd\u{85}\u{7F}\u{0}\te")
        let raw = ProbeRows.rawRows(VoiceAudioMeasured.research, "RX.text")[0]
        #expect(rx.textUnits == ProbeRows.unescapeUnits(raw[0]))
        #expect(Self.span(rx.pending(8)) == ProbeRows.unescape(raw[1]))
        #expect(Self.span(rx.pending(9)) == ProbeRows.unescape(raw[2]))
    }

    static func span(_ span: RxTextStream.Span?) -> String {
        span.map { "Optional[Span[start=\($0.start), length=\($0.length)]]" } ?? "Optional.empty"
    }

    /// Truncation to `maxChars` UTF-16 units splits a surrogate pair like Java (`textUnits`).
    @Test func rxTrimSplitsSurrogatesLikeJava() {
        let rows = ProbeRows.rawRows(VoiceAudioMeasured.extra, "RX.trim")
        #expect(rows.count == 6)
        for row in rows {
            let rx = RxTextStream(maxChars: Int32(row[0])!)
            rx.append(ProbeRows.unescape(row[1]))
            let expected = ProbeRows.unescapeUnits(String(row[2].dropFirst("String:".count)))
            #expect(rx.textUnits == expected, "\(row)")
        }
    }

    @Test func rxSequenceMatchesJava() {
        let s = RxTextStream(maxChars: 100)
        var seq: [String] = []
        seq.append(Self.span(s.pending(.max)))
        s.append(nil)
        s.append("")
        seq.append(Self.span(s.pending(0)))
        s.append("\u{1F600}\u{7}")
        seq.append(Self.span(s.pending(3)))
        seq.append(Self.span(s.pending(4)))
        seq.append(Self.span(s.pending(2)))
        seq.append(Self.span(s.pending(.min)))
        seq.append(s.text)
        #expect(ProbeRows.javaList(seq) == Self.extra("RX.sequence")[0][0])
    }

    // MARK: - TextTokens

    static func describe(_ tokens: [TextTokens.Token]) -> String {
        ProbeRows.javaList(tokens.map { "Token[start=\($0.start), end=\($0.end), word=\($0.word)]" })
    }

    @Test func textTokensMatchJava() {
        #expect(Self.describe(TextTokens.words("a\u{A0}b c\u{2003}d\u{1C}e\u{85}f\u{200B}g\u{1F600} h"))
            == Self.research("TT.words")[0][0])
        #expect(ProbeRows.javaList(TextTokens.byLine("a\r\nb\n\n c \n").map(Self.describe))
            == Self.research("TT.byLine")[0][0])
        let words = Self.extra("TT.words")
        let lines = Self.extra("TT.byLine")
        #expect(words.count == 9 && lines.count == 9)
        for row in words {
            #expect(Self.describe(TextTokens.words(row[0])) == row[1], "\(row)")
        }
        for row in lines {
            #expect(ProbeRows.javaList(TextTokens.byLine(row[0]).map(Self.describe)) == row[1], "\(row)")
        }
    }

    // MARK: - RecentCalls

    @Test func recentCallsMatchJava() {
        let zero = RecentCalls(max: 0)
        zero.offer("A")
        #expect(ProbeRows.javaList(zero.calls) == Self.research("RC.max0")[0][0])
        let exact = RecentCalls(max: 2)
        exact.offer(" A ")
        exact.offer("A")
        exact.offer("a")
        #expect(ProbeRows.javaList(exact.calls) == Self.research("RC.case")[0][0])
        let negative = RecentCalls(max: -1)
        negative.offer("A")
        #expect(ProbeRows.javaList(negative.calls) == Self.extra("RC.negative")[0][0])
        let sequence = RecentCalls(max: 3)
        for call in ["A", "\u{2003}", "\u{A0}", "B", "A", "C", "D", "B"] {
            sequence.offer(call)
        }
        #expect(ProbeRows.javaList(sequence.calls) == Self.extra("RC.sequence")[0][0])
        sequence.clear()
        #expect(ProbeRows.javaList(sequence.calls) == Self.extra("RC.clear")[0][0])
    }

    /// Java equality by UTF-16 units: composed and decomposed `é` are two different callsigns.
    @Test func recentCallsCompareUnitsNotCanonically() {
        let r = RecentCalls(max: 4)
        r.offer("\u{E9}")
        r.offer("e\u{301}")
        #expect(r.calls.count == 2)
    }
}
