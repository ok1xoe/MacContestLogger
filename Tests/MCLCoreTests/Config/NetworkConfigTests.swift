import Foundation
import Testing
@testable import MCLCore

@Suite struct NetworkConfigTests {

    // MARK: - An empty JSON gives the same values as init()

    @Test func emptyJsonEqualsDefaults() throws {
        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(ClusterConfig.self, from: empty) == ClusterConfig())
        #expect(try JSONDecoder().decode(DxClusterConfig.self, from: empty) == DxClusterConfig())
        #expect(try JSONDecoder().decode(HamQthConfig.self, from: empty) == HamQthConfig())
        #expect(try JSONDecoder().decode(QrzConfig.self, from: empty) == QrzConfig())
        #expect(try JSONDecoder().decode(ClubLogConfig.self, from: empty) == ClubLogConfig())
        #expect(try JSONDecoder().decode(BroadcastConfig.self, from: empty) == BroadcastConfig())
        #expect(try JSONDecoder().decode(WsjtxConfig.self, from: empty) == WsjtxConfig())
        #expect(try JSONDecoder().decode(N1mmRecvConfig.self, from: empty) == N1mmRecvConfig())
        #expect(try JSONDecoder().decode(AdifUdpConfig.self, from: empty) == AdifUdpConfig())
        #expect(try JSONDecoder().decode(MapConfig.self, from: empty) == MapConfig())
    }

    // MARK: - DxClusterConfigTest

    @Test func defaultCommandsHasTen() {
        #expect(DxClusterConfig.defaultCommands().count == DxClusterConfig.commandCount)
    }

    /// Replaces the Java `new AppConfig().getDxCluster()`: `AppConfig` exists
    /// in Swift, but `dxCluster` is just one of its nested configurations —
    /// a fresh `DxClusterConfig()` is verified directly, not by a detour through the whole `AppConfig`.
    @Test func freshConfigHasDefaultCommandsAndNoFavorites() {
        let c = DxClusterConfig()
        #expect(c.commands.count == DxClusterConfig.commandCount)
        #expect(c.favorites.isEmpty)
    }

    @Test func favoriteDefaultsToPort7300() {
        #expect(DxClusterFavorite().port == 7300)
    }

    /// Replaces the Java save/load via `ConfigStore`/`AppConfig`: a JSON round-trip
    /// directly over `DxClusterConfig` itself is verified, without going through
    /// the whole `AppConfig` (which already exists in Swift — see `ConfigStoreTests`).
    @Test func savesAndReloadsFavoritesAndCommands() throws {
        var config = DxClusterConfig()
        config.favorites = [
            DxClusterFavorite(name: "HamQTH", host: "hamqth.com", port: 7300, login: "OK1XOE", password: "pass"),
            DxClusterFavorite(name: "NC7J", host: "dxc.nc7j.com", port: 7373, login: "OK1XOE", password: ""),
        ]
        config.commands = [
            DxClusterCommand(label: "Spoty", command: "SH/DX"),
            DxClusterCommand(label: "Nápověda", command: "HELP"),
        ]
        config.lastFavorite = "NC7J"

        let data = try JSONEncoder().encode(config)
        let reloaded = try JSONDecoder().decode(DxClusterConfig.self, from: data)

        #expect(reloaded.favorites.count == 2)
        #expect(reloaded.favorites[0].name == "HamQTH")
        #expect(reloaded.favorites[0].host == "hamqth.com")
        #expect(reloaded.favorites[0].port == 7300)
        #expect(reloaded.favorites[0].login == "OK1XOE")
        #expect(reloaded.favorites[0].password == "pass")
        #expect(reloaded.favorites[1].port == 7373)
        #expect(reloaded.commands.count == 2)
        #expect(reloaded.commands[0].label == "Spoty")
        #expect(reloaded.commands[0].command == "SH/DX")
        #expect(reloaded.lastFavorite == "NC7J")
    }

    @Test func spotBufferAndWheelDefaults() {
        let c = DxClusterConfig()
        #expect(c.spotBufferMinutes == 90)
        #expect(c.wheelStepHz == 100)
    }

    /// Replaces the Java save/load via `ConfigStore`/`AppConfig` — the same
    /// reason as for `savesAndReloadsFavoritesAndCommands`.
    @Test func savesAndReloadsSpotBufferAndWheel() throws {
        var config = DxClusterConfig()
        config.spotBufferMinutes = 45
        config.wheelStepHz = 250

        let data = try JSONEncoder().encode(config)
        let reloaded = try JSONDecoder().decode(DxClusterConfig.self, from: data)

        #expect(reloaded.spotBufferMinutes == 45)
        #expect(reloaded.wheelStepHz == 250)
    }

    // MARK: - BroadcastConfigTest

    @Test func broadcastDefaults() {
        let b = BroadcastConfig()
        #expect(b.contactsEnabled == false)
        #expect(b.contactsTargets == "")
        #expect(b.radioTargets == "")
        #expect(b.scoreTargets == "")
        #expect(b.appInfoTargets == "")
    }

    /// Replaces the Java `appConfigHasBroadcastRoundTrip` (Jackson via `AppConfig`):
    /// `AppConfig` exists in Swift, but `broadcast` is just one of its nested
    /// configurations — a JSON round-trip directly over `BroadcastConfig` itself is verified.
    @Test func broadcastRoundTripsThroughJson() throws {
        var c = BroadcastConfig()
        c.contactsEnabled = true
        c.contactsTargets = "127.0.0.1:12060"

        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(BroadcastConfig.self, from: data)

        #expect(back.contactsEnabled == true)
        #expect(back.contactsTargets == "127.0.0.1:12060")
    }

    // MARK: - WsjtxConfigTest

    @Test func wsjtxDefaultsAreSafe() {
        let c = WsjtxConfig()
        #expect(c.receiveEnabled == false)
        #expect(c.sendEnabled == false)
        #expect(c.receiveBind == "0.0.0.0:2237")
        #expect(c.sendTargets == "")
    }

    // `setReceiveBind(null)`/`setSendTargets(null)`/`setWsjtx(null)` cannot be written
    // on their own — `receiveBind`/`sendTargets` are non-optional `String`s here and
    // `wsjtx` in `AppConfig` is a non-optional `var`, not `Optional`. The same state (`null`
    // in place of that value) can however be provoked via JSON — hence the two tests below on an
    // explicit `null`.

    /// Replaces `nullSettersAreCoerced`. `sendTargets` matches Java (coerce
    /// and the declared Swift default are `""`), but `receiveBind` NOT: the Java getter after
    /// `setReceiveBind(null)` returns `""`, whereas the shared `value(_:default:)` in
    /// Swift merges a missing key and an explicit `null` into the declared default
    /// `"0.0.0.0:2237"`. The test pins the actual (different) Swift behaviour — the difference is
    /// reachable only by hand-editing `config.json`, the application itself serialises
    /// via the coercing getters of `WsjtxConfig.java`, which never write `null`.
    @Test func wsjtxExplicitNullsDecodeToSwiftDefaults() throws {
        let json = #"{"receiveBind": null, "sendTargets": null}"#
        let c = try JSONDecoder().decode(WsjtxConfig.self, from: Data(json.utf8))
        #expect(c.receiveBind == "0.0.0.0:2237") // Java would return "" here (setter coerce)
        #expect(c.sendTargets == "")
    }

    /// Replaces `appConfigNeverReturnsNullWsjtx`. Here Swift matches Java:
    /// `{"wsjtx": null}` substitutes a fresh default `WsjtxConfig` the same way as
    /// `setWsjtx(null)` in Java substitutes a new `WsjtxConfig()` — both have
    /// `receiveEnabled == false`.
    @Test func appConfigExplicitNullWsjtxDecodesToFreshDefault() throws {
        let json = #"{"wsjtx": null}"#
        let a = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(a.wsjtx.receiveEnabled == false)
    }

    // MARK: - N1mmRecvConfigTest

    @Test func n1mmRecvDefaultsAreSafe() {
        let c = N1mmRecvConfig()
        #expect(c.receiveEnabled == false)
        #expect(c.receiveBind == "0.0.0.0:12061")
    }

    /// Replaces `nullBindCoerced` — see `wsjtxExplicitNullsDecodeToSwiftDefaults`.
    /// Here no value matches Java: `setReceiveBind(null)` in Java returns
    /// `""`, `value(_:default:)` in Swift returns the declared default
    /// `"0.0.0.0:12061"`. The difference is reachable only by hand-editing `config.json`
    /// — `N1mmRecvConfig.java` serialises via the same coercing getter.
    @Test func n1mmRecvExplicitNullBindDecodesToSwiftDefault() throws {
        let json = #"{"receiveBind": null}"#
        let c = try JSONDecoder().decode(N1mmRecvConfig.self, from: Data(json.utf8))
        #expect(c.receiveBind == "0.0.0.0:12061") // Java would return "" here (setter coerce)
    }

    /// Replaces `appConfigNeverReturnsNull` — a match with Java just like
    /// `appConfigExplicitNullWsjtxDecodesToFreshDefault`.
    @Test func appConfigExplicitNullN1mmRecvDecodesToFreshDefault() throws {
        let json = #"{"n1mmRecv": null}"#
        let a = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(a.n1mmRecv.receiveEnabled == false)
    }

    // MARK: - AdifUdpConfigTest

    @Test func adifUdpDefaultsAreSafe() {
        let c = AdifUdpConfig()
        #expect(c.receiveEnabled == false)
        #expect(c.receiveBind == "0.0.0.0:2333")
    }

    /// Replaces `nullBindCoerced` — the same difference as for `N1mmRecvConfig`: Java
    /// `setReceiveBind(null)` returns `""`, Swift `value(_:default:)` returns the declared
    /// default `"0.0.0.0:2333"`. Reachable only by hand-editing `config.json` —
    /// `AdifUdpConfig.java` serialises via the same coercing getter.
    @Test func adifUdpExplicitNullBindDecodesToSwiftDefault() throws {
        let json = #"{"receiveBind": null}"#
        let c = try JSONDecoder().decode(AdifUdpConfig.self, from: Data(json.utf8))
        #expect(c.receiveBind == "0.0.0.0:2333") // Java would return "" here (setter coerce)
    }

    /// Replaces `appConfigNeverReturnsNull` — a match with Java just like
    /// `appConfigExplicitNullWsjtxDecodesToFreshDefault`.
    @Test func appConfigExplicitNullAdifUdpDecodesToFreshDefault() throws {
        let json = #"{"adifUdp": null}"#
        let a = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(a.adifUdp.receiveEnabled == false)
    }

    // MARK: - ClusterConfig / HamQth / Qrz / ClubLog / Map — without a Java test
    //
    // These five types (`ClusterConfig`, `HamQthConfig`, `QrzConfig`, `ClubLogConfig`,
    // `MapConfig`) have no test class in Java — they are covered only by the test
    // "empty JSON = default values" above. Added on top: a normalisation that
    // that test alone would not catch.

    @Test func hamQthAndQrzHaveDigiDefaults() {
        #expect(HamQthConfig().callModes == ["DIGI"])
        #expect(HamQthConfig().fetchFields == ["grid", "cqZone", "ituZone", "name"])
        #expect(QrzConfig().callModes == ["DIGI"])
        #expect(QrzConfig().fetchFields == ["grid", "cqZone", "ituZone", "name"])
    }

    @Test func clubLogConfiguredRequiresAllThreeFields() {
        var c = ClubLogConfig()
        c.enabled = true
        #expect(c.configured() == false)
        c.email = "ok1xoe@example.com"
        c.appPassword = "app-pass"
        c.apiKey = "key"
        #expect(c.configured() == true)
        c.enabled = false
        #expect(c.configured() == false)
    }

    @Test func mapSchemeBlankFallsBackToGreen() throws {
        #expect(MapConfig().scheme == "green")
        var c = MapConfig()
        c.scheme = "  "
        #expect(c.scheme == "green")

        let json = Data(#"{"scheme":"blue"}"#.utf8)
        #expect(try JSONDecoder().decode(MapConfig.self, from: json).scheme == "blue")

        let blankJson = Data(#"{"scheme":"  "}"#.utf8)
        #expect(try JSONDecoder().decode(MapConfig.self, from: blankJson).scheme == "green")
    }

    @Test func clusterConfigDefaults() {
        let c = ClusterConfig()
        #expect(c.enabled == false)
        #expect(c.port == 1883)
        #expect(c.shareSpots == true)
        #expect(c.interlock == .none)
        #expect(c.stationType == .none)
        #expect(c.ruleEnforcement == .warn)
        #expect(c.serialServer == false)
    }

    /// The `ClusterConfig` enums have no `@JsonValue` in Java — Jackson serialises them
    /// by constant name (uppercase). Guards the wire format — it must not change
    /// by `Interlock`/`OperatingGuard` living in `Cluster/`/`Contest/Engine/`,
    /// not as nested types of `ClusterConfig`.
    @Test func clusterConfigEnumsSerializeAsJavaConstantNames() throws {
        var c = ClusterConfig()
        c.interlock = .sameBand
        c.stationType = .mult
        c.ruleEnforcement = .block
        let data = try JSONEncoder().encode(c)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains(#""interlock":"SAME_BAND""#))
        #expect(json.contains(#""stationType":"MULT""#))
        #expect(json.contains(#""ruleEnforcement":"BLOCK""#))

        // Decoding back (not just encoding) — both sides of the wire format.
        let decoded = try JSONDecoder().decode(ClusterConfig.self, from: data)
        #expect(decoded.interlock == .sameBand)
        #expect(decoded.stationType == .mult)
        #expect(decoded.ruleEnforcement == .block)
    }
}
