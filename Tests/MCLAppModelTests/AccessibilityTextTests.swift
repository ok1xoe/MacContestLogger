import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spoken texts of the icon-only controls and the drawn islands (`AccessibilityText`): the TRX LED, the score bar,
/// the band map's spots, the world map, the charts, the compass and the glyph marks of the tables. Pure functions of
/// plain values — no window is needed.
@Suite struct AccessibilityTextTests {

    private static let source: Translator = .source

    private static let english = Translator(language: "en", translations: LanguageCatalog.Translations([
        JavaStringKey("Připojeno"): "Connected",
        JavaStringKey("Odpojeno"): "Disconnected",
        JavaStringKey("Připojuji…"): "Connecting…",
        JavaStringKey("Připojuji (%s)…"): "Connecting (%s)…",
        JavaStringKey("duplicitní"): "dupe",
        JavaStringKey("spotů: %d"): "spots: %d",
    ]))

    // MARK: - the LED

    @Test func theLedStatesFollowTheSnapshotFlags() {
        #expect(AccessibilityText.rigLedState(connected: true, connecting: false) == .connected)
        #expect(AccessibilityText.rigLedState(connected: false, connecting: false) == .disconnected)
        #expect(AccessibilityText.rigLedState(connected: false, connecting: true) == .connecting)
    }

    @Test func theLedValuesAreTranslated() {
        let tr: Translator = Self.english
        #expect(AccessibilityText.rigLedValue(.connecting, translator: tr) == "Connecting…")
        #expect(AccessibilityText.rigLedValue(.connected, translator: tr) == "Connected")
        #expect(AccessibilityText.rigLedValue(.disconnected, translator: tr) == "Disconnected")
    }

    @Test func theLedValuesAreTheCzechKeysWithoutALanguage() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.rigLedValue(.connected, translator: tr) == "Připojeno")
        #expect(AccessibilityText.rigLedValue(.disconnected, translator: tr) == "Odpojeno")
        #expect(AccessibilityText.rigLedValue(.connecting, translator: tr) == "Připojuji…")
    }

    // MARK: - the score bar

    @Test func theScoreBarSaysEveryFigure() {
        let value: String = AccessibilityText.scoreBarValue(qso: "12", points: "34", mult: "5", total: "170",
                                                            translator: Self.source)
        #expect(value == "QSO 12, Body 34, násobiče 5, Skóre 170")
    }

    // MARK: - the band map

    @Test func aSpotSaysCallKilohertzAndState() {
        let tr: Translator = Self.english
        #expect(AccessibilityText.bandmapSpot(call: "OK1ABC", freqHz: 14_025_300, color: .good, translator: tr)
            == "OK1ABC, 14025.3 kHz")
        #expect(AccessibilityText.bandmapSpot(call: "OK1ABC", freqHz: 14_025_300, color: .dupe, translator: tr)
            == "OK1ABC, 14025.3 kHz, dupe")
        #expect(AccessibilityText.bandmapSpot(call: "DL1X", freqHz: 7_010_000, color: .oneMult,
                                              translator: Self.source) == "DL1X, 7010.0 kHz, nový násobič")
        #expect(AccessibilityText.bandmapSpot(call: "DL1X", freqHz: 7_010_000, color: .multiMult,
                                              translator: Self.source) == "DL1X, 7010.0 kHz, více nových násobičů")
    }

    @Test func theBandmapValueHasBandFrequencyAndCount() {
        #expect(AccessibilityText.bandmapValue(band: "20m", tunedHz: 14_074_000, spots: 7, translator: Self.english)
            == "20m, 14074.0 kHz, spots: 7")
    }

    // MARK: - the world map

    @Test func theWorldMapSummarisesWhatItShows() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.worldMapValue(dxccMode: true, fields: 3, dots: 31, translator: tr) == "zemí: 31")
        #expect(AccessibilityText.worldMapValue(dxccMode: false, fields: 3, dots: 31, translator: tr)
            == "čtverců: 3")
    }

    // MARK: - the charts

    @Test func theHourChartGivesTheRangeAndTheTotal() {
        let chart = HourlyChart(title: "QSO po hodinách (max 30/h)", hours: ["10-04 10Z", "10-04 11Z", "10-04 12Z"],
                                values: [10, 30, 5], scale: 30)
        #expect(AccessibilityText.hourChartValue(chart, translator: Self.source)
            == "QSO po hodinách (max 30/h), hodin: 3, od 10-04 10Z do 10-04 12Z, celkem QSO: 45")
        let empty = HourlyChart(title: "QSO po hodinách", hours: [], values: [], scale: 1)
        #expect(AccessibilityText.hourChartValue(empty, translator: Self.source) == "QSO po hodinách, žádná data")
    }

    @Test func theRateBarsCarryTheirGoalStatus() {
        let rates = NearTermRates(
            title: "QSO/hod — cíl 100",
            bars: [RateBar(label: "10", value: 120, status: .met), RateBar(label: "100", value: 80, status: .close),
                   RateBar(label: "60m", value: 20, status: .missed), RateBar(label: "17m", value: 9, status: .none)],
            peak: 120, goalLine: 100)
        #expect(AccessibilityText.rateBarsValue(rates, translator: Self.source)
            == "QSO/hod — cíl 100, 10: 120 (cíl splněn), 100: 80 (blízko cíle), 60m: 20 (pod cílem), 17m: 9")
    }

    @Test func theTrendSaysTheLastPoint() throws {
        let start: JavaInstant = try #require(JavaInstant.ofEpochSecond(1_791_000_000))
        let trend = TrendView(
            title: "Průběh — 60min",
            points: [TrendPoint(start: start, clock: "10:00", value: 40, status: .met),
                     TrendPoint(start: start, clock: "10:15", value: 22, status: .missed)],
            scale: 40, gridLabels: [0, 10, 20, 30, 40], goal: 30, goalLine: 30)
        #expect(AccessibilityText.trendValue(trend, translator: Self.source)
            == "Průběh — 60min, bodů: 2, poslední 10:15: 22 (pod cílem)")
        let none = TrendView(title: "Průběh — 60min", points: [], scale: 1, gridLabels: [0, 0, 0, 0, 0], goal: nil,
                             goalLine: nil)
        #expect(AccessibilityText.trendValue(none, translator: Self.source) == "Průběh — 60min, žádná data")
    }

    @Test func theTimerColourBecomesAWord() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.timerState(.none, translator: tr) == nil)
        #expect(AccessibilityText.timerState(.ok, translator: tr) == "v pořádku")
        #expect(AccessibilityText.timerState(.warn, translator: tr) == "pozor")
        #expect(AccessibilityText.timerState(.over, translator: tr) == "po termínu")
    }

    // MARK: - the compass

    @Test func theCompassSaysRotatorAndTarget() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.compassValue(azimuth: 123.4, target: 45, translator: tr) == "rotátor 123°, cíl 45°")
        #expect(AccessibilityText.compassValue(azimuth: nil, target: nil, translator: tr) == "rotátor neznámý")
    }

    // MARK: - glyph marks

    @Test func theLogMarksAreSpokenAsWords() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.logWarning(nil, translator: tr) == "")
        #expect(AccessibilityText.logWarning("chybí výměna", translator: tr) == "Varování: chybí výměna")
        #expect(AccessibilityText.logXQso("", translator: tr) == "bez X-QSO")
        #expect(AccessibilityText.logXQso("X", translator: tr) == "X-QSO X")
        #expect(AccessibilityText.logPoints("3", dupe: true, translator: Self.english) == "3, dupe")
        #expect(AccessibilityText.logPoints("3", dupe: false, translator: Self.english) == "3")
        #expect(AccessibilityText.multMark(true, translator: tr) == "násobič")
        #expect(AccessibilityText.multMark(false, translator: tr) == "")
    }

    @Test func theSortArrowIsSpokenInTheHeader() {
        let tr: Translator = Self.source
        #expect(AccessibilityText.logHeader(title: "Volačka", sorted: nil, translator: tr) == "Volačka")
        #expect(AccessibilityText.logHeader(title: "Volačka", sorted: true, translator: tr)
            == "Volačka, řazeno vzestupně")
        #expect(AccessibilityText.logHeader(title: "Volačka", sorted: false, translator: tr)
            == "Volačka, řazeno sestupně")
    }

    @Test func theInfoStripNoteGlyphIsSpoken() {
        #expect(AccessibilityText.infoStrip("TOUR 3 | 📝 Konec pásma", translator: Self.source)
            == "TOUR 3 | Poznámka k pásmu: Konec pásma")
        #expect(AccessibilityText.infoStrip("SKED OK1X 14:30", translator: Self.source) == "SKED OK1X 14:30")
    }

    @Test func aDupesheetHitIsSaid() {
        #expect(AccessibilityText.dupesheetCall("OK1ABC", hit: true, translator: Self.source)
            == "OK1ABC, shoduje se s psaným")
        #expect(AccessibilityText.dupesheetCall("OK1ABC", hit: false, translator: Self.source) == "OK1ABC")
    }

    // MARK: - the shipped languages

    /// Every text that `AccessibilityText` speaks is in both shipped language files (the audit script checks the
    /// literals; this checks the files through the real loader).
    @Test func theShippedLanguagesTranslateTheSpokenTexts() throws {
        let keys: [String] = ["Připojeno", "Odpojeno", "Připojuji…", "duplicitní", "nový násobič", "žádná data",
                              "cíl splněn", "řazeno vzestupně", "Varování", "Velikost písma", "Kompas rotátoru"]
        for code in ["en", "de"] {
            let bytes: [UInt8] = try #require(LanguageCatalog.bundledBytes(code))
            let map = LanguageCatalog.Translations(try #require(LanguageJsonReader.read(bytes)))
            for key in keys {
                #expect(map[key] != nil, "\(code) misses \(key)")
            }
        }
    }
}
