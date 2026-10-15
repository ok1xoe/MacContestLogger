import Foundation

/// The QTC setup of the WAE DX Contest (N1MM Entry window → Config → WAE: „Ctrl-Z sends QTC? automatically",
/// „Max QTC Number for callsign colors in Band Map" and the „QTC Window Setup Area" with its CW, SSB and RTTY
/// tabs). Kept as a string map (`AppConfig.qtcSetup`): a missing key is the default, a value equal to the default is
/// not stored.
public struct QtcSetup: Equatable, Sendable {

    /// The settings. Messages may use the F-key macros (`*`, `!`, `{MYCALL}`, `{ENTER}`…) plus `{QTC}` (the series
    /// header, `26/10`) and `$` (the number of the QTC asked again).
    public enum Key: String, CaseIterable, Sendable {
        /// Ctrl+Z in Run, CW, as a European station sends the ask message first (N1MM option, off by default).
        case ctrlZSendsAsk
        /// Return in the series header field sends the QRV message (N1MM „when moving from QTC header send QRV").
        case cwQrvOnHeader
        /// The number of QTCs per station for the band map colours (N1MM „Max QTC Number for callsign colors").
        case colorMax
        /// N1MM „Default Number of QTCs to Send": the most QTCs one sent series holds.
        case sendCount
        case cwAsk, cwQrv, cwConfirm, cwAgain, cwTu
        case ssbQrv, ssbConfirm, ssbAgain, ssbTu
        case rttyQrv, rttyAllAgain, rttyAgain, rttyReceivedSave
        case rttyAskQrv, rttyHeading, rttyEnding, rttySentSave, rttySpacing
    }

    /// The stored values (non-default ones).
    public private(set) var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        var kept: [String: String] = [:]
        for (raw, value) in values {
            if let key = Key(rawValue: raw), value != Self.defaultValue(key) {
                kept[raw] = value
            }
        }
        self.values = kept
    }

    /// The default of a key (N1MM-like messages; an empty TU means the normal TU key of ESM, F3).
    public static func defaultValue(_ key: Key) -> String {
        switch key {
        case .ctrlZSendsAsk, .cwQrvOnHeader: "false"
        case .colorMax, .sendCount: "10"
        case .cwAsk: "QTC?"
        case .cwQrv: "QRV"
        case .cwConfirm: "R"
        case .cwAgain: "AGN $"
        case .cwTu, .ssbTu: ""
        case .ssbQrv: "qtc-qrv.wav"
        case .ssbConfirm: "qtc-confirm.wav"
        case .ssbAgain: "qtc-again.wav"
        case .rttyQrv: "QRV QRV"
        case .rttyAllAgain: "ALL AGN ALL AGN"
        case .rttyAgain: "QTC $ AGN QTC $ AGN"
        case .rttyReceivedSave: "QSL ALL QTC TU *"
        case .rttyAskQrv: "! QTC {QTC} QRV?"
        case .rttyHeading: "QTC {QTC} QTC {QTC}"
        case .rttyEnding: "END QTC"
        case .rttySentSave: "TU QTC QSL"
        case .rttySpacing: "{ENTER}"
        }
    }

    public func text(_ key: Key) -> String {
        values[key.rawValue] ?? Self.defaultValue(key)
    }

    public func flag(_ key: Key) -> Bool {
        text(key) == "true"
    }

    /// A count setting: 1…10, the default for anything else.
    public func number(_ key: Key) -> Int {
        let parsed: Int? = Int(KotlinStrings.trim(text(key)))
        if let parsed, (1...10).contains(parsed) {
            return parsed
        }
        return Int(Self.defaultValue(key)) ?? 10
    }

    public mutating func set(_ key: Key, _ value: String) {
        if value == Self.defaultValue(key) {
            values.removeValue(forKey: key.rawValue)
        } else {
            values[key.rawValue] = value
        }
    }

    public mutating func set(_ key: Key, flag: Bool) {
        set(key, flag ? "true" : "false")
    }
}

/// The messages of the QTC window (N1MM's QRV, Cfm, Agn, TU and the RTTY RQTC / SQTC messages) by the entry window's
/// mode, with `{QTC}` and `$` resolved. Pure.
public enum QtcMessages {

    /// What a QTC button sends.
    public enum Kind: Equatable, Sendable {
        /// The receiving station asks for QTCs (CW `QTC?`).
        case ask
        /// Ready to copy (QRV / RX Ready).
        case ready
        /// The QTC was copied (Cfm, CW and SSB).
        case confirm
        /// The QTC with this number again (Agn, `$`).
        case again(Int)
        /// The whole series again (RTTY All Agn).
        case allAgain
        /// The series is complete: TU on exit (CW / SSB), Save QTC (RTTY, receiving).
        case receivedDone
        /// The sending station asks whether the other is ready (RTTY RU QRV).
        case askReady
        /// The sending station is done: TU on exit (CW / SSB), Save QTC (RTTY, sending).
        case sentDone
    }

    /// The mode family of the entry window.
    public enum Family: Equatable, Sendable {
        case cw, phone, digital

        public init(_ mode: Mode) {
            if mode == .cw {
                self = .cw
            } else if mode.isDigital {
                self = .digital
            } else {
                self = .phone
            }
        }
    }

    /// What goes out.
    public enum Outgoing: Equatable, Sendable {
        /// A message sent like an F-key message in CW / digital, or played (wav names, `[text]`) in phone.
        case message(String)
        /// The normal TU key of ESM (F3): the TU message is not set.
        case tuKey
    }

    /// The buttons of the window for its side and mode, in display order.
    public static func kinds(sending: Bool, family: Family) -> [Kind] {
        switch (sending, family) {
        case (false, .cw): [.ask, .ready, .confirm, .again(0), .receivedDone]
        case (false, .phone): [.ready, .confirm, .again(0), .receivedDone]
        case (false, .digital): [.ready, .allAgain, .again(0), .receivedDone]
        case (true, .digital): [.askReady, .sentDone]
        case (true, _): [.sentDone]
        }
    }

    /// The outgoing message of a kind, `nil` = nothing set for this mode (a blank message sends nothing).
    public static func outgoing(_ kind: Kind, family: Family, setup: QtcSetup, header: String) -> Outgoing? {
        let template: String
        switch (kind, family) {
        case (.ask, .cw): template = setup.text(.cwAsk)
        case (.ready, .cw): template = setup.text(.cwQrv)
        case (.ready, .phone): template = setup.text(.ssbQrv)
        case (.ready, .digital): template = setup.text(.rttyQrv)
        case (.confirm, .cw): template = setup.text(.cwConfirm)
        case (.confirm, .phone): template = setup.text(.ssbConfirm)
        case (.again, .cw): template = setup.text(.cwAgain)
        case (.again, .phone): template = setup.text(.ssbAgain)
        case (.again, .digital): template = setup.text(.rttyAgain)
        case (.allAgain, .digital): template = setup.text(.rttyAllAgain)
        case (.receivedDone, .digital): template = setup.text(.rttyReceivedSave)
        case (.sentDone, .digital): template = setup.text(.rttySentSave)
        case (.askReady, .digital): template = setup.text(.rttyAskQrv)
        case (.receivedDone, .cw), (.sentDone, .cw):
            template = setup.text(.cwTu)
            if KotlinStrings.isBlank(template) { return .tuKey }
        case (.receivedDone, .phone), (.sentDone, .phone):
            template = setup.text(.ssbTu)
            if KotlinStrings.isBlank(template) { return .tuKey }
        default:
            return nil
        }
        if KotlinStrings.isBlank(template) {
            return nil
        }
        var number: Int = 0
        if case .again(let n) = kind {
            number = n
        }
        return .message(expand(template, header: header, number: number))
    }

    /// `{QTC}` (ASCII case-insensitive) → the series header, `$` → the QTC number (`0` = none: removed).
    public static func expand(_ template: String, header: String, number: Int) -> String {
        var out: String = ""
        let units: [UInt16] = Array(template.utf16)
        let macro: [UInt16] = Array("{QTC}".utf16)
        var index = 0
        while index < units.count {
            if units[index] == 0x7B, index + macro.count <= units.count,
               JavaText.toUpperCase(String(decoding: units[index..<(index + macro.count)], as: UTF16.self)) == "{QTC}" {
                out += header
                index += macro.count
                continue
            }
            if units[index] == 0x24 {
                out += number > 0 ? String(number) : ""
                index += 1
                continue
            }
            out += String(decoding: [units[index]], as: UTF16.self)
            index += 1
        }
        return out
    }

    /// The header of a series: `n/count`.
    public static func header(group: Int, count: Int) -> String {
        "\(group)/\(count)"
    }

    /// The header the receiving station typed: `12/7` stays, `12` alone is `12/10` (N1MM assumes ten), blank stays
    /// blank.
    public static func receivedHeader(_ typed: String, defaultCount: Int = 10) -> String {
        let trimmed: String = KotlinStrings.trim(typed)
        if let parsed = QtcPlanner.parseGroup(trimmed) {
            return header(group: parsed.groupNr, count: parsed.count)
        }
        if let number = Int(trimmed), number > 0 {
            return header(group: number, count: defaultCount)
        }
        return trimmed
    }

    /// The RTTY series to send (N1MM SQTC „Send All"): the heading, every line, the ending, joined by the spacing
    /// (normally `{ENTER}`).
    public static func digitalSeries(header: String, lines: [QtcPlanner.Line], setup: QtcSetup) -> String {
        let spacing: String = setup.text(.rttySpacing)
        var parts: [String] = []
        let heading: String = expand(setup.text(.rttyHeading), header: header, number: 0)
        if !KotlinStrings.isBlank(heading) {
            parts.append(heading)
        }
        for line in lines {
            parts.append("\(line.time) \(line.call) \(line.serial)")
        }
        let ending: String = expand(setup.text(.rttyEnding), header: header, number: 0)
        if !KotlinStrings.isBlank(ending) {
            parts.append(ending)
        }
        return parts.joined(separator: spacing)
    }
}

/// Who may exchange QTCs with whom (WAE), for Ctrl+Z and the band map colours. Pure.
public enum QtcRules {

    /// The side of the station in the QTC traffic.
    public enum Role: Equatable, Sendable {
        /// A European station receives QTCs.
        case receive
        /// A station outside Europe sends them.
        case send
    }

    /// The role of my station: Europe receives, the rest of the world sends; an unknown continent receives.
    public static func role(ownContinent: String?) -> Role {
        guard let ownContinent, !ownContinent.isEmpty else { return .receive }
        return JavaText.equals(ownContinent, "EU") ? .receive : .send
    }

    /// QTCs can pass between two stations: in WAE CW / SSB only between Europe and the rest of the world, in WAE RTTY
    /// (`anyContinent`) between any two stations on different continents. An unknown continent never qualifies.
    public static func canExchange(ownContinent: String?, otherContinent: String?, anyContinent: Bool) -> Bool {
        guard let own = ownContinent, let other = otherContinent, !own.isEmpty, !other.isEmpty else { return false }
        if anyContinent {
            return !JavaText.equals(own, other)
        }
        return JavaText.equals(own, "EU") != JavaText.equals(other, "EU")
    }

    /// The number of QTCs exchanged with each partner (upper case).
    public static func counts(_ qtcs: [QtcRecord]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for q in qtcs {
            counts[JavaText.toUpperCase(KotlinText.trim(q.partnerCall)), default: 0] += 1
        }
        return counts
    }

    /// N1MM's band map colours in WAE: red a new multiplier, green a new station with QTCs left, blue a new station
    /// without, the QTC colour (black) a dupe with QTCs left, grey a dupe without.
    public static func color(dupe: Bool, newMultCount: Int, qtcLeft: Bool) -> SpotColorClassifier.SpotColorKey {
        if dupe {
            return qtcLeft ? .qtc : .dupe
        }
        if newMultCount >= 1 {
            return .oneMult
        }
        return qtcLeft ? .multiMult : .good
    }
}
