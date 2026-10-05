import AppKit
import MCLCore

/// The one palette of the spot windows (the Bandmap labels and the Available Multipliers rows, `BM:419-438`,
/// `AM:14-24`), with a light and a dark variant: the meaning of a colour stays — blue a good QSO,
/// red one multiplier, green two or more, grey a dupe — the shades follow the appearance. The band plan strip and the
/// band notes use colours outside it (`BM:405-418`), so a strip is never mistaken for a spot.
enum SpotColors {

    private static func rgb(_ hex: Int) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static let good: NSColor = DomainColors.dynamic("mcl.spot.good", light: rgb(0x1E88E5), dark: rgb(0x64B5F6))
    static let oneMult: NSColor = DomainColors.dynamic("mcl.spot.one", light: rgb(0xE53935), dark: rgb(0xFF7B73))
    static let multiMult: NSColor = DomainColors.dynamic("mcl.spot.multi", light: rgb(0x43A047), dark: rgb(0x81C784))
    static let dupe: NSColor = DomainColors.dynamic("mcl.spot.dupe", light: rgb(0x9E9E9E), dark: rgb(0xB0B0B0))

    static let planCw: NSColor = DomainColors.dynamic("mcl.plan.cw", light: rgb(0x5C6BC0), dark: rgb(0x9FA8DA))
    static let planDigi: NSColor = DomainColors.dynamic("mcl.plan.digi", light: rgb(0xFFB300), dark: rgb(0xFFCA28))
    static let planPhone: NSColor = DomainColors.dynamic("mcl.plan.phone", light: rgb(0x26A69A), dark: rgb(0x4DB6AC))
    static let note: NSColor = DomainColors.dynamic("mcl.bandNote", light: rgb(0x8E24AA), dark: rgb(0xCE93D8))

    /// N1MM colours of the Mults / Mults & Qs button (`AM:62-63`).
    static let buttonMults: NSColor = rgb(0xE53935)
    static let buttonAll: NSColor = rgb(0x1E88E5)

    /// `spotColor(key)`.
    static func color(_ key: SpotColorClassifier.SpotColorKey) -> NSColor {
        switch key {
        case .dupe: dupe
        case .good: good
        case .oneMult: oneMult
        case .multiMult: multiMult
        }
    }

    /// `planColor(category)`.
    static func plan(_ category: BandPlan.ModeCategory) -> NSColor {
        switch category {
        case .cw: planCw
        case .digi: planDigi
        case .phone: planPhone
        }
    }

    /// `planLabel(category)`: Czech, as the rest of the UI (verbatim).
    static func planLabel(_ category: BandPlan.ModeCategory) -> String {
        switch category {
        case .cw: "CW"
        case .digi: "DIGI"
        case .phone: "FONE"
        }
    }
}
