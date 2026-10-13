/// The frequency a sound-card digital mode really transmits on (N1MM „AutoTRXUpdate"): with the rig in a sideband
/// mode the dial shows the suppressed carrier and the signal sits the modem's audio frequency above it (USB) or below
/// it (LSB). In FSK RTTY (hamlib `RTTY`/`RTTYR`), CW and the other modes the dial already is the frequency.
public enum DigitalFrequency {

    /// `+1` for an upper sideband mode, `-1` for a lower one, `nil` when the dial is the transmitted frequency.
    public static func sideband(rawMode: String) -> Int? {
        switch JavaText.toUpperCase(JavaText.trim(rawMode)) {
        case "USB", "PKTUSB", "USB-D", "DATA-U", "DIGU", "PKT-U", "USBD1", "USBD2", "USBD3": 1
        case "LSB", "PKTLSB", "LSB-D", "DATA-L", "DIGL", "PKT-L", "LSBD1", "LSBD2", "LSBD3": -1
        default: nil
        }
    }

    /// The dial ± the audio frequency in a sideband mode; the dial otherwise (or without a known audio frequency).
    public static func transmitHz(dialHz: Int64, rawMode: String, carrierHz: Int?) -> Int64 {
        guard dialHz > 0, let carrierHz, carrierHz > 0, let side = sideband(rawMode: rawMode) else { return dialHz }
        return dialHz + Int64(side * carrierHz)
    }

    /// N1MM Shift Frequency Compensation: the offset for FSK RTTY (rig mode RTTY/RTTYR), 0 otherwise.
    public static func shiftCompensation(rawMode: String, enabled: Bool, offsetHz: Int) -> Int64 {
        guard enabled else { return 0 }
        let mode: String = JavaText.toUpperCase(JavaText.trim(rawMode))
        return mode == "RTTY" || mode == "RTTYR" ? Int64(offsetHz) : 0
    }

    /// The side the received audio lies on for Align: USB-like `+1`, LSB-like `-1` (FSK RTTY demodulates as LSB,
    /// RTTYR as USB), `nil` for other modes.
    public static func alignSide(rawMode: String) -> Int? {
        switch JavaText.toUpperCase(JavaText.trim(rawMode)) {
        case "RTTY": -1
        case "RTTYR": 1
        default: sideband(rawMode: rawMode)
        }
    }

    /// N1MM Align: the dial that puts a signal now at audio `carrierHz` onto `targetHz` (the filter's centre);
    /// `nil` when nothing moves or the mode has no audio side.
    public static func alignedDialHz(dialHz: Int64, rawMode: String, carrierHz: Int, targetHz: Int) -> Int64? {
        guard dialHz > 0, carrierHz > 0, carrierHz != targetHz, let side = alignSide(rawMode: rawMode) else {
            return nil
        }
        return dialHz + Int64(side * (carrierHz - targetHz))
    }

    /// `{RDIGFQ}` / `{LDIGFQ}`: kHz with one decimal (US decimal point), `""` for an unknown frequency.
    public static func macroText(_ hz: Int64) -> String {
        guard hz > 0 else { return "" }
        let tenths: Int64 = (hz + 50) / 100
        return String(tenths / 10) + "." + String(tenths % 10)
    }
}
