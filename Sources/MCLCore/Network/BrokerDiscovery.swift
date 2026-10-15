import Foundation

/// An MQTT broker found in the local network by Bonjour (`_mqtt._tcp` / `_secure-mqtt._tcp`), for the zero-config
/// setup of the network log: Settings → Cluster → „Najít broker v LAN" fills the host and the port.
public struct DiscoveredBroker: Equatable, Sendable, Hashable {
    /// The Bonjour service name (`Mosquitto on hub`).
    public var name: String
    public var host: String
    public var port: Int
    /// Advertised as `_secure-mqtt._tcp` (TLS, typically 8883).
    public var tls: Bool

    public init(name: String, host: String, port: Int, tls: Bool) {
        self.name = name
        self.host = host
        self.port = port
        self.tls = tls
    }

    /// The Bonjour service types that are browsed.
    public static let plainType = "_mqtt._tcp"
    public static let tlsType = "_secure-mqtt._tcp"

    /// `Mosquitto on hub — 192.168.1.10:1883 (TLS)`.
    public var label: String {
        name + " — " + host + ":" + String(port) + (tls ? " (TLS)" : "")
    }

    /// A resolved host as typed into the broker field: an IPv6 address without the zone, a `.local.` name without
    /// the final dot.
    public static func hostText(_ raw: String) -> String {
        var host: String = raw
        if let percent = host.firstIndex(of: "%") {
            host = String(host[..<percent])
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    /// The found brokers without repeats (one service seen on several interfaces), sorted by name.
    public static func unique(_ found: [DiscoveredBroker]) -> [DiscoveredBroker] {
        var seen: Set<String> = []
        var out: [DiscoveredBroker] = []
        for broker in found where seen.insert(broker.name + "|" + String(broker.tls)).inserted {
            out.append(broker)
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Texts of the broker search.
public enum BrokerTexts {
    public static let noneFoundKey = "V místní síti není žádný MQTT broker ohlášený přes Bonjour"
    public static let foundKey = "Nalezené MQTT brokery v místní síti: %s"
    public static let tailscaleMissingKey = "Tailscale není nainstalovaný (aplikace Tailscale ani příkaz tailscale nenalezeny)"
    public static let tailscaleDownKey = "Tailscale není připojený (%s) — spusťte a přihlaste Tailscale"
    public static let tailscaleNoneKey = "Žádná z %s stanic tailnetu online neodpovídá jako MQTT broker"
    public static let tailscaleFoundKey = "Nalezené MQTT brokery v tailnetu: %s"
}
