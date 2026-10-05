import Foundation

extension SpotAnalyzer {

    /// Kotlin `spotTooltip` (`ContestController.kt:700-714`): the description of a spot in the multiplier grid —
    /// call and frequency (`%.1f` kHz, US), mode with category and whether it is evaluated, the grid with its field,
    /// the spotter and a non-blank comment.
    ///
    /// The texts translated in Kotlin (`tr`) are translated by `translator`: `"\nMód: "`, `"neurčitelný"`,
    /// `", ignorováno"`, `"\nKomentář: "`; the others stay as Kotlin writes them (`", vyhodnocuje se"`,
    /// `"\nGrid: "`, `" → pole "`, `"\nSpotter: "`).
    public func spotTooltip(_ spot: DxSpot, translator: Translator = .source) -> String {
        let call: String = spot.dxCall
        let mode: String = resolveSpotMode(call: call, freqHz: spot.freqHz, comment: spot.comment)
        let category: String? = spotModeCategory(spot)
        let grid: String? = gridForSpot(spot)
        let kHz: String = JavaFormat.format("%.1f", .double(Double(spot.freqHz) / 1000.0))
        var out: String = "\(call)   \(kHz) kHz"
        out += translator.translate("\nMód: ") + mode
        out += " (" + (category ?? translator.translate("neurčitelný"))
        out += isColorRelevant(spot) ? ", vyhodnocuje se" : translator.translate(", ignorováno")
        out += ")"
        if let grid {
            let field: String = JavaText.toUpperCase(JavaChar.string(Array(grid.utf16.prefix(2))))
            out += "\nGrid: \(grid) → pole \(field)"
        }
        out += "\nSpotter: " + spot.spotter
        // Post-port: a spot on the QO-100 transponder says so (the band stays 3 cm).
        if let satellite = Qo100.label(freqHz: spot.freqHz) {
            out += translator.translate("\nSatelit: ") + satellite
        }
        if !KotlinText.isBlank(spot.comment) {
            out += translator.translate("\nKomentář: ") + spot.comment
        }
        return out
    }
}
