import Foundation
import MCLCore
import Network
import os

/// Browses the local network for MQTT brokers (`_mqtt._tcp`, `_secure-mqtt._tcp`) for `timeoutMs` and resolves each
/// service to a host and port. Only started by the operator (Settings → Cluster → „Najít broker v LAN"); never under
/// `MCL_INERT_NETWORK`. A service is resolved by opening (and at once closing) a TCP connection to it — no data is
/// sent.
public typealias BrokerDiscoverer = @Sendable (_ timeoutMs: Int,
                                               _ done: @escaping @Sendable ([DiscoveredBroker]) -> Void) -> Void

enum BonjourBrokerBrowser {

    /// The inert discoverer: finds nothing at once.
    @Sendable static func inert(_ timeoutMs: Int, _ done: @escaping @Sendable ([DiscoveredBroker]) -> Void) {
        done([])
    }

    @Sendable static func live(_ timeoutMs: Int, _ done: @escaping @Sendable ([DiscoveredBroker]) -> Void) {
        let search = Search(timeoutMs: timeoutMs, done: done)
        search.start()
    }

    /// One search: two browsers, a connection per found service, all cancelled at the deadline.
    private final class Search: @unchecked Sendable {
        private let queue = DispatchQueue(label: "mcl.broker-discovery")
        private let timeoutMs: Int
        private let done: @Sendable ([DiscoveredBroker]) -> Void
        private var browsers: [NWBrowser] = []
        private var connections: [NWConnection] = []
        private var found: [DiscoveredBroker] = []
        private var finished = false

        init(timeoutMs: Int, done: @escaping @Sendable ([DiscoveredBroker]) -> Void) {
            self.timeoutMs = timeoutMs
            self.done = done
        }

        func start() {
            queue.async { [self] in
                for (type, tls) in [(DiscoveredBroker.plainType, false), (DiscoveredBroker.tlsType, true)] {
                    let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
                    browser.browseResultsChangedHandler = { [self] results, _ in
                        for result in results {
                            resolve(result.endpoint, tls: tls)
                        }
                    }
                    browser.start(queue: queue)
                    browsers.append(browser)
                }
                queue.asyncAfter(deadline: .now() + .milliseconds(max(timeoutMs, 500))) { [self] in
                    finish()
                }
            }
        }

        private func resolve(_ endpoint: NWEndpoint, tls: Bool) {
            guard case .service(let name, _, _, _) = endpoint, !finished,
                  !found.contains(where: { $0.name == name && $0.tls == tls }) else { return }
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { [self, weak connection] state in
                guard let connection else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                        let text: String = DiscoveredBroker.hostText("\(host)")
                        if !found.contains(where: { $0.name == name && $0.tls == tls }) {
                            found.append(DiscoveredBroker(name: name, host: text, port: Int(port.rawValue), tls: tls))
                        }
                    }
                    connection.cancel()
                case .failed, .waiting:
                    connection.cancel()
                default:
                    break
                }
            }
            connections.append(connection)
            connection.start(queue: queue)
        }

        private func finish() {
            guard !finished else { return }
            finished = true
            browsers.forEach { $0.cancel() }
            connections.forEach { $0.cancel() }
            let result: [DiscoveredBroker] = DiscoveredBroker.unique(found)
            done(result)
        }
    }
}
