import Testing
@testable import MCLCore

/// `SpotModeCategory.of` = Kotlin `modeCategory` (`ui/AvailFilterDialog.kt:57`, v1.1.1); rows `modeCategory` of
/// a maintainer-only probe (JDK 21).
@Suite struct SpotModeCategoryTests {

    @Test(arguments: [
        ("CW", "CW"), ("cw", "CW"), (" CW ", "CW"), ("\u{00A0}CW\u{00A0}", "CW"),
        ("SSB", "PHONE"), ("USB", "PHONE"), ("LSB", "PHONE"), ("PH", "PHONE"), ("PHONE", "PHONE"),
        ("FM", "PHONE"), ("AM", "PHONE"), ("RTTY", "DIGI"), ("FT8", "DIGI"), ("DIGITAL", "DIGI"), ("", "DIGI"),
        ("ph", "PHONE"), ("\u{0131}", "DIGI"), ("Ph\u{00A0}", "PHONE"),
    ])
    func measuredCategories(_ mode: String, _ expected: String) {
        #expect(SpotModeCategory.of(mode) == expected)
    }
}
