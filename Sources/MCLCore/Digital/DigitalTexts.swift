/// The texts of the Digital Interface and fldigi control (Czech keys of `lang_*.json`).
public enum DigitalTexts {
    public static let modemSetKey = "fldigi: mód %s"
    /// The Digital Interface's frequency caption: the transmitted frequency and the audio frequency (verbatim units).
    public static func frequencyCaption(transmitHz: Int64, carrierHz: Int?) -> String {
        guard transmitHz > 0 else { return "" }
        var text: String = FrequencyText.formatHz(transmitHz) + " kHz"
        if let carrierHz, carrierHz > 0 {
            text += " · " + String(carrierHz) + " Hz"
        }
        return text
    }
}
