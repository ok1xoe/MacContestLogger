/// The QO-100 (Es'hail-2) geostationary amateur transponders. They have no band of their own in ADIF or Cabrillo:
/// a QSO is logged as `13cm` (uplink, 2400.05–2400.30 MHz) with the downlink on `3cm` (10489.55–10489.80 MHz narrow-band,
/// 10491–10499 MHz wide-band), so the band stays 13 cm / 3 cm and QO-100 is only a label shown to the operator
/// (the bandmap and the spot tooltip). A spot on the LNB intermediate frequency (739.x MHz) has no band at all.
public enum Qo100 {

    public static let name = "QO-100"

    /// Narrow-band transponder downlink, inclusive.
    static let narrowDownlink: ClosedRange<Int> = 10_489_500_000...10_490_000_000
    /// Wide-band transponder downlink, inclusive.
    static let wideDownlink: ClosedRange<Int> = 10_491_000_000...10_499_000_000
    /// The whole 13 cm amateur segment the uplink sits in (spots are normally at the downlink, so it counts
    /// only when the caller says the frequency is an uplink).
    static let uplink: ClosedRange<Int> = 2_400_000_000...2_450_000_000

    /// `"QO-100"` for a downlink frequency (and for an uplink one when `isUplink`), otherwise `nil`. Only a frequency
    /// that has a microwave band qualifies, so the Java-table switch of the parity gates switches the label off too.
    public static func label(freqHz: Int, isUplink: Bool = false) -> String? {
        guard Band.from(frequencyHz: freqHz)?.isMicrowave == true else { return nil }
        if narrowDownlink.contains(freqHz) || wideDownlink.contains(freqHz) { return name }
        if isUplink && uplink.contains(freqHz) { return name }
        return nil
    }
}
