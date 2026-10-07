import Foundation
import Testing
@testable import MCLCore

/// Window plugins, the acting part: actions in the manifest, the operator's settings (grants, keys, docking), the
/// canvas element and the text-command policy.
@Suite struct PluginStage2CoreTests {

    static func manifest(_ json: String) throws -> PluginManifest {
        try PluginManifest.parse(Array(json.utf8), directoryName: "demo")
    }

    @Test func actionsMakeAWindowOptional() throws {
        let manifest = try Self.manifest("""
            {"protocol":1,"permissions":["read","entry","rig"],"actions":[{"id":"cq","title":"CQ helper"},{"id":"x"}]}
            """)
        #expect(manifest.windows.isEmpty)
        #expect(manifest.actions == [PluginManifest.Action(id: "cq", title: "CQ helper"),
                                     PluginManifest.Action(id: "x", title: "x")])
        #expect(manifest.unsupportedPermissions.isEmpty)
        #expect(manifest.permissionsNeedingGrant == ["entry", "rig"])
        #expect(throws: ContestMessage.self) { try Self.manifest(#"{"protocol":1}"#) }
        #expect(throws: ContestMessage.self) {
            try Self.manifest(#"{"protocol":1,"actions":[{"id":"a"},{"id":"a"}]}"#)
        }
        #expect(throws: ContestMessage.self) { try Self.manifest(#"{"protocol":1,"actions":"a"}"#) }
        // cat and transmit stay unsupported in this stage.
        #expect(try Self.manifest(#"{"protocol":1,"permissions":["cat"],"actions":[{"id":"a"}]}"#)
            .unsupportedPermissions == ["cat"])
    }

    @Test func grantsDecideTheEffectivePermissions() throws {
        let manifest = try Self.manifest(
            #"{"protocol":1,"permissions":["read","ui","entry","spots","spots.send"],"windows":[{"id":"main"}]}"#)
        var settings = PluginSettings()
        #expect(settings.needsConsent(manifest))
        #expect(settings.effectivePermissions(manifest) == ["read", "ui"])
        // `spots.send` without `spots` is not kept.
        settings.setGranted("demo", ["entry", "spots.send", "ui"])
        #expect(settings.grants["demo"] == ["entry"])
        #expect(!settings.needsConsent(manifest))
        #expect(settings.effectivePermissions(manifest) == ["read", "ui", "entry"])
        settings.setGranted("demo", ["spots", "spots.send"])
        #expect(settings.effectivePermissions(manifest) == ["read", "ui", "spots", "spots.send"])
        settings.setGranted("demo", [])
        #expect(settings.grants["demo"] == nil)
        #expect(settings.decided == ["demo"])
        // A plugin asking only for read and ui never needs consent.
        #expect(!PluginSettings().needsConsent(try Self.manifest(#"{"protocol":1,"windows":[{"id":"m"}]}"#)))
    }

    @Test func settingsRoundTripThroughTheFile() throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        let url = URL(fileURLWithPath: dir)
        #expect(PluginSettings.load(dataDir: url) == PluginSettings())
        var settings = PluginSettings()
        settings.setGranted("a", ["rig"])
        settings.keys["a/cq"] = "Ctrl+Alt+P"
        settings.passThrough = ["a/cq"]
        settings.docked = ["plugin:a/main"]
        try settings.save(dataDir: url)
        #expect(PluginSettings.load(dataDir: url) == settings)
        // Missing fields read as empty; a broken file as empty settings.
        ScriptingFixture.write(dir + "/" + PluginSettings.fileName, Array(#"{"keys":{"a/b":"F5"}}"#.utf8))
        #expect(PluginSettings.load(dataDir: url).keys == ["a/b": "F5"])
        ScriptingFixture.write(dir + "/" + PluginSettings.fileName, Array("{".utf8))
        #expect(PluginSettings.load(dataDir: url) == PluginSettings())
    }

    @Test func canvasShapesAreRead() throws {
        let content = try PluginUIContent.parse(try PluginJSON.parse("""
            {"elements":[{"type":"canvas","id":"map","width":200,"height":100,"label":"Band activity","shapes":[
              {"shape":"line","x1":0,"y1":0,"x2":10,"y2":10,"style":"mult","lineWidth":2},
              {"shape":"rect","x":1,"y":2,"w":3,"h":4,"fill":true},
              {"shape":"circle","cx":5,"cy":5,"r":-3,"style":"dupe"},
              {"shape":"path","points":[[0,0],[1,1],[2,0]],"closed":true},
              {"shape":"text","x":4,"y":4,"text":"20m","size":200},
              {"shape":"star"},{"shape":"line","x1":"a"}]}]}
            """))
        guard case .canvas(let canvas) = content.elements.first else {
            Issue.record("no canvas")
            return
        }
        #expect(canvas.id == "map")
        #expect(canvas.width == 200 && canvas.height == 100)
        #expect(canvas.label == "Band activity")
        #expect(canvas.shapes.count == 5)
        #expect(canvas.shapes[0] == .line(from: PluginUIPoint(x: 0, y: 0), to: PluginUIPoint(x: 10, y: 10), style: .mult,
                                          lineWidth: 2))
        #expect(canvas.shapes[2] == .circle(center: PluginUIPoint(x: 5, y: 5), radius: 3, style: .dupe, fill: false,
                                            lineWidth: 1))
        #expect(canvas.shapes[4] == .text("20m", at: PluginUIPoint(x: 4, y: 4), style: .normal, size: 72))
        #expect(content.warnings == ["a canvas shape that cannot be read was left out"])
    }

    @Test func canvasLimits() throws {
        let shapes: String = (0...PluginUICanvas.maxShapes).map { _ in
            #"{"shape":"rect","x":0,"y":0,"w":1,"h":1}"#
        }.joined(separator: ",")
        let content = try PluginUIContent.parse(try PluginJSON.parse(
            #"{"elements":[{"type":"canvas","width":99999,"height":-5,"shapes":["# + shapes + "]}]}"))
        guard case .canvas(let canvas) = content.elements.first else {
            Issue.record("no canvas")
            return
        }
        #expect(canvas.shapes.count == PluginUICanvas.maxShapes)
        #expect(canvas.width == PluginUICanvas.maxSide)
        #expect(canvas.height == 1)
        #expect(content.warnings.count == 1)
    }

    @Test func commandsThatTransmitOrDestroyAreRefused() throws {
        func refusal(_ text: String) throws -> String? {
            let command: CallFieldCommand = try #require(try CallFieldCommands.parse(text, currentFreqHz: 14_025_000))
            return PluginCommandPolicy.refusal(command)
        }
        for refused in ["RPT", "ESM", "SPOTME", "SCRIPT run", "CLEARLOG", "CLEARLOGNOW", "EXIT", "EXITNOW", "RESET"] {
            #expect(try refusal(refused) != nil, "\(refused) must be refused")
        }
        for allowed in ["14030", "CW", "NOESM", "NORPT", "SPLIT", "NOSPLIT", "RIT 100", "POSTCONTEST", "REOPEN"] {
            #expect(try refusal(allowed) == nil, "\(allowed) must be allowed")
        }
    }

    @Test func theKeyMessage() throws {
        let key = try PluginJSON.parse(PluginOutbound.key(action: "cq"))
        #expect(key == .object(["type": .string("key"), "action": .string("cq"), "phase": .string("press")]))
    }
}
