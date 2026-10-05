import Testing
@testable import MCLCore

/// The text filters of the Settings fields (`ui/configurer/*.kt` `onValueChange`); expected values from
/// a maintainer-only probe (JDK 21).
@Suite struct SettingsInputFilterTests {

    private static let surrogateDigit = "\u{1D7D9}1"

    @Test(arguments: [
        ("12a3", "123", "12", "123", "123"),
        ("\u{0661}\u{0662}x3", "\u{0661}\u{0662}3", "\u{0661}\u{0662}", "\u{0661}\u{0662}3", "\u{0661}\u{0662}3"),
        (surrogateDigit, "1", "1", "1", "1"),
        ("-1.5,2", "152", "15", "-152", "1.5,2"),
        ("123456", "123456", "12", "123456", "123456"),
        (" 7 ", "7", "7", "7", "7"),
        ("\u{00B2}\u{00BD}9", "9", "9", "9", "9"),
    ])
    func digitFilters(_ input: String, _ digits: String, _ two: String, _ minus: String, _ dot: String) {
        #expect(SettingsInputFilter.digits(limit: nil).apply(input) == digits)
        #expect(SettingsInputFilter.digits(limit: 2).apply(input) == two)
        #expect(SettingsInputFilter.digitsAnd(extra: "-").apply(input) == minus)
        #expect(SettingsInputFilter.digitsAnd(extra: ".,").apply(input) == dot)
    }

    @Test func uppercaseTrimAndNone() {
        #expect(SettingsInputFilter.uppercase.apply("ok1xoe/p") == "OK1XOE/P")
        #expect(SettingsInputFilter.uppercase.apply("stra\u{00DF}e") == "STRASSE")
        #expect(SettingsInputFilter.uppercase.apply("\u{0131}i") == "II")
        #expect(SettingsInputFilter.trim.apply(" OP1 ") == "OP1")
        #expect(SettingsInputFilter.none.apply(" a ") == " a ")
    }

    @Test func blacklistAdd() {
        #expect(SettingsInputFilter.addingBlacklistEntry(" dl1abc ", to: ["OK1XOE"]) == ["OK1XOE", "DL1ABC"])
        #expect(SettingsInputFilter.addingBlacklistEntry("ok1xoe", to: ["OK1XOE"]) == nil)
        #expect(SettingsInputFilter.addingBlacklistEntry("   ", to: ["OK1XOE"]) == nil)
        #expect(SettingsInputFilter.addingBlacklistEntry("\u{0131}", to: ["I"]) == nil)
    }
}
