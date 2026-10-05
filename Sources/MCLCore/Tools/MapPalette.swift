import Foundation

/// Colour schemes of the map background (Kotlin `MapStyle.kt`, `MS:`) as `0xAARRGGBB` values: light and dark ocean,
/// land and coast per scheme and the muted palette of the political colouring. The titles are Czech translation keys.
public struct MapScheme: Equatable, Sendable {
    public let key: String
    /// Czech title (translation key).
    public let title: String
    public let oceanLight: UInt32
    public let landLight: UInt32
    public let coastLight: UInt32
    public let oceanDark: UInt32
    public let landDark: UInt32
    public let coastDark: UInt32

    public func ocean(dark: Bool) -> UInt32 { dark ? oceanDark : oceanLight }
    public func land(dark: Bool) -> UInt32 { dark ? landDark : landLight }
    public func coast(dark: Bool) -> UInt32 { dark ? coastDark : coastLight }
}

public enum MapPalette {

    /// The schemes in the order of the settings choice; the first is the default.
    public static let schemes: [MapScheme] = [
        MapScheme(key: "green", title: "Zelená",
                  oceanLight: 0xFFB7_D4E3, landLight: 0xFFA9_B58F, coastLight: 0xFF80_8B65,
                  oceanDark: 0xFF17_303F, landDark: 0xFF47_563F, coastDark: 0xFF61_704F),
        MapScheme(key: "gray", title: "Šedá",
                  oceanLight: 0xFFDC_E4E9, landLight: 0xFFC6_CDD2, coastLight: 0xFF98_A2AA,
                  oceanDark: 0xFF21_2930, landDark: 0xFF3C_444B, coastDark: 0xFF59_636B),
        MapScheme(key: "sepia", title: "Sépiová",
                  oceanLight: 0xFFEA_DFC7, landLight: 0xFFD8_C29A, coastLight: 0xFFB2_9767,
                  oceanDark: 0xFF27_2219, landDark: 0xFF47_3C2A, coastDark: 0xFF69_5B40),
        MapScheme(key: "slate", title: "Modrošedá",
                  oceanLight: 0xFFC6_D7E6, landLight: 0xFFAE_B9C4, coastLight: 0xFF85_90A0,
                  oceanDark: 0xFF19_222E, landDark: 0xFF39_4452, coastDark: 0xFF58_6574),
    ]

    /// `mapSchemeByKey`: the scheme with the key, the first one for an unknown or missing key.
    public static func scheme(key: String?) -> MapScheme {
        schemes.first { $0.key == key } ?? schemes[0]
    }

    public static let politicalLight: [UInt32] = [
        0xFFCB_B78A, 0xFF9F_BE8E, 0xFF8F_B3B0, 0xFFC2_9A9A,
        0xFFA9_A6C6, 0xFFD0_B48C, 0xFF9D_B6C4, 0xFFBF_C08C,
        0xFFC7_A2B4, 0xFF8F_B79E, 0xFFBA_AF9C, 0xFFA8_C0B0,
        0xFFD1_AE9A, 0xFF9A_AECB,
    ]

    public static let politicalDark: [UInt32] = [
        0xFF5B_5238, 0xFF44_5539, 0xFF3C_5453, 0xFF57_3F3F,
        0xFF47_4563, 0xFF5E_4E38, 0xFF3F_4E5A, 0xFF56_5738,
        0xFF5A_4150, 0xFF3B_543F, 0xFF52_4B3E, 0xFF44_5851,
        0xFF5D_4B3E, 0xFF3E_4A5D,
    ]

    /// `politicalColor`: the palette cycles with the ring's group (DXCC entity ordinal; the modulus is non-negative).
    public static func politicalColor(group: Int, dark: Bool) -> UInt32 {
        let palette: [UInt32] = dark ? politicalDark : politicalLight
        let count: Int = palette.count
        return palette[((group % count) + count) % count]
    }
}
