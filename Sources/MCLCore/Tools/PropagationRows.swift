import Foundation

/// The logic of the propagation forecast window (Kotlin `PropagationWindow.kt`, `PW:47-104`): the SFI input, the path to
/// the target, the 24 × band table and its texts. Pure; `now` is injected.
public enum PropagationRows {

    /// The bands of the table, lowest first (the window draws them top-down from the highest).
    public static let bands: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

    /// Colours of the cells as `0xAARRGGBB`.
    public static let openColor: UInt32 = 0xFF43_A047
    public static let marginalColor: UInt32 = 0xFFFD_D835
    public static let closedColor: UInt32 = 0x3388_8888

    /// The SFI field filter (`filter(Char::isDigit).take(3)`).
    public static func filterSfi(_ text: String) -> String {
        SimulatorSession.digits(text, limit: 3)
    }

    /// The initial SFI text: the last WWV message's flux, otherwise `120`.
    public static func defaultSfiText(wwv: WwvMessage?) -> String {
        wwv.map { String($0.sfi) } ?? "120"
    }

    /// The flux used for the forecast: the text as a number, otherwise 120.
    public static func sfi(_ text: String) -> Double {
        JavaDouble.parseDouble(text) ?? 120.0
    }

    /// The colour of a band level.
    public static func color(_ level: PropagationModel.Level) -> UInt32 {
        switch level {
        case .open: return openColor
        case .marginal: return marginalColor
        case .closed: return closedColor
        }
    }

    /// One row of the table: a band and the level in each UTC hour.
    public struct Row: Equatable, Sendable {
        public let band: Band
        public let levels: [PropagationModel.Level]
    }

    /// The table for a path: the hour labels (`00`…`23`), the index of the current hour, the rows from the highest band.
    public struct Table: Equatable, Sendable {
        public let title: String
        public let hourLabels: [String]
        public let nowHour: Int
        public let rows: [Row]
    }

    /// What the window shows: a hint or the table.
    public enum View: Equatable, Sendable {
        case message(String)
        case table(Table)
    }

    /// The rows from the forecast for `from` → `to`: the highest band first, a missing level counts as closed.
    public static func rows(from: (lat: Double, lon: Double), to: (lat: Double, lon: Double), sfi: Double,
                            now: Date) -> [Row] {
        let ssn: Double = PropagationModel.ssnFromSfi(sfi)
        let forecast: [[Band: PropagationModel.Level]] = PropagationModel.forecast(
            from.lat, from.lon, to.lat, to.lon, from: now, ssn: ssn, bands: bands)
        return bands.reversed().map { band in
            Row(band: band, levels: forecast.map { $0[band] ?? .closed })
        }
    }

    /// The target text: the field, or the typed callsign when it is blank (`ifBlank`), then `trim()`.
    public static func call(target: String, typedCall: String) -> String {
        KotlinText.trim(KotlinText.isBlank(target) ? typedCall : target)
    }

    /// The whole view. `myGrid` is the station locator, `lookup` the DXCC resolver.
    public static func view(target: String, typedCall: String, sfiText: String, myGrid: String,
                            lookup: (any DxccLookup)?, now: Date, translate: Translator) -> View {
        let call: String = Self.call(target: target, typedCall: typedCall)
        let mine = Maidenhead.centerLatLon(myGrid)
        let entity: DxccEntity? = lookup?.resolve(call)
        guard let mine, let entity, entity.hasLatLon else {
            if mine == nil {
                return .message(translate.translate("Doplň lokátor stanice (Nastavení → Stanice)."))
            }
            return .message(translate.translate("Zadej volačku nebo prefix země."))
        }
        let flux: Double = sfi(sfiText)
        let ssn: Double = PropagationModel.ssnFromSfi(flux)
        let table: [Row] = rows(from: mine, to: (entity.lat, entity.lon), sfi: flux, now: now)
        let title: String = translate.translate("%s · SSN %s · aktuální hodina zvýrazněná",
                                                [.string(entity.name), .int(Int(JavaMath.d2i(ssn)))])
        let hours: [String] = (0..<24).map { ToolsFormat.two(Int64($0)) }
        let seconds: Int64 = JavaMath.d2l(now.timeIntervalSince1970.rounded(.down))
        let hour: Int = Int((seconds - JavaMath.floorDiv(seconds, 86_400) * 86_400) / 3_600)
        return .table(Table(title: title, hourLabels: hours, nowHour: hour, rows: table))
    }

    /// Footnote under the table.
    public static func footnote(_ translator: Translator) -> String {
        translator.translate(
            "Zjednodušený model (foF2 ze SFI a výšky Slunce v řídicích bodech trasy, útlum vrstvy D) — orientační, ne VOACAP.")
    }
}
