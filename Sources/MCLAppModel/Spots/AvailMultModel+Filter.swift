import Foundation
import MCLCore

/// The „Pásma a režimy" sheet of the Available Multipliers window (`AvailFilterDialog.kt`, N1MM Bands/Modes): the
/// band groups, the traffic categories, which of them the active contest supports (the rest is greyed out) and what
/// ticking them does to the filter.
extension AvailMultModel {

    /// One group of the sheet (Kotlin `BandGroup`): `extra` are common bands without support, shown as disabled
    /// check boxes.
    public struct BandGroup: Equatable, Sendable {
        public let title: String
        public let bands: [Band]
        public let extra: [String]
    }

    /// Kotlin `BAND_GROUPS` (titles verbatim, not translated).
    public static let bandGroups: [BandGroup] = [
        BandGroup(title: "HF",
                  bands: [.m160, .m80, .m60, .m40, .m30, .m20, .m17, .m15, .m12, .m10], extra: []),
        BandGroup(title: "VHF", bands: [.m6, .m2], extra: ["222"]),
        BandGroup(title: "UHF", bands: [.cm70, .cm23], extra: ["902"]),
        // Post-port: the microwave bands 13 cm – 3 cm are real bands now (Kotlin listed them as disabled extras).
        BandGroup(title: "Mw", bands: [.cm13, .cm9, .cm6, .cm3], extra: ["24G"]),
    ]

    /// Kotlin `MODE_CHOICES`: the category and its label.
    public static let modeChoices: [(mode: String, label: String)] = [
        ("CW", "CW"), ("PHONE", "Phone"), ("DIGI", "Digi"),
    ]

    /// Kotlin `bandLabel`: the band in MHz as N1MM labels it.
    public static func bandLabel(_ band: Band) -> String {
        switch band {
        case .m160: "1.8"
        case .m80: "3.5"
        case .m60: "5"
        case .m40: "7"
        case .m30: "10"
        case .m20: "14"
        case .m17: "18"
        case .m15: "21"
        case .m12: "24"
        case .m10: "28"
        case .m6: "50"
        case .m2: "144"
        case .cm70: "430"
        case .cm23: "1296"
        case .cm13: "2.3G"
        case .cm9: "3.4G"
        case .cm6: "5.7G"
        case .cm3: "10G"
        }
    }

    /// The bands of the active definition (`def.bands()` through `Band.fromAdif`); none without a contest.
    public var supportedBands: Set<Band> {
        var out: Set<Band> = []
        for case let adif? in contest.definition?.bands ?? [] {
            if let band = Band.from(adif: adif) {
                out.insert(band)
            }
        }
        return out
    }

    /// The traffic categories of the active definition's modes (`DIGITAL` → DIGI, `SSB` → PHONE).
    public var supportedModes: Set<String> {
        var out: Set<String> = []
        for case let mode? in contest.definition?.modes ?? [] {
            out.insert(SpotModeCategory.of(mode))
        }
        return out
    }

    /// The group title button: all supported bands of the group ticked → they are unticked, otherwise ticked.
    public func toggleGroup(_ group: BandGroup) {
        let supported: Set<Band> = supportedBands
        let enabled: [Band] = group.bands.filter { supported.contains($0) }
        guard !enabled.isEmpty else { return }
        if enabled.allSatisfy({ bands.contains($0) }) {
            bands.subtract(enabled)
        } else {
            bands.formUnion(enabled)
        }
    }

    /// A band's check box.
    public func setBand(_ band: Band, ticked: Bool) {
        if ticked {
            bands.insert(band)
        } else {
            bands.remove(band)
        }
    }

    /// A mode category's check box.
    public func setMode(_ mode: String, ticked: Bool) {
        if ticked {
            modes.insert(mode)
        } else {
            modes.remove(mode)
        }
    }
}
