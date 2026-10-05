/// Best-effort mapping of ADIF fields received from WSJT-X to the `receivedRaw` exchange map according to the configuration of
/// the active contest — port of `wsjtx/WsjtxExchangeMapper.java` (v1.1.1). What cannot be translated is left out —
/// the field stays incomplete and the user fills it in in the Log window.
///
/// The result is a Java `LinkedHashMap` (`JavaLinkedMap`: order of the definition fields, a `null` id is a key).
/// Emptiness is Java `isBlank()`, trimming `trim()`, tokens `trim().split("\\s+")` (ASCII whitespace).
///
/// Leniency compared to Java (like `ExchangeGrab`): a field with `type == nil`
/// (Java `NullPointerException` from `switch`) is skipped — it accepts nothing and consumes no token.
/// The definition validator reports such a field as an error, it is unreachable from the app.
public enum WsjtxExchangeMapper {

    public typealias ExchangeField = ContestDefinition.ExchangeField
    public typealias FieldType = ContestDefinition.FieldType

    private static let whitespace: JavaRegex = {
        do {
            return try JavaRegex("\\s+")
        } catch {
            preconditionFailure("pevný vzor musí jít zkompilovat: \(error)")
        }
    }()

    public static func toReceivedRaw(_ fields: [ExchangeField], _ adif: [String: String]) -> JavaLinkedMap<String> {
        var raw = JavaLinkedMap<String>()
        let srxTokens: [String] = tokens(firstNonBlank(adif["srx_string"], adif["srx"]))
        var tokenIdx: Int = reportTokensInSrx(fields, srxTokens, adif["rst_rcvd"])
        for f in fields {
            guard let type = f.type else { continue }
            let value: String?
            switch type {
            case .RST, .RS:
                value = adif["rst_rcvd"]
            case .LOCATOR:
                value = firstNonBlank(adif["gridsquare"], adif["srx_string"])
            case .SERIAL, .INTEGER:
                value = digits(firstNonBlank(adif["srx"], nextToken(srxTokens, tokenIdx)))
            default:
                value = nextToken(srxTokens, tokenIdx)
            }
            if isTokenConsuming(type) {
                tokenIdx += 1
            }
            if let value, !JavaText.isBlank(value) {
                raw.put(f.id, JavaText.trim(value))
            }
        }
        return raw
    }

    /// How many tokens at the start of `srx_string` the report occupies — 0 or 1.
    ///
    /// WSJT-X does not write the report into `srx_string` (it holds only its own exchange there), but the MacContestLogger ADIF export
    /// puts the whole flat exchange there including the report. We recognise it by three things at once: the contest has a report in the
    /// exchange, there is exactly one more token than the fields consume, and the first is exactly
    /// `rst_rcvd` (after `trim()`).
    private static func reportTokensInSrx(_ fields: [ExchangeField], _ srxTokens: [String], _ rstRcvd: String?) -> Int {
        guard let rstRcvd, !JavaText.isBlank(rstRcvd), let first = srxTokens.first else {
            return 0
        }
        let hasReportField: Bool = fields.contains { $0.type == .RST || $0.type == .RS }
        let consuming: Int = fields.filter { $0.type.map(isTokenConsuming) ?? false }.count
        let firstIsReport: Bool = first.utf16.elementsEqual(JavaText.trim(rstRcvd).utf16)
        return hasReportField && firstIsReport && srxTokens.count == consuming + 1 ? 1 : 0
    }

    private static func tokens(_ s: String?) -> [String] {
        guard let s, !JavaText.isBlank(s) else { return [] }
        return whitespace.split(JavaText.trim(s), limit: 0)
    }

    private static func nextToken(_ tokens: [String], _ idx: Int) -> String? {
        idx < tokens.count ? tokens[idx] : nil
    }

    private static func isTokenConsuming(_ type: FieldType) -> Bool {
        switch type {
        case .RST, .RS, .LOCATOR: false
        default: true
        }
    }

    /// `replaceAll("\\D", "")` (ASCII digits) and `Long.parseLong`; a `long` overflow returns the raw digits.
    private static func digits(_ s: String?) -> String? {
        guard let s else { return nil }
        let kept: [UInt16] = s.utf16.filter { $0 >= 0x30 && $0 <= 0x39 }
        if kept.isEmpty {
            return nil
        }
        let d = String(decoding: kept, as: UTF16.self)
        do {
            return String(try JavaInteger.parseLong(d))
        } catch {
            return d // number too long for long — return the raw digits, do not break the import
        }
    }

    private static func firstNonBlank(_ vals: String?...) -> String? {
        for v in vals {
            if let v, !JavaText.isBlank(v) {
                return v
            }
        }
        return nil
    }
}
