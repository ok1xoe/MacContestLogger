import Foundation

/// (De)serialisation of the WSJT-X messages we use — port of `wsjtx/WsjtxMessages.java` (v1.1.1): Status (1),
/// Decode (2), Clear (3), Reply (4, write only), QSO Logged (5), Logged ADIF (12).
///
/// Texts are `String?` because the wire carries `null` (length −1) and Java holds it in records.
public enum WsjtxMessages {

    public struct QsoLogged: Equatable, Sendable {
        public var dateTimeOff: Date?
        public var dxCall: String?
        public var dxGrid: String?
        public var txFreqHz: Int64
        public var mode: String?
        public var reportSent: String?
        public var reportRcvd: String?
        public var txPower: String?
        public var comments: String?
        public var name: String?
        public var dateTimeOn: Date?
        public var opCall: String?
        public var myCall: String?
        public var myGrid: String?
        public var exchangeSent: String?
        public var exchangeRcvd: String?
        public var propMode: String?

        public init(dateTimeOff: Date?, dxCall: String?, dxGrid: String?, txFreqHz: Int64, mode: String?,
                    reportSent: String?, reportRcvd: String?, txPower: String?, comments: String?, name: String?,
                    dateTimeOn: Date?, opCall: String?, myCall: String?, myGrid: String?, exchangeSent: String?,
                    exchangeRcvd: String?, propMode: String?) {
            self.dateTimeOff = dateTimeOff
            self.dxCall = dxCall
            self.dxGrid = dxGrid
            self.txFreqHz = txFreqHz
            self.mode = mode
            self.reportSent = reportSent
            self.reportRcvd = reportRcvd
            self.txPower = txPower
            self.comments = comments
            self.name = name
            self.dateTimeOn = dateTimeOn
            self.opCall = opCall
            self.myCall = myCall
            self.myGrid = myGrid
            self.exchangeSent = exchangeSent
            self.exchangeRcvd = exchangeRcvd
            self.propMode = propMode
        }
    }

    public struct LoggedAdif: Equatable, Sendable {
        public var adif: String?

        public init(adif: String?) {
            self.adif = adif
        }
    }

    /// A decode from the band: time (ms since UTC midnight), SNR, DT, audio offset, mode, message text.
    ///
    /// Equality like a Java record: `deltaTime` via `Double.compare` (NaN = NaN, `0.0` ≠ `-0.0`).
    public struct Decode: Equatable, Sendable {
        public var id: String?
        public var isNew: Bool
        public var timeMs: Int32
        public var snr: Int32
        public var deltaTime: Double
        public var deltaFrequency: Int32
        public var mode: String?
        public var message: String?
        public var lowConfidence: Bool
        public var offAir: Bool

        public init(id: String?, isNew: Bool, timeMs: Int32, snr: Int32, deltaTime: Double, deltaFrequency: Int32,
                    mode: String?, message: String?, lowConfidence: Bool, offAir: Bool) {
            self.id = id
            self.isNew = isNew
            self.timeMs = timeMs
            self.snr = snr
            self.deltaTime = deltaTime
            self.deltaFrequency = deltaFrequency
            self.mode = mode
            self.message = message
            self.lowConfidence = lowConfidence
            self.offAir = offAir
        }

        public static func == (lhs: Decode, rhs: Decode) -> Bool {
            guard lhs.id == rhs.id, lhs.isNew == rhs.isNew else { return false }
            guard lhs.timeMs == rhs.timeMs, lhs.snr == rhs.snr else { return false }
            let lhsBits: UInt64 = canonicalBits(lhs.deltaTime)
            let rhsBits: UInt64 = canonicalBits(rhs.deltaTime)
            guard lhsBits == rhsBits, lhs.deltaFrequency == rhs.deltaFrequency else { return false }
            guard lhs.mode == rhs.mode, lhs.message == rhs.message else { return false }
            return lhs.lowConfidence == rhs.lowConfidence && lhs.offAir == rhs.offAir
        }

        /// `Double.doubleToLongBits`.
        private static func canonicalBits(_ value: Double) -> UInt64 {
            value.isNaN ? 0x7FF8_0000_0000_0000 : value.bitPattern
        }
    }

    /// WSJT-X status (we take only the start of the message: frequency, mode, DX, transmitting).
    public struct Status: Equatable, Sendable {
        public var id: String?
        public var dialFrequencyHz: Int64
        public var mode: String?
        public var dxCall: String?
        public var report: String?
        public var txMode: String?
        public var txEnabled: Bool
        public var transmitting: Bool

        public init(id: String?, dialFrequencyHz: Int64, mode: String?, dxCall: String?, report: String?,
                    txMode: String?, txEnabled: Bool, transmitting: Bool) {
            self.id = id
            self.dialFrequencyHz = dialFrequencyHz
            self.mode = mode
            self.dxCall = dxCall
            self.report = report
            self.txMode = txMode
            self.txEnabled = txEnabled
            self.transmitting = transmitting
        }
    }

    /// Clearing the decode window in WSJT-X.
    public struct Clear: Equatable, Sendable {
        public var id: String?

        public init(id: String?) {
            self.id = id
        }
    }

    /// Result of `decode` (Java `Object`).
    public enum Message: Equatable, Sendable {
        case qsoLogged(QsoLogged)
        case loggedAdif(LoggedAdif)
        case decode(Decode)
        case status(Status)
        case clear(Clear)
    }

    /// Reply (4): WSJT-X responds to a decode as if the user double-clicked it. `id` must be the Id of the target
    /// WSJT-X instance (from the received message). Fields differ from Decode: no `isNew`, instead of `offAir` a byte
    /// `modifiers` (low 8 bits).
    public static func encodeReply(_ d: Decode, modifiers: Int32) -> [UInt8] {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(WsjtxProtocol.reply)
        WsjtxCodec.writeString(&out, d.id)
        out.writeInt(d.timeMs)
        out.writeInt(d.snr)
        out.writeDouble(d.deltaTime)
        out.writeInt(d.deltaFrequency)
        WsjtxCodec.writeString(&out, d.mode)
        WsjtxCodec.writeString(&out, d.message)
        out.writeBoolean(d.lowConfidence)
        out.writeByte(modifiers)
        return out.bytes
    }

    /// Writing a Decode (WSJT-X sends it; here for tests and simulation).
    public static func encodeDecode(_ d: Decode) -> [UInt8] {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(WsjtxProtocol.decode)
        WsjtxCodec.writeString(&out, d.id)
        out.writeBoolean(d.isNew)
        out.writeInt(d.timeMs)
        out.writeInt(d.snr)
        out.writeDouble(d.deltaTime)
        out.writeInt(d.deltaFrequency)
        WsjtxCodec.writeString(&out, d.mode)
        WsjtxCodec.writeString(&out, d.message)
        out.writeBoolean(d.lowConfidence)
        out.writeBoolean(d.offAir)
        return out.bytes
    }

    public static func encodeQsoLogged(_ m: QsoLogged) -> [UInt8] {
        var out = WsjtxDataOutput()
        writeHeader(&out, WsjtxProtocol.qsoLogged)
        WsjtxCodec.writeDateTimeUtc(&out, m.dateTimeOff)
        WsjtxCodec.writeString(&out, m.dxCall)
        WsjtxCodec.writeString(&out, m.dxGrid)
        out.writeLong(m.txFreqHz)
        WsjtxCodec.writeString(&out, m.mode)
        WsjtxCodec.writeString(&out, m.reportSent)
        WsjtxCodec.writeString(&out, m.reportRcvd)
        WsjtxCodec.writeString(&out, m.txPower)
        WsjtxCodec.writeString(&out, m.comments)
        WsjtxCodec.writeString(&out, m.name)
        WsjtxCodec.writeDateTimeUtc(&out, m.dateTimeOn)
        WsjtxCodec.writeString(&out, m.opCall)
        WsjtxCodec.writeString(&out, m.myCall)
        WsjtxCodec.writeString(&out, m.myGrid)
        WsjtxCodec.writeString(&out, m.exchangeSent)
        WsjtxCodec.writeString(&out, m.exchangeRcvd)
        WsjtxCodec.writeString(&out, m.propMode)
        return out.bytes
    }

    public static func encodeLoggedAdif(_ m: LoggedAdif) -> [UInt8] {
        var out = WsjtxDataOutput()
        writeHeader(&out, WsjtxProtocol.loggedAdif)
        WsjtxCodec.writeString(&out, m.adif)
        return out.bytes
    }

    /// Returns `QsoLogged`, `LoggedAdif`, `Decode`, `Status`, `Clear`, or `nil` for other types.
    ///
    /// As in Java: a bad magic → `badMagic` (`IllegalArgumentException`); the schema is not checked;
    /// the Id is read for every type (also an unknown one); truncated data → `endOfStream`, a string length above
    /// 65 535 → `stringLengthOutOfRange` (both `UncheckedIOException` in Java); a Julian day outside
    /// `LocalDate` → `epochDayOutOfRange` (an unwrapped `DateTimeException`). Decode reads the last two
    /// booleans only when bytes remain (older WSJT-X); Status only the start of the message; excess bytes
    /// are ignored.
    public static func decode(_ data: [UInt8]) throws(WsjtxError) -> Message? {
        var input = WsjtxDataInput(data)
        let magic: Int32 = try input.readInt()
        if magic != WsjtxProtocol.magic {
            throw .badMagic(magic)
        }
        _ = try input.readInt() // schema — not checked strictly
        let type: Int32 = try input.readInt()
        let id: String? = try WsjtxCodec.readString(&input)
        switch type {
        case WsjtxProtocol.decode:
            return .decode(try readDecode(&input, id))
        case WsjtxProtocol.status:
            return .status(try readStatus(&input, id))
        case WsjtxProtocol.clear:
            return .clear(Clear(id: id))
        case WsjtxProtocol.qsoLogged:
            return .qsoLogged(try readQsoLogged(&input))
        case WsjtxProtocol.loggedAdif:
            return .loggedAdif(LoggedAdif(adif: try WsjtxCodec.readString(&input)))
        default:
            return nil
        }
    }

    private static func readDecode(_ input: inout WsjtxDataInput, _ id: String?) throws(WsjtxError) -> Decode {
        let isNew: Bool = try input.readBoolean()
        let timeMs: Int32 = try input.readInt()
        let snr: Int32 = try input.readInt()
        let deltaTime: Double = try input.readDouble()
        let deltaFrequency: Int32 = try input.readInt()
        let mode: String? = try WsjtxCodec.readString(&input)
        let message: String? = try WsjtxCodec.readString(&input)
        let lowConfidence: Bool = try readOptionalBoolean(&input)
        let offAir: Bool = try readOptionalBoolean(&input)
        return Decode(id: id, isNew: isNew, timeMs: timeMs, snr: snr, deltaTime: deltaTime,
                      deltaFrequency: deltaFrequency, mode: mode, message: message,
                      lowConfidence: lowConfidence, offAir: offAir)
    }

    /// `in.available() > 0 && in.readBoolean()`.
    private static func readOptionalBoolean(_ input: inout WsjtxDataInput) throws(WsjtxError) -> Bool {
        guard input.available > 0 else { return false }
        return try input.readBoolean()
    }

    private static func readStatus(_ input: inout WsjtxDataInput, _ id: String?) throws(WsjtxError) -> Status {
        let dial: Int64 = try input.readLong()
        let mode: String? = try WsjtxCodec.readString(&input)
        let dxCall: String? = try WsjtxCodec.readString(&input)
        let report: String? = try WsjtxCodec.readString(&input)
        let txMode: String? = try WsjtxCodec.readString(&input)
        let txEnabled: Bool = try input.readBoolean()
        let transmitting: Bool = try input.readBoolean()
        return Status(id: id, dialFrequencyHz: dial, mode: mode, dxCall: dxCall, report: report, txMode: txMode,
                      txEnabled: txEnabled, transmitting: transmitting)
    }

    private static func readQsoLogged(_ input: inout WsjtxDataInput) throws(WsjtxError) -> QsoLogged {
        let off: Date? = try WsjtxCodec.readDateTimeUtc(&input)
        let dxCall: String? = try WsjtxCodec.readString(&input)
        let dxGrid: String? = try WsjtxCodec.readString(&input)
        let freq: Int64 = try input.readLong()
        let mode: String? = try WsjtxCodec.readString(&input)
        let reportSent: String? = try WsjtxCodec.readString(&input)
        let reportRcvd: String? = try WsjtxCodec.readString(&input)
        let txPower: String? = try WsjtxCodec.readString(&input)
        let comments: String? = try WsjtxCodec.readString(&input)
        let name: String? = try WsjtxCodec.readString(&input)
        let on: Date? = try WsjtxCodec.readDateTimeUtc(&input)
        let opCall: String? = try WsjtxCodec.readString(&input)
        let myCall: String? = try WsjtxCodec.readString(&input)
        let myGrid: String? = try WsjtxCodec.readString(&input)
        let exchangeSent: String? = try WsjtxCodec.readString(&input)
        let exchangeRcvd: String? = try WsjtxCodec.readString(&input)
        let propMode: String? = try WsjtxCodec.readString(&input)
        return QsoLogged(dateTimeOff: off, dxCall: dxCall, dxGrid: dxGrid, txFreqHz: freq, mode: mode,
                         reportSent: reportSent, reportRcvd: reportRcvd, txPower: txPower, comments: comments,
                         name: name, dateTimeOn: on, opCall: opCall, myCall: myCall, myGrid: myGrid,
                         exchangeSent: exchangeSent, exchangeRcvd: exchangeRcvd, propMode: propMode)
    }

    private static func writeHeader(_ out: inout WsjtxDataOutput, _ type: Int32) {
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(type)
        WsjtxCodec.writeString(&out, WsjtxProtocol.idOut)
    }
}
