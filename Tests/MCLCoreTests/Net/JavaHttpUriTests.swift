import Testing
@testable import MCLCore

/// `JavaHttpUri.parse` = Java `URI.create` + `HttpRequest.newBuilder(URI)` (`checkURI`). Expected values
/// measured by the maintainer-only probe (rows `URI.<n>`, JDK 21): success
/// `scheme|host|port|rawPath|rawQuery`, otherwise the text of `IllegalArgumentException.getMessage()`.
@Suite struct JavaHttpUriTests {

    private struct Case: Sendable {
        let input: String
        let expected: String
    }

    private static let iae = "ERR "

    private static let cases: [Case] = [
        Case(input: "https://www.hamqth.com/xml.php?u=OK1XOE&p=secret",
             expected: "OK https|www.hamqth.com|-1|/xml.php|u=OK1XOE&p=secret"),
        Case(input: "https://www.hamqth.com/xml.php?id=abc def&callsign=W1AW&prg=MacContestLogger",
             expected: "ERR Illegal character in query at index 37: https://www.hamqth.com/xml.php?id=abc def&callsign=W1AW&prg=MacContestLogger"),
        Case(input: "https://xmldata.qrz.com/xml/current/?s=key with space;callsign=W1AW",
             expected: "ERR Illegal character in query at index 42: https://xmldata.qrz.com/xml/current/?s=key with space;callsign=W1AW"),
        Case(input: "https://www.hamqth.com/xml.php?id=a|b",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a|b"),
        Case(input: "https://www.hamqth.com/xml.php?id=a\"b",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a\"b"),
        Case(input: "https://www.hamqth.com/xml.php?id=a<b>",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a<b>"),
        Case(input: "https://www.hamqth.com/xml.php?id={x}",
             expected: "ERR Illegal character in query at index 34: https://www.hamqth.com/xml.php?id={x}"),
        Case(input: "https://www.hamqth.com/xml.php?id=a^b`c",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a^b`c"),
        Case(input: "https://www.hamqth.com/xml.php?id=a\\b",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a\\b"),
        Case(input: "https://www.hamqth.com/xml.php?id=%zz",
             expected: "ERR Malformed escape pair at index 34: https://www.hamqth.com/xml.php?id=%zz"),
        Case(input: "https://www.hamqth.com/xml.php?id=%4",
             expected: "ERR Malformed escape pair at index 34: https://www.hamqth.com/xml.php?id=%4"),
        Case(input: "https://www.hamqth.com/xml.php?id=[x]", expected: "OK https|www.hamqth.com|-1|/xml.php|id=[x]"),
        Case(input: "https://www.hamqth.com/xml.php?id=a\tb",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a\tb"),
        Case(input: "https://www.hamqth.com/xml.php?id=a\nb",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=a\nb"),
        Case(input: "https://www.hamqth.com/xml.php?id=\u{010D}\u{00A0}",
             expected: "ERR Illegal character in query at index 35: https://www.hamqth.com/xml.php?id=\u{010D}\u{00A0}"),
        Case(input: "https://www.hamqth.com/xml.php?id=\u{010D}", expected: "OK https|www.hamqth.com|-1|/xml.php|id=\u{010D}"),
        Case(input: "https://host/p\u{00E1}th?q=\u{1F600}", expected: "OK https|host|-1|/p\u{00E1}th|q=\u{1F600}"),
        Case(input: "https://host/a b", expected: "ERR Illegal character in path at index 14: https://host/a b"),
        Case(input: "https://host/a#frag ment",
             expected: "ERR Illegal character in fragment at index 19: https://host/a#frag ment"),
        Case(input: "https://host/a#frag", expected: "OK https|host|-1|/a|null"),
        Case(input: "", expected: "ERR URI with undefined scheme"),
        Case(input: "foo", expected: "ERR URI with undefined scheme"),
        Case(input: "/relative/path", expected: "ERR URI with undefined scheme"),
        Case(input: "ftp://host/file", expected: "ERR invalid URI scheme ftp"),
        Case(input: "mailto:a@b.cz", expected: "ERR invalid URI scheme mailto"),
        Case(input: "http:opaque", expected: "ERR unsupported URI http:opaque"),
        Case(input: "http://", expected: "ERR Expected authority at index 7: http://"),
        Case(input: "http:///path", expected: "ERR unsupported URI http:///path"),
        Case(input: "http://a b/", expected: "ERR Illegal character in authority at index 8: http://a b/"),
        Case(input: "http://host:abc/", expected: "ERR unsupported URI http://host:abc/"),
        Case(input: "http://host:99999/", expected: "OK http|host|99999|/|null"),
        Case(input: "http://host:/x", expected: "OK http|host|-1|/x|null"),
        Case(input: "http://[::1]:8080/post/", expected: "OK http|[::1]|8080|/post/|null"),
        Case(input: "http://[::1/post/",
             expected: "ERR Expected closing bracket for IPv6 address at index 11: http://[::1/post/"),
        Case(input: "http://[zz]/", expected: "ERR Malformed IPv6 address at index 8: http://[zz]/"),
        Case(input: "http://[fe80::1%en0]/", expected: "OK http|[fe80::1%en0]|-1|/|null"),
        Case(input: "http://-host.com/", expected: "ERR unsupported URI http://-host.com/"),
        Case(input: "http://host-.com/", expected: "ERR unsupported URI http://host-.com/"),
        Case(input: "http://a_b.com/", expected: "ERR unsupported URI http://a_b.com/"),
        Case(input: "http://1.2.3.4.5/", expected: "ERR unsupported URI http://1.2.3.4.5/"),
        Case(input: "http://256.1.1.1/", expected: "ERR unsupported URI http://256.1.1.1/"),
        Case(input: "http://user:pw@host/", expected: "OK http|host|-1|/|null"),
        Case(input: "http://us er@host/", expected: "ERR Illegal character in authority at index 9: http://us er@host/"),
        Case(input: "HTTP://Host.Example/x", expected: "OK HTTP|Host.Example|-1|/x|null"),
        Case(input: "Https://host", expected: "OK Https|host|-1||null"),
        Case(input: "1http://x", expected: "ERR Illegal character in scheme name at index 0: 1http://x"),
        Case(input: "://x", expected: "ERR Expected scheme name at index 0: ://x"),
        Case(input: "http://ho\u{010D}st/", expected: "ERR unsupported URI http://ho\u{010D}st/"),
        Case(input: "http://host/%", expected: "ERR Malformed escape pair at index 12: http://host/%"),
        Case(input: "https://contestonlinescore.com/post/", expected: "OK https|contestonlinescore.com|-1|/post/|null"),
        Case(input: "http://127.0.0.1:8080/post/", expected: "OK http|127.0.0.1|8080|/post/|null"),
        Case(input: "http://localhost:8080/post/", expected: "OK http|localhost|8080|/post/|null"),
        Case(input: "http://host?x", expected: "OK http|host|-1||x"),
        Case(input: "http://host#f", expected: "OK http|host|-1||null"),
        Case(input: "http://host.123/", expected: "ERR unsupported URI http://host.123/"),
        Case(input: "http://123/", expected: "OK http|123|-1|/|null"),
        // IPv6 and port branches (`URI.56`–`URI.65`).
        Case(input: "http://[1:2:3:4:5:6:7:8:9]/", expected: "ERR IPv6 address too long at index 8: http://[1:2:3:4:5:6:7:8:9]/"),
        Case(input: "http://[1:2:3]/", expected: "ERR IPv6 address too short at index 8: http://[1:2:3]/"),
        Case(input: "http://[12345::]/",
             expected: "ERR IPv6 hexadecimal digit sequence too long at index 8: http://[12345::]/"),
        Case(input: "http://[::1.2.3.4]/", expected: "OK http|[::1.2.3.4]|-1|/|null"),
        Case(input: "http://[fe80::1%]/", expected: "ERR scope id expected: http://[fe80::1%]/"),
        Case(input: "http://[1:2:3:4:5:6:7:8::]/", expected: "ERR Malformed IPv6 address at index 8: http://[1:2:3:4:5:6:7:8::]/"),
        Case(input: "http://[::1.2.3.999]/", expected: "ERR Malformed IPv4 address at index 16: http://[::1.2.3.999]/"),
        Case(input: "http://host:2147483648/", expected: "ERR unsupported URI http://host:2147483648/"),
        Case(input: "http://[::1]x/", expected: "ERR Expected port number at index 12: http://[::1]x/"),
        Case(input: "http://a@b@c/", expected: "ERR unsupported URI http://a@b@c/"),
    ]

    private static func describe(_ input: String) -> String {
        do {
            let uri = try JavaHttpUri.parse(input)
            let fields: [String] = [uri.scheme, uri.host, String(uri.port), uri.rawPath, uri.rawQuery ?? "null"]
            return "OK " + fields.joined(separator: "|")
        } catch {
            return iae + error.message
        }
    }

    @Test func matchesJavaUriCreateAndCheckUri() {
        for item in Self.cases {
            #expect(Self.describe(item.input) == item.expected, "\(item.input)")
        }
    }

    /// The request target like Java `Utils.encode(rawPath?rawQuery)`: NFC, non-ASCII as UTF-8 `%XX`; an empty
    /// path → `/`; the fragment and userinfo are not sent.
    @Test func requestUrlEncodesLikeJava() throws {
        let cases: [(String, String)] = [
            ("https://host/p\u{00E1}th?q=\u{1F600}", "https://host/p%C3%A1th?q=%F0%9F%98%80"),
            ("https://host/a#frag", "https://host/a"),
            ("Https://host", "https://host/"),
            ("http://user:pw@host:8080/x?y=1", "http://host:8080/x?y=1"),
            ("http://127.0.0.1:8080/post/", "http://127.0.0.1:8080/post/"),
            ("https://www.hamqth.com/xml.php?id=[x]", "https://www.hamqth.com/xml.php?id=%5Bx%5D"),
            ("http://[fe80::1%en0]/", "http://[fe80::1%25en0]/"),
            ("http://[::1]:8080/post/", "http://[::1]:8080/post/"),
        ]
        for (input, expected) in cases {
            #expect(try JavaHttpUri.parse(input).requestURL?.absoluteString == expected, "\(input)")
        }
    }
}
