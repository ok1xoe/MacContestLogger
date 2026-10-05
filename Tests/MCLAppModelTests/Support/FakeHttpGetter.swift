import Foundation
import MCLCore
import os

/// The callbooks' HTTP in tests: a closure over the URL text, no socket and no name lookup — the clients' real
/// service URLs never leave the process. Answers by the first route whose fragment the URL contains (otherwise a
/// failure) and records every URL.
final class FakeHttpGetter: HttpGetter {

    struct Route: Sendable {
        let fragment: String
        let status: Int
        let body: String
    }

    private struct State {
        var routes: [Route]
        var urls: [String] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ routes: [Route] = []) {
        state = OSAllocatedUnfairLock(initialState: State(routes: routes))
    }

    var urls: [String] {
        state.withLock { $0.urls }
    }

    func route(_ fragment: String, _ body: String, status: Int = 200) {
        state.withLock { $0.routes.append(Route(fragment: fragment, status: status, body: body)) }
    }

    func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
        let route: Route? = state.withLock { s in
            s.urls.append(url)
            return s.routes.first { url.contains($0.fragment) }
        }
        guard let route else { throw HttpGetFailure("no route") }
        return HttpGetResponse(status: route.status, body: Data(route.body.utf8))
    }

    /// HamQTH: a session for `u=`, then the record of `callsign=<call>`.
    func hamQth(call: String, grid: String = "", name: String = "", cq: String = "", itu: String = "") {
        route("hamqth.com/xml.php?u=", "<HamQTH><session><session_id>s1</session_id></session></HamQTH>")
        var xml = "<HamQTH><search><callsign>" + call + "</callsign><nick>" + name + "</nick>"
        xml += "<grid>" + grid + "</grid><cq>" + cq + "</cq><itu>" + itu + "</itu></search></HamQTH>"
        route("hamqth.com/xml.php?id=s1&callsign=" + call + "&", xml)
    }

    /// QRZ.com: a key for `username=`, then the record of `callsign=<call>`.
    func qrz(call: String, grid: String = "", name: String = "", cq: String = "", itu: String = "") {
        route("xmldata.qrz.com/xml/current/?username=", "<QRZDatabase><Session><Key>k1</Key></Session></QRZDatabase>")
        var xml = "<QRZDatabase><Callsign><call>" + call + "</call><fname>" + name + "</fname>"
        xml += "<grid>" + grid + "</grid><cqzone>" + cq + "</cqzone><ituzone>" + itu + "</ituzone></Callsign>"
        xml += "<Session><Key>k1</Key></Session></QRZDatabase>"
        route("xmldata.qrz.com/xml/current/?s=k1;callsign=" + call, xml)
    }
}
