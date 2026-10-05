/// Wire DTOs of the cluster sync — counterparts of the Java records from the Gradle submodule `:sync-shared`
/// (`cz.ok1xoe.maccontestlogger.sync`). Fields have Java types: `String`/`Integer`/`Boolean`/`Instant` are
/// optional (Java `null` is written as `null` on the wire and read back), `long` is `Int`/`Int64`, `int` is `Int32`.
/// Component order = order in the Java record (Jackson writes JSON in it). Mapping to the `Qso` model (where text is
/// `""` instead of `null`) is done by `WireMapper`.

/// Raw fields of one QSO over the network. Deliberately **without** `points` and `multiplier` — each station computes the score
/// itself from its own contest definition (no scoring drift). Band and mode are names of Java enums (`M20`, `CW`).
public struct QsoWire: WireMessage {
    public var timestampUtc: JavaInstant?
    public var call: String?
    public var freqHz: Int
    public var band: String?
    public var mode: String?
    public var rstSent: String?
    public var rstRcvd: String?
    public var exchangeSent: String?
    public var exchangeRcvd: String?
    public var serialSent: Int32?
    public var serialRcvd: Int32?
    public var `operator`: String?
    public var comment: String?
    public var dxccEntity: Int32?
    public var dxccName: String?
    public var continent: String?
    /// `null` on older stations = not an X-QSO.
    public var xqso: Bool?

    public init(timestampUtc: JavaInstant?, call: String?, freqHz: Int, band: String?, mode: String?,
                rstSent: String?, rstRcvd: String?, exchangeSent: String?, exchangeRcvd: String?,
                serialSent: Int32?, serialRcvd: Int32?, operator: String?, comment: String?,
                dxccEntity: Int32?, dxccName: String?, continent: String?, xqso: Bool? = nil) {
        self.timestampUtc = timestampUtc
        self.call = call
        self.freqHz = freqHz
        self.band = band
        self.mode = mode
        self.rstSent = rstSent
        self.rstRcvd = rstRcvd
        self.exchangeSent = exchangeSent
        self.exchangeRcvd = exchangeRcvd
        self.serialSent = serialSent
        self.serialRcvd = serialRcvd
        self.operator = `operator`
        self.comment = comment
        self.dxccEntity = dxccEntity
        self.dxccName = dxccName
        self.continent = continent
        self.xqso = xqso
    }

    public static let wireTypeName = "QsoWire"
    public static let wireFields: [WireField] = [
        WireField("timestampUtc", .instant), WireField("call", .string), WireField("freqHz", .long),
        WireField("band", .string), WireField("mode", .string), WireField("rstSent", .string),
        WireField("rstRcvd", .string), WireField("exchangeSent", .string), WireField("exchangeRcvd", .string),
        WireField("serialSent", .intBox), WireField("serialRcvd", .intBox), WireField("operator", .string),
        WireField("comment", .string), WireField("dxccEntity", .intBox), WireField("dxccName", .string),
        WireField("continent", .string), WireField("xqso", .boolBox),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(timestampUtc: v[0].instant, call: v[1].string, freqHz: Int(v[2].long), band: v[3].string,
                  mode: v[4].string, rstSent: v[5].string, rstRcvd: v[6].string, exchangeSent: v[7].string,
                  exchangeRcvd: v[8].string, serialSent: v[9].intBox, serialRcvd: v[10].intBox,
                  operator: v[11].string, comment: v[12].string, dxccEntity: v[13].intBox, dxccName: v[14].string,
                  continent: v[15].string, xqso: v[16].boolBox)
    }

    public var wireValues: [WireValue] {
        var v: [WireValue] = [.instant(timestampUtc), .string(call), .long(Int64(freqHz)), .string(band)]
        v += [.string(mode), .string(rstSent), .string(rstRcvd), .string(exchangeSent), .string(exchangeRcvd)]
        v += [.intBox(serialSent), .intBox(serialRcvd), .string(`operator`), .string(comment)]
        v += [.intBox(dxccEntity), .string(dxccName), .string(continent), .boolBox(xqso)]
        return v
    }
}

/// Canonical state of one contact from the authority (retained `qso/state/<uuid>`); the station merges it by `uuid`
/// with LWW by `version`. Tombstone = `deleted == true` (not an empty payload).
public struct QsoState: WireMessage {
    public var uuid: String?
    public var stationId: String?
    public var version: Int64
    public var updatedAtUtc: JavaInstant?
    public var deleted: Bool
    public var qso: QsoWire?

    public init(uuid: String?, stationId: String?, version: Int64, updatedAtUtc: JavaInstant?, deleted: Bool,
                qso: QsoWire?) {
        self.uuid = uuid
        self.stationId = stationId
        self.version = version
        self.updatedAtUtc = updatedAtUtc
        self.deleted = deleted
        self.qso = qso
    }

    public static let wireTypeName = "QsoState"
    public static let wireFields: [WireField] = [
        WireField("uuid", .string), WireField("stationId", .string), WireField("version", .long),
        WireField("updatedAtUtc", .instant), WireField("deleted", .bool), WireField("qso", .record(QsoWire.wireFields)),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(uuid: v[0].string, stationId: v[1].string, version: v[2].long, updatedAtUtc: v[3].instant,
                  deleted: v[4].bool, qso: v[5].record.map(QsoWire.init(wireValues:)))
    }

    public var wireValues: [WireValue] {
        [.string(uuid), .string(stationId), .long(version), .instant(updatedAtUtc), .bool(deleted),
         .record(qso?.wireValues)]
    }
}

/// Station command to the authority `qso/cmd/insert` and `qso/cmd/update` (full raw fields, not a delta).
public struct QsoCommand: WireMessage {
    public var stationId: String?
    public var uuid: String?
    public var clientTimestampUtc: JavaInstant?
    public var qso: QsoWire?

    public init(stationId: String?, uuid: String?, clientTimestampUtc: JavaInstant?, qso: QsoWire?) {
        self.stationId = stationId
        self.uuid = uuid
        self.clientTimestampUtc = clientTimestampUtc
        self.qso = qso
    }

    public static let wireTypeName = "QsoCommand"
    public static let wireFields: [WireField] = [
        WireField("stationId", .string), WireField("uuid", .string), WireField("clientTimestampUtc", .instant),
        WireField("qso", .record(QsoWire.wireFields)),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, uuid: v[1].string, clientTimestampUtc: v[2].instant,
                  qso: v[3].record.map(QsoWire.init(wireValues:)))
    }

    public var wireValues: [WireValue] {
        [.string(stationId), .string(uuid), .instant(clientTimestampUtc), .record(qso?.wireValues)]
    }
}

/// Station command to the authority `qso/cmd/delete`.
public struct DeleteCommand: WireMessage {
    public var stationId: String?
    public var uuid: String?
    public var clientTimestampUtc: JavaInstant?

    public init(stationId: String?, uuid: String?, clientTimestampUtc: JavaInstant?) {
        self.stationId = stationId
        self.uuid = uuid
        self.clientTimestampUtc = clientTimestampUtc
    }

    public static let wireTypeName = "DeleteCommand"
    public static let wireFields: [WireField] = [
        WireField("stationId", .string), WireField("uuid", .string), WireField("clientTimestampUtc", .instant),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, uuid: v[1].string, clientTimestampUtc: v[2].instant)
    }

    public var wireValues: [WireValue] {
        [.string(stationId), .string(uuid), .instant(clientTimestampUtc)]
    }
}

/// DX spot shared between stations (`spot/new`, N1MM Multi-User telnet sharing); `stationId` = the station that
/// received it from the cluster (own spots are ignored).
public struct SpotWire: WireMessage {
    public var stationId: String?
    public var spotter: String?
    public var freqHz: Int
    public var dxCall: String?
    public var comment: String?

    public init(stationId: String?, spotter: String?, freqHz: Int, dxCall: String?, comment: String?) {
        self.stationId = stationId
        self.spotter = spotter
        self.freqHz = freqHz
        self.dxCall = dxCall
        self.comment = comment
    }

    public static let wireTypeName = "SpotWire"
    public static let wireFields: [WireField] = [
        WireField("stationId", .string), WireField("spotter", .string), WireField("freqHz", .long),
        WireField("dxCall", .string), WireField("comment", .string),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, spotter: v[1].string, freqHz: Int(v[2].long), dxCall: v[3].string,
                  comment: v[4].string)
    }

    public var wireValues: [WireValue] {
        [.string(stationId), .string(spotter), .long(Int64(freqHz)), .string(dxCall), .string(comment)]
    }
}

/// State of a station in the network log (retained `station/status/<stationId>`, N1MM Network Status); Last Will carries
/// `online == false`. `timestampUtc` is an ISO-8601 text of the send instant, `entryCall` the call being typed.
public struct StationStatusWire: WireMessage {
    public var stationId: String?
    public var `operator`: String?
    public var stationType: String?
    public var band: String?
    public var mode: String?
    public var freqHz: Int
    public var runMode: String?
    public var qsoCount: Int32
    public var transmitting: Bool
    public var online: Bool
    public var timestampUtc: String?
    public var entryCall: String?

    public init(stationId: String?, operator: String?, stationType: String?, band: String?, mode: String?,
                freqHz: Int, runMode: String?, qsoCount: Int32, transmitting: Bool, online: Bool,
                timestampUtc: String?, entryCall: String?) {
        self.stationId = stationId
        self.operator = `operator`
        self.stationType = stationType
        self.band = band
        self.mode = mode
        self.freqHz = freqHz
        self.runMode = runMode
        self.qsoCount = qsoCount
        self.transmitting = transmitting
        self.online = online
        self.timestampUtc = timestampUtc
        self.entryCall = entryCall
    }

    /// "offline" state for Last Will (`StationStatusWire.offline`).
    public static func offline(_ stationId: String?) -> StationStatusWire {
        StationStatusWire(stationId: stationId, operator: "", stationType: "", band: "", mode: "", freqHz: 0,
                          runMode: "", qsoCount: 0, transmitting: false, online: false, timestampUtc: nil,
                          entryCall: "")
    }

    public static let wireTypeName = "StationStatusWire"
    public static let wireFields: [WireField] = [
        WireField("stationId", .string), WireField("operator", .string), WireField("stationType", .string),
        WireField("band", .string), WireField("mode", .string), WireField("freqHz", .long),
        WireField("runMode", .string), WireField("qsoCount", .int), WireField("transmitting", .bool),
        WireField("online", .bool), WireField("timestampUtc", .string), WireField("entryCall", .string),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, operator: v[1].string, stationType: v[2].string, band: v[3].string,
                  mode: v[4].string, freqHz: Int(v[5].long), runMode: v[6].string, qsoCount: v[7].int,
                  transmitting: v[8].bool, online: v[9].bool, timestampUtc: v[10].string, entryCall: v[11].string)
    }

    public var wireValues: [WireValue] {
        var v: [WireValue] = [.string(stationId), .string(`operator`), .string(stationType), .string(band)]
        v += [.string(mode), .long(Int64(freqHz)), .string(runMode), .int(qsoCount), .bool(transmitting)]
        v += [.bool(online), .string(timestampUtc), .string(entryCall)]
        return v
    }
}

/// Message between stations on `station/msg` (QoS 1, not retained): chat, station hand-over (pass) or a callsign for the
/// runner's stack (call stacking). `toStation` empty = to all; `freqHz` 0 = not given.
public struct NetMessageWire: WireMessage {
    public static let chat = "CHAT"
    public static let pass = "PASS"
    public static let stack = "STACK"

    public var type: String?
    public var id: String?
    public var fromStation: String?
    public var fromOperator: String?
    public var toStation: String?
    public var text: String?
    public var call: String?
    public var freqHz: Int
    public var mode: String?
    public var timestampUtc: String?

    public init(type: String?, id: String?, fromStation: String?, fromOperator: String?, toStation: String?,
                text: String?, call: String?, freqHz: Int, mode: String?, timestampUtc: String?) {
        self.type = type
        self.id = id
        self.fromStation = fromStation
        self.fromOperator = fromOperator
        self.toStation = toStation
        self.text = text
        self.call = call
        self.freqHz = freqHz
        self.mode = mode
        self.timestampUtc = timestampUtc
    }

    /// Is the message for the given station (to it or to all, and not from it)? Java: `!stationId.equals(fromStation) &&
    /// (toStation == null || toStation.isBlank() || toStation.equals(stationId))`.
    public func isFor(_ stationId: String) -> Bool {
        guard !JavaText.equals(stationId, fromStation) else { return false }
        guard let toStation else { return true }
        return JavaText.isBlank(toStation) || JavaText.equals(toStation, stationId)
    }

    public static let wireTypeName = "NetMessageWire"
    public static let wireFields: [WireField] = [
        WireField("type", .string), WireField("id", .string), WireField("fromStation", .string),
        WireField("fromOperator", .string), WireField("toStation", .string), WireField("text", .string),
        WireField("call", .string), WireField("freqHz", .long), WireField("mode", .string),
        WireField("timestampUtc", .string),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(type: v[0].string, id: v[1].string, fromStation: v[2].string, fromOperator: v[3].string,
                  toStation: v[4].string, text: v[5].string, call: v[6].string, freqHz: Int(v[7].long),
                  mode: v[8].string, timestampUtc: v[9].string)
    }

    public var wireValues: [WireValue] {
        var v: [WireValue] = [.string(type), .string(id), .string(fromStation), .string(fromOperator)]
        v += [.string(toStation), .string(text), .string(call), .long(Int64(freqHz)), .string(mode)]
        v.append(.string(timestampUtc))
        return v
    }
}

/// Request from a station for the next serial number (`serial/request`).
public struct SerialRequest: WireMessage {
    public var stationId: String?
    public var requestId: String?

    public init(stationId: String?, requestId: String?) {
        self.stationId = stationId
        self.requestId = requestId
    }

    public static let wireTypeName = "SerialRequest"
    public static let wireFields: [WireField] = [WireField("stationId", .string), WireField("requestId", .string)]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, requestId: v[1].string)
    }

    public var wireValues: [WireValue] {
        [.string(stationId), .string(requestId)]
    }
}

/// Serial number assigned by the authority (`serial/reply/<stationId>`).
public struct SerialReply: WireMessage {
    public var stationId: String?
    public var requestId: String?
    public var serial: Int32

    public init(stationId: String?, requestId: String?, serial: Int32) {
        self.stationId = stationId
        self.requestId = requestId
        self.serial = serial
    }

    public static let wireTypeName = "SerialReply"
    public static let wireFields: [WireField] = [
        WireField("stationId", .string), WireField("requestId", .string), WireField("serial", .int),
    ]

    public init(wireValues v: [WireValue]) {
        self.init(stationId: v[0].string, requestId: v[1].string, serial: v[2].int)
    }

    public var wireValues: [WireValue] {
        [.string(stationId), .string(requestId), .int(serial)]
    }
}
