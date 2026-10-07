import Foundation
@testable import MCLAppModel
@testable import MCLCore
import os
import Testing

/// Window plugins that act on the app: the consent and the grants, the acting requests through the real models
/// (entry, rig, spots, text commands — never a transmitter, never a real rig or network), key-bound actions,
/// docking, the multipliers request and canvas clicks.
@MainActor @Suite struct PluginStage2ModelTests {
    typealias T = PluginWindowsModelTests

    static let key = T.key

    /// A plugin that logs its input (`in.log`) and its hello (`hello.json`) and shows "up".
    static let logging: String = """
        IFS= read -r hello
        printf '%s\\n' "$hello" > hello.json
        \(T.setText("up"))
        \(T.echoLoop)
        """

    /// Writes a plugin whose manifest is `manifest` (a JSON object without `protocol`).
    @discardableResult
    static func rawPlugin(_ app: IntegrationApp, name: String = "demo", manifest: String, body: String) throws -> URL {
        let dir: URL = app.app.dataDir.appendingPathComponent("plugins/" + name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ("{\"protocol\":1," + manifest + "}").write(to: dir.appendingPathComponent("plugin.json"), atomically: true,
                                                         encoding: .utf8)
        let run: URL = dir.appendingPathComponent("run")
        try ("#!/bin/sh\n" + body + "\n").write(to: run, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)
        return dir
    }

    // MARK: - consent and grants

    @Test func aPluginAskingForMoreWaitsForConsentThenStartsWithTheGrant() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try T.plugin(app, permissions: ["read", "ui", "entry", "rig"], body: Self.logging)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        #expect(model.session("demo")?.phase == .awaitingConsent)
        #expect(model.consentRequest == "demo")
        #expect(model.banner(Self.key) == "Plugin čeká na povolení oprávnění")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("hello.json").path))

        model.answerConsent("demo", granted: ["entry"])
        #expect(model.consentRequest == nil)
        await eventually("running") { T.shownText(model.session("demo")) == "up" }
        let hello: PluginJSON? = T.lines(dir.appendingPathComponent("hello.json")).first.flatMap(T.json)
        #expect(hello?["permissions"] == .array([.string("read"), .string("ui"), .string("entry")]))
        await model.settleSettings()
        #expect(PluginSettings.load(dataDir: app.app.dataDir).grants["demo"] == ["entry"])
        // The next start does not ask again.
        model.windowClosed(Self.key)
        model.open(Self.key)
        #expect(model.session("demo")?.phase == .starting)
        await model.shutdown()
    }

    /// A refused or revoked permission gives the `permission` error; a revoke applies to the next request.
    @Test func ungrantedRequestsGetAPermissionError() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try T.plugin(app, permissions: ["read", "ui", "entry"], body: """
            IFS= read -r hello
            \(T.setText("up"))
            while IFS= read -r line; do
              printf '%s\\n' "$line" >> in.log
              case "$line" in *'"action":"click"'*)
                echo '{"type":"request","id":1,"method":"entry.setCall","params":{"call":"OK1PLG"}}' ;;
              esac
            done
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.answerConsent("demo", granted: [])
        model.open(Self.key)
        await eventually("up") { T.shownText(model.session("demo")) == "up" }
        let log: URL = dir.appendingPathComponent("in.log")
        model.click(Self.key, target: "go")
        await eventually("refused") { T.lines(log).contains { $0.contains("\"permission\"") } }
        #expect(app.model.entry.form.call == "")
        model.setGrants("demo", ["entry"])
        model.click(Self.key, target: "go")
        await eventually("granted") { app.model.entry.form.call == "OK1PLG" }
        model.setGrants("demo", [])
        app.model.entry.callChanged("")
        model.click(Self.key, target: "go")
        await eventually("revoked") { T.lines(log).filter { $0.contains("\"permission\"") }.count == 2 }
        #expect(app.model.entry.form.call == "")
        await model.shutdown()
    }

    // MARK: - acting requests through the models

    static func act(_ app: IntegrationApp, _ method: String, _ params: [String: PluginJSON] = [:],
                    permissions: [String] = ["read", "ui", "entry", "rig", "spots", "spots.send", "app.command"])
        async -> Result<PluginJSON, PluginRpc.Failure> {
        await PluginRpc.answer(method: method, params: params, permissions: permissions,
                               context: app.model.pluginWindows.context)
    }

    @Test func entryRequestsActOnTheEntryWindow() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("14025")
        #expect(try await Self.act(app, "entry.setCall", ["call": .string("OK1ABC")]).get() != .null)
        #expect(entry.form.call == "OK1ABC")
        let set = try await Self.act(app, "entry.setExchange", ["fields": .object(["zone": .string("15"),
                                                                                   "nope": .string("x")])]).get()
        #expect(set["unknown"] == .array([.string("nope")]))
        #expect(entry.form.contestExchange["zone"] == "15")
        let state = try await Self.act(app, "entry.getCall").get()
        #expect(state["call"] == .string("OK1ABC"))
        #expect(state["exchange"]?["zone"] == .string("15"))
        #expect(state["freqHz"] == .int(14_025_000))
        _ = await Self.act(app, "entry.log")
        await entry.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["OK1ABC"])
        // A command in the call field is never run by entry.log.
        entry.callChanged("CLEARLOG")
        #expect(await Self.act(app, "entry.log")
            == .failure(PluginRpc.Failure(code: "refused", message: "the call field holds a command")))
        _ = await Self.act(app, "entry.wipe")
        #expect(entry.form.call == "")
        _ = await Self.act(app, "entry.status", ["text": .string("hello from plugin")])
        #expect(app.model.status.message == "hello from plugin")
        #expect(await Self.act(app, "entry.setCall")
            == .failure(PluginRpc.Failure(code: "invalid_params", message: "entry.setCall needs call")))
    }

    @Test func rigRequestsTuneThroughTheEntry() async throws {
        let app = try await IntegrationApp.make()
        let entry: EntryModel = app.model.entry
        _ = try await Self.act(app, "rig.qsy", ["freqHz": .int(7_012_000), "mode": .string("CW")]).get()
        #expect(entry.form.freqHz == 7_012_000)
        #expect(entry.form.mode == .cw)
        _ = try await Self.act(app, "rig.setMode", ["mode": .string("ssb")]).get()
        #expect(entry.form.mode == .ssb)
        #expect(await Self.act(app, "rig.setMode", ["mode": .string("morse")])
            == .failure(PluginRpc.Failure(code: "invalid_params", message: "rig.setMode needs a known mode")))
        #expect(await Self.act(app, "rig.rit", ["offsetHz": .int(200_000)])
            == .failure(PluginRpc.Failure(code: "invalid_params", message: "rig.rit needs offsetHz within ±99999")))
        _ = try await Self.act(app, "rig.split", ["off": .bool(true)]).get()
        _ = try await Self.act(app, "rig.swap").get()
        _ = try await Self.act(app, "rig.focusedRadio", ["radio": .int(0)]).get()
        #expect(await Self.act(app, "rig.focusedRadio", ["radio": .int(3)])
            == .failure(PluginRpc.Failure(code: "invalid_params", message: "rig.focusedRadio needs radio 0 or 1")))
        // Without the permission nothing moves.
        #expect(await Self.act(app, "rig.qsy", ["freqHz": .int(3_500_000)], permissions: ["read"])
            == .failure(PluginRpc.Failure(code: "permission", message: "rig.qsy needs the rig permission")))
        #expect(entry.form.freqHz == 7_012_000)
    }

    @Test func spotRequestsUseTheSpotBufferAndTheBlacklist() async throws {
        let app = try await IntegrationApp.make()
        let buffer: SpotBuffer = app.model.dxCluster.spots
        _ = try await Self.act(app, "spots.add", ["call": .string("dl1aa"), "freqHz": .int(14_025_000),
                                                  "comment": .string("from plugin")]).get()
        #expect(buffer.snapshot().map(\.dxCall) == ["DL1AA"])
        #expect(try await Self.act(app, "spots.remove", ["call": .string("DL1AA")]).get()["removed"] == .bool(true))
        #expect(buffer.snapshot().isEmpty)
        #expect(try await Self.act(app, "spots.remove", ["call": .string("DL1AA")]).get()["removed"] == .bool(false))
        _ = try await Self.act(app, "spots.mark", ["freqHz": .int(14_030_000)]).get()
        #expect(buffer.snapshot().count == 1)
        _ = try await Self.act(app, "spots.blacklist", ["call": .string("pirate")]).get()
        #expect(app.model.blacklist.entries(isCall: true).map(\.value).contains("PIRATE"))
        // Not connected (no network in tests): spots.send is refused with the reason, nothing is sent.
        let sent = await Self.act(app, "spots.send", ["call": .string("DL1AA"), "freqHz": .int(14_025_000)])
        guard case .failure(let failure) = sent else {
            Issue.record("spots.send must not succeed without a cluster connection")
            return
        }
        #expect(failure.code == "refused")
        // spots.send needs its own grant.
        #expect(await Self.act(app, "spots.send", ["call": .string("DL1AA"), "freqHz": .int(14_025_000)],
                               permissions: ["spots"])
            == .failure(PluginRpc.Failure(code: "permission", message: "spots.send needs the spots.send permission")))
    }

    @Test func textCommandsRunOnlyWhenTheyCannotTransmit() async throws {
        let app = try await IntegrationApp.make()
        let entry: EntryModel = app.model.entry
        _ = try await Self.act(app, "app.command", ["text": .string("21025")]).get()
        await entry.settle()
        #expect(entry.form.freqHz == 21_025_000)
        for text in ["RPT", "ESM", "SPOTME", "CLEARLOG", "EXIT"] {
            let result = await Self.act(app, "app.command", ["text": .string(text)])
            guard case .failure(let failure) = result else {
                Issue.record("\(text) must be refused")
                continue
            }
            #expect(failure.code == "refused")
        }
        #expect(!app.model.operating.cqRepeat)
        #expect(await Self.act(app, "app.command", ["text": .string("OK1ABC")])
            == .failure(PluginRpc.Failure(code: "refused", message: "not a command")))
    }

    @Test func multipliersOfTheActiveContest() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.app.logContestQso(call: "W1AW", zone: "5", freqKHz: "7025")
        let result = try PluginJSON.parse(try await Self.act(app, "contest.multipliers").get().serialized())
        let list: [PluginJSON] = try #require(result["multipliers"]?.arrayValue)
        #expect(!list.isEmpty)
        let worked: Int64 = list.compactMap { $0["worked"]?.intValue }.reduce(0, +)
        #expect(worked > 0)
        #expect(Int64(try #require(app.model.contest.score).multTotal) <= worked)
        #expect(list.allSatisfy { $0["needed"] == .null })
    }

    // MARK: - keys

    @Test func aBoundKeyReachesThePluginAndCanPassThrough() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.rawPlugin(app, manifest: #""permissions":["read"],"actions":[{"id":"cq","title":"CQ"}]"#,
                                          body: "IFS= read -r hello\necho '{\"type\":\"ready\"}'\n" + T.echoLoop)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        #expect(model.menuWindows.isEmpty)
        let combo: KeyCombo = try #require(KeyCombo.parse("Ctrl+Alt+P"))
        #expect(model.handleKey(combo, pressed: true) == nil)
        model.bindKey(plugin: "demo", action: "cq", key: "ctrl+alt+p")
        #expect(model.settings.keys["demo/cq"] == "Ctrl+Alt+P")
        // The press starts the (window-less) plugin and sends the key; the release only answers.
        #expect(model.handleKey(combo, pressed: true) == false)
        #expect(model.handleKey(combo, pressed: false) == false)
        let log: URL = dir.appendingPathComponent("in.log")
        await eventually("key delivered") { !T.lines(log).isEmpty }
        #expect(T.lines(log).compactMap(T.json).first?["type"] == .string("key"))
        #expect(T.lines(log).compactMap(T.json).first?["action"] == .string("cq"))
        model.setPassThrough(plugin: "demo", action: "cq", true)
        #expect(model.handleKey(combo, pressed: true) == true)
        await eventually("second key") { T.lines(log).count == 2 }
        await model.settleSettings()
        let saved = PluginSettings.load(dataDir: app.app.dataDir)
        #expect(saved.keys == ["demo/cq": "Ctrl+Alt+P"])
        #expect(saved.passThrough == ["demo/cq"])
        model.bindKey(plugin: "demo", action: "cq", key: nil)
        #expect(model.handleKey(combo, pressed: true) == nil)
        await model.shutdown()
    }

    /// The entry window's key flow asks the hook first: a bound key is consumed (or passed on).
    @Test func theEntryKeyFlowAsksThePluginHook() async throws {
        let app = try await PortedApp.make()
        let flow = EntryKeyFlow(entry: app.entry)
        let pressed = Box<[Bool]>([])
        let passOn = Box<Bool>(false)
        app.entry.pluginKeyHook = { combo, isPress in
            guard combo.keyCode == AwtKeyCodes.vkEscape, !combo.ctrl else { return nil }
            pressed.value.append(isPress)
            return passOn.value
        }
        app.entry.callChanged("DL1ABC")
        let down = MacKeyEvent(kind: .keyDown, keyCode: 0x35, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}")
        let up = MacKeyEvent(kind: .keyUp, keyCode: 0x35, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}")
        #expect(flow.process(down, target: .entry(.call)))
        #expect(flow.process(up, target: .entry(.call)))
        #expect(pressed.value == [true, false])
        #expect(app.entry.form.call == "DL1ABC")
        passOn.value = true
        _ = flow.process(down, target: .entry(.call))
        _ = flow.process(up, target: .entry(.call))
        #expect(app.entry.form.call == "")
    }

    // MARK: - docking and canvas

    @Test func dockingKeepsThePluginRunningAndIsRemembered() async throws {
        let app = try await IntegrationApp.make()
        try T.plugin(app, body: Self.logging)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("up") { T.shownText(model.session("demo")) == "up" }
        model.dock(Self.key)
        #expect(model.dockedKeys == [Self.key])
        #expect(!app.model.windows.isOpen(Self.key))
        // The window closing for the dock is not the user's close: the plugin runs on for the panel.
        model.windowClosed(Self.key)
        #expect(model.session("demo")?.phase == .running)
        await model.settleSettings()
        #expect(PluginSettings.load(dataDir: app.app.dataDir).docked == [Self.key])
        model.undock(Self.key)
        #expect(app.model.windows.isOpen(Self.key))
        #expect(model.dockedKeys.isEmpty)
        model.dock(Self.key)
        model.closeDocked(Self.key)
        #expect(model.session("demo")?.phase == .stopped)
        #expect(model.dockedKeys.isEmpty)
    }

    @Test func aCanvasClickSendsItsPoint() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try T.plugin(app, body: Self.logging)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("up") { T.shownText(model.session("demo")) == "up" }
        model.canvasClick(Self.key, target: "map", x: 12.34, y: 56.78)
        let log: URL = dir.appendingPathComponent("in.log")
        await eventually("click") { !T.lines(log).isEmpty }
        let click: PluginJSON = try #require(T.lines(log).first.flatMap(T.json))
        #expect(click["target"] == .string("map"))
        #expect(click["value"]?["x"]?.doubleValue == 12.3)
        #expect(click["value"]?["y"]?.doubleValue == 56.8)
        await model.shutdown()
    }
}
