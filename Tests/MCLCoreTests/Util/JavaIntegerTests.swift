import Testing
@testable import MCLCore

/// Tests of `JavaInteger.parseInt` — Java `Integer.parseInt(String)`.
///
/// Values measured on JDK 21.0.2 (`ProbeBasics.java`). `nil` stands where
/// Java throws `NumberFormatException`.
@Suite struct JavaIntegerTests {

    @Test func parseIntMatchesJava() {
        let measured: [(String, Int32?)] = [
            ("+7", 7),
            ("-0", 0),
            ("\u{663}", 3),                 // Arabic-Indic three (Nd)
            ("\u{FF11}\u{FF12}", 12),       // fullwidth digits
            ("\u{661}\u{665}", 15),
            ("00012", 12),
            ("2147483647", 2_147_483_647),
            ("2147483648", nil),
            ("-2147483648", -2_147_483_648),
            ("-2147483649", nil),
            (" 7", nil),                    // parseInt does not trim
            ("7 ", nil),
            ("", nil),
            ("+", nil),
            ("-", nil),
            ("+-1", nil),
            ("0x10", nil),
            ("1_0", nil),
            ("\u{1D7CE}", nil),             // a mathematical zero outside the BMP: a pair of surrogate units
        ]
        for (text, expected) in measured {
            #expect(JavaInteger.parseInt(text) == expected, "parseInt(\(text.debugDescription))")
        }
    }

    /// The only implementation: the YAML decoder and `cty.dat` call the same function.
    @Test func otherParsersDelegate() {
        #expect(JacksonCoercion.parseInt("\u{663}") == 3)
        #expect(JacksonCoercion.parseInt("2147483648") == nil)
        #expect(CtyDxccResolver.javaParseInt("\u{663}") == 3)
        #expect(CtyDxccResolver.javaParseInt("-2147483648") == -2_147_483_648)
    }

    /// `Long.parseLong` (`RigctldClient.parseLongSafe`.1 R5): `+`, Unicode digits
    /// `Nd`, overflow and the exception text. Measured on JDK 21.0.2 (maintainer-only probe,
    /// rows `PL`); `EXC` = `NumberFormatException` with a verbatim message.
    @Test func parseLongMatchesJava() {
        let measured: [(String, String)] = [
            ("0", "0"),
            ("+0", "0"),
            ("-0", "0"),
            ("14074000", "14074000"),
            ("+14074000", "14074000"),
            ("-1", "-1"),
            ("00012", "12"),
            ("\u{663}", "3"),
            ("\u{661}\u{664}\u{660}\u{667}\u{664}\u{660}\u{660}\u{660}", "14074000"),
            ("\u{FF11}\u{FF12}", "12"),
            ("1\u{660}", "10"),
            ("9223372036854775807", "9223372036854775807"),
            ("+9223372036854775807", "9223372036854775807"),
            ("9223372036854775808", "EXC For input string: \"9223372036854775808\""),
            ("-9223372036854775808", "-9223372036854775808"),
            ("-9223372036854775809", "EXC For input string: \"-9223372036854775809\""),
            ("99999999999999999999", "EXC For input string: \"99999999999999999999\""),
            (" 7", "EXC For input string: \" 7\""),
            ("7 ", "EXC For input string: \"7 \""),
            ("", "EXC For input string: \"\""),
            ("+", "EXC For input string: \"+\""),
            ("-", "EXC For input string: \"-\""),
            ("+-1", "EXC For input string: \"+-1\""),
            ("--1", "EXC For input string: \"--1\""),
            ("0x10", "EXC For input string: \"0x10\""),
            ("1_0", "EXC For input string: \"1_0\""),
            ("14.074e6", "EXC For input string: \"14.074e6\""),
            ("1e3", "EXC For input string: \"1e3\""),
            ("\u{1D7CE}", "EXC For input string: \"\u{1D7CE}\""),
            ("\u{2212}5", "EXC For input string: \"\u{2212}5\""),
            ("RPRT -1", "EXC For input string: \"RPRT -1\""),
            ("VFOA", "EXC For input string: \"VFOA\""),
            ("None", "EXC For input string: \"None\""),
        ]
        for (text, expected) in measured {
            let actual: String
            do {
                actual = String(try JavaInteger.parseLong(text))
            } catch {
                actual = "EXC " + error.message
            }
            #expect(actual == expected, "parseLong(\(text.debugDescription))")
        }
    }
}
