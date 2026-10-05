/// Sends a logged QSO as WSJT-X messages (type 5 QSO Logged + type 12 Logged ADIF) — port of
/// `wsjtx/WsjtxSender.java` (v1.1.1). The ADIF is a whole document `AdifWriter.toAdif([qso], station:)`
/// (header with the station + one record), as in Java.
public final class WsjtxSender: Sendable {

    private let broadcaster: any Broadcaster
    private let targets: [Target]
    private let adifWriter = AdifWriter()

    public init(_ broadcaster: any Broadcaster, _ targets: [Target]) {
        self.broadcaster = broadcaster
        self.targets = targets
    }

    public func send(_ qso: Qso, _ station: Station?) {
        broadcaster.send(WsjtxMessages.encodeQsoLogged(Self.toQsoLogged(qso, station)), targets)
        let adif: String = adifWriter.toAdif([qso], station: station)
        broadcaster.send(WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: adif)), targets)
    }

    /// The text fields of `Qso` are `""` in Swift instead of Java `null` — Java converts them with `nz` to `""` anyway.
    static func toQsoLogged(_ q: Qso, _ s: Station?) -> WsjtxMessages.QsoLogged {
        WsjtxMessages.QsoLogged(
            dateTimeOff: q.timestampUtc,
            dxCall: q.call,
            dxGrid: "",
            txFreqHz: Int64(q.freqHz),
            mode: q.mode?.adif ?? "",
            reportSent: q.rstSent,
            reportRcvd: q.rstRcvd,
            txPower: "",
            comments: q.comment,
            name: "",
            dateTimeOn: q.timestampUtc,
            opCall: s?.operator ?? "",
            myCall: s?.call ?? "",
            myGrid: s?.gridSquare ?? "",
            exchangeSent: q.exchangeSent,
            exchangeRcvd: q.exchangeRcvd,
            propMode: "")
    }

    public func close() {
        broadcaster.close()
    }
}
