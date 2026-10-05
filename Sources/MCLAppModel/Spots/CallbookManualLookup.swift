import Foundation
import MCLCore
import os

/// The result of a lookup the operator asked for (the entry window's button, the log and band map menus).
public struct ManualLookupResult: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The request is in flight.
        case loading
        /// The service has the call: its record and the DXCC country when the call resolves.
        case found(HamQthRecord, country: String?)
        /// The service answered but does not know the call.
        case notFound
        /// The service refused the user name or password.
        case badCredentials(String)
        /// The request failed (offline, timeout, a bad status).
        case networkError(String)
        /// `MCL_INERT_NETWORK`: nothing was asked.
        case networkDisabled
        /// The service has no credentials.
        case notConfigured
    }

    public let call: String
    public let service: CallbookService
    public let state: State

    public init(call: String, service: CallbookService, state: State) {
        self.call = call
        self.service = service
        self.state = state
    }

    /// The record when found.
    public var record: HamQthRecord? {
        if case .found(let record, _) = state { return record }
        return nil
    }

    /// A failure or an empty answer as a Czech message (a key of the translations); `nil` while loading or found.
    public var problem: ContestMessage? {
        switch state {
        case .loading, .found: return nil
        case .notFound: return ContestMessage("Volačka nenalezena")
        case .badCredentials(let text):
            return ContestMessage("Chybné přihlášení (%s)", .string(text))
        case .networkError(let text):
            return ContestMessage("Chyba sítě (%s)", .string(text))
        case .networkDisabled: return ContestMessage("Síť je vypnutá (MCL_INERT_NETWORK)")
        case .notConfigured: return ContestMessage("Chybí přihlašovací údaje")
        }
    }
}

/// An `HttpGetter` that remembers what the service answered, so a failed lookup can say why (the clients report
/// every failure as an empty record).
final class RecordingHttpGetter: HttpGetter {
    struct Exchange: Sendable {
        let url: String
        let status: Int
        let body: String
    }

    private struct State {
        var exchanges: [Exchange] = []
        var failure: String?
    }

    private let inner: any HttpGetter
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ inner: any HttpGetter) {
        self.inner = inner
    }

    var exchanges: [Exchange] { state.withLock { $0.exchanges } }
    var failure: String? { state.withLock { $0.failure } }

    func get(_ url: String) throws(HttpGetFailure) -> HttpGetResponse {
        do {
            let response: HttpGetResponse = try inner.get(url)
            let body = String(decoding: response.body, as: UTF8.self)
            state.withLock { $0.exchanges.append(Exchange(url: url, status: response.status, body: body)) }
            return response
        } catch {
            state.withLock { $0.failure = error.message ?? "I/O" }
            throw error
        }
    }
}

enum ManualLookupClassifier {

    /// Why a lookup that found nothing found nothing: a failed request, a refused login or an unknown call.
    static func problem(for service: CallbookService, failure: String?,
                        exchanges: [RecordingHttpGetter.Exchange]) -> ManualLookupResult.State {
        if let failure {
            return failure == NetworkPorts.disabledMessage ? .networkDisabled : .networkError(failure)
        }
        if let bad = exchanges.first(where: { $0.status != 200 }) {
            return .networkError("HTTP " + String(bad.status))
        }
        let marker: String = service == .hamQth ? "?u=" : "?username="
        if let login = exchanges.first(where: { $0.url.contains(marker) }) {
            let sessionTag: String = service == .hamQth ? "session_id" : "Key"
            if text(of: sessionTag, in: login.body) == nil {
                let errorTag: String = service == .hamQth ? "error" : "Error"
                return .badCredentials(text(of: errorTag, in: login.body) ?? "login")
            }
        }
        return .notFound
    }

    /// The text of the first `<tag>…</tag>` (case-insensitive), blank = none.
    static func text(of tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<" + tag + ">", options: .caseInsensitive),
              let close = xml.range(of: "</" + tag + ">", options: .caseInsensitive, range: open.upperBound..<xml.endIndex)
        else { return nil }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
