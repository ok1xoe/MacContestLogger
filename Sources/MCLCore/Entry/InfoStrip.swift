import Foundation

/// What the info strip next to Run/S&P shows (`EP:1271-1307`): everything that influences dupes and the exchange.
/// A `nil` input = the source that fills it is not there (REC, antenna, clock, band note, RIT, tuning, SNS,
/// sked) and the item is left out.
public struct InfoStripInput: Equatable, Sendable {
    /// The active TOUR (`contest.tour`) and the moment for its session end.
    public var tour: Tour?
    public var now: Date
    public var countyLine: [String]
    /// `config.station.roverQth` (untrimmed, as Kotlin shows it).
    public var roverQth: String
    public var usesRoverQth: Bool
    public var bonusStationCount: Int
    public var cqRepeat: Bool
    public var repeatSeconds: Double
    public var recording: Bool?
    public var antennaName: String?
    public var clockOffsetMs: Int64?
    public var bandNote: String?
    public var ritHz: Int?
    public var tuning: Bool?
    public var postContest: Bool
    /// Serial-number server waiting for a number (`isSerialServer && stationNet != null && reservedSerial == null`).
    public var snsWaiting: Bool?
    public var stackedCalls: [String]
    /// The next sked within 10 minutes: its formatted time and call.
    public var sked: InfoStripSked?

    public init(tour: Tour? = nil, now: Date = Date(), countyLine: [String] = [], roverQth: String = "",
                usesRoverQth: Bool = false, bonusStationCount: Int = 0, cqRepeat: Bool = false,
                repeatSeconds: Double = 0, recording: Bool? = nil, antennaName: String? = nil,
                clockOffsetMs: Int64? = nil, bandNote: String? = nil, ritHz: Int? = nil, tuning: Bool? = nil,
                postContest: Bool = false, snsWaiting: Bool? = nil, stackedCalls: [String] = [],
                sked: InfoStripSked? = nil) {
        self.tour = tour
        self.now = now
        self.countyLine = countyLine
        self.roverQth = roverQth
        self.usesRoverQth = usesRoverQth
        self.bonusStationCount = bonusStationCount
        self.cqRepeat = cqRepeat
        self.repeatSeconds = repeatSeconds
        self.recording = recording
        self.antennaName = antennaName
        self.clockOffsetMs = clockOffsetMs
        self.bandNote = bandNote
        self.ritHz = ritHz
        self.tuning = tuning
        self.postContest = postContest
        self.snsWaiting = snsWaiting
        self.stackedCalls = stackedCalls
        self.sked = sked
    }
}

/// The next sked shown in the strip: its formatted time and call.
public struct InfoStripSked: Equatable, Sendable {
    public var time: String
    public var call: String

    public init(time: String, call: String) {
        self.time = time
        self.call = call
    }
}

public enum InfoStrip {

    /// The items in Kotlin order: TOUR, county line (else rover), bonus, RPT, REC, ANT, HODINY, band note, RIT,
    /// LADĚNÍ, DODATEČNÉ ZADÁNÍ, SNS, ZÁSOBNÍK, SKED. Translatable ones are keys; the rest verbatim.
    public static func extras(_ input: InfoStripInput) -> [ContestMessage] {
        var items: [ContestMessage] = []
        if let tour = input.tour, let end = try? tour.sessionEnd(at: input.now) {
            items.append(.verbatim("TOUR " + tour.format() + " do " + EntryTexts.hhmmZ(end)))
        }
        if !input.countyLine.isEmpty {
            items.append(.verbatim("County line " + input.countyLine.joined(separator: "/")))
        } else if !KotlinStrings.isBlank(input.roverQth) && input.usesRoverQth {
            items.append(.verbatim("Rover " + input.roverQth))
        }
        if input.bonusStationCount > 0 {
            items.append(.verbatim("Bonus \(input.bonusStationCount)"))
        }
        if input.cqRepeat {
            items.append(.verbatim("RPT " + EntryTexts.repeatLabel(input.repeatSeconds)))
        }
        items.append(contentsOf: hardwareItems(input))
        if input.postContest {
            items.append(ContestMessage("DODATEČNÉ ZADÁNÍ"))
        }
        if input.snsWaiting == true {
            items.append(ContestMessage("SNS: čekám na číslo"))
        }
        if !input.stackedCalls.isEmpty {
            items.append(ContestMessage("ZÁSOBNÍK %s (Ctrl+Alt+K)", .string(input.stackedCalls.joined(separator: " "))))
        }
        if let sked = input.sked {
            items.append(.verbatim("SKED " + sked.time + " " + sked.call))
        }
        return items
    }

    /// REC, ANT, HODINY, band note, RIT, LADĚNÍ.
    private static func hardwareItems(_ input: InfoStripInput) -> [ContestMessage] {
        var items: [ContestMessage] = []
        if input.recording == true {
            items.append(.verbatim("● REC"))
        }
        if let antenna = input.antennaName {
            items.append(.verbatim("ANT " + antenna))
        }
        if let offset = input.clockOffsetMs, offset > 1_000 || offset < -1_000 {
            items.append(.verbatim("HODINY " + signedTenths(Double(offset) / 1000.0) + " s"))
        }
        if let note = input.bandNote {
            items.append(.verbatim("📝 " + note))
        }
        if let rit = input.ritHz, rit != 0 {
            items.append(.verbatim("RIT " + (rit > 0 ? "+" : "") + String(rit)))
        }
        if input.tuning == true {
            items.append(ContestMessage("LADĚNÍ"))
        }
        return items
    }

    /// The text: `" " + extras.joinToString(" · ")`, or `""` without items.
    public static func text(_ items: [ContestMessage], _ translator: Translator, decimalSeparator: String = ".") -> String {
        if items.isEmpty {
            return ""
        }
        return " " + items.map { $0.text(translator, decimalSeparator: decimalSeparator) }.joined(separator: " · ")
    }

    /// Java `%+.1f` (`Locale.US`): the sign always (the value is never near zero here, |offset| > 1 s).
    static func signedTenths(_ value: Double) -> String {
        let fixed: String = JavaFormat.fixed(value, precision: 1)
        return fixed.hasPrefix("-") ? fixed : "+" + fixed
    }
}
