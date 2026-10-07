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
        // A permission no version knows stays unsupported.
        #expect(try Self.manifest(#"{"protocol":1,"permissions":["network"],"actions":[{"id":"a"}]}"#)
            .unsupportedPermissions == ["network"])
    }

    @Test func grantsDecideTheEffectivePermissions() throws {
        let manifest = try Self.manifest(
            #"{"protocol":1,"permissions":["read","ui","entry","spots","spots.send"],"windows":[{"id":"main"}]}"#)
        var settings = PluginSettings()
        #expect(settings.needsConsent(manifest))
        #expect(settings.undecided(manifest) == ["entry", "spots", "spots.send"])
        #expect(settings.effectivePermissions(manifest) == ["read", "ui"])
        // `spots.send` without `spots` is not kept; a permission the manifest does not ask for never is.
        settings.decide(manifest, granted: ["entry", "spots.send", "ui", "transmit"], decided: settings.undecided(manifest))
        #expect(settings.grants[PluginSettings.identity(manifest)] == ["entry"])
        #expect(!settings.needsConsent(manifest))
        #expect(settings.effectivePermissions(manifest) == ["read", "ui", "entry"])
        settings.decide(manifest, granted: ["spots", "spots.send"], decided: manifest.permissionsNeedingGrant)
        #expect(settings.effectivePermissions(manifest) == ["read", "ui", "spots", "spots.send"])
        settings.decide(manifest, granted: [], decided: manifest.permissionsNeedingGrant)
        #expect(settings.grants[PluginSettings.identity(manifest)] == nil)
        // A plugin asking only for read and ui never needs consent.
        #expect(!PluginSettings().needsConsent(try Self.manifest(#"{"protocol":1,"windows":[{"id":"m"}]}"#)))
        #expect(PluginManifest.offByDefault.contains("spots.send"))
    }

    /// A manifest that asks for more later is asked again — only for the new permissions; the decided ones stay.
    @Test func aGrowingManifestIsAskedAgainForTheNewOnes() throws {
        let first = try Self.manifest(#"{"protocol":1,"name":"Helper","permissions":["entry"],"windows":[{"id":"m"}]}"#)
        var settings = PluginSettings()
        settings.decide(first, granted: ["entry"], decided: ["entry"])
        let grown = try Self.manifest(
            #"{"protocol":1,"name":"Helper","permissions":["entry","rig"],"windows":[{"id":"m"}]}"#)
        #expect(settings.needsConsent(grown))
        #expect(settings.undecided(grown) == ["rig"])
        #expect(settings.effectivePermissions(grown) == ["entry"])
        settings.decide(grown, granted: [], decided: ["rig"])
        #expect(!settings.needsConsent(grown))
        #expect(settings.effectivePermissions(grown) == ["entry"])
    }

    /// Another plugin put into the same directory (another manifest name) inherits nothing.
    @Test func grantsBelongToTheDirectoryAndTheName() throws {
        let original = try Self.manifest(#"{"protocol":1,"name":"Helper","permissions":["entry"],"windows":[{"id":"m"}]}"#)
        var settings = PluginSettings()
        settings.decide(original, granted: ["entry"], decided: ["entry"])
        let other = try Self.manifest(#"{"protocol":1,"name":"Other","permissions":["entry"],"windows":[{"id":"m"}]}"#)
        #expect(settings.effectivePermissions(other) == [])
        #expect(settings.needsConsent(other))
    }

    @Test func settingsRoundTripThroughTheFile() throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        let url = URL(fileURLWithPath: dir)
        #expect(PluginSettings.load(dataDir: url) == PluginSettings())
        var settings = PluginSettings()
        settings.decide(try Self.manifest(#"{"protocol":1,"permissions":["rig"],"actions":[{"id":"cq"}]}"#),
                        granted: ["rig"], decided: ["rig"])
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

    /// Every command of `CallFieldCommand` with the decision the policy must make. `decided(_:)` is an exhaustive
    /// switch: a new command does not compile until it is added here (and to the policy).
    static func expectAllowed(_ command: CallFieldCommand) -> Bool {
        switch command {
        case .qsy, .otherVfo, .split, .splitOff, .rit, .swapVfo, .changeMode, .version, .esmOff, .rescore:
            return true
        case .toggle(let setting, let on):
            switch setting {
            case .cqRepeat: return !on
            case .workDupes: return true
            case .autoReload, .postContest: return false
            }
        case .appAction(let action):
            switch action {
            case .debugCat, .reopen: return true
            case .broadcastLog, .exit, .exitNow, .wipeLogNow, .closeContest, .newContest, .openContest, .copyLog,
                 .reload, .resetInterfaces, .loadBeacons, .logout:
                return false
            }
        case .runScript, .login, .wipeLog, .exportAdif, .exportCabrillo, .importLog, .esmOn, .autoRunSp, .setTour,
             .tourOff, .bonusStations, .roverQth, .countyLine, .countyLineOff, .spotMe, .cutNumbers, .openSettingsTab,
             .openSetup, .networkOn, .networkOff, .invalid:
            return false
        }
    }

    static let everyCommand: [CallFieldCommand] = [
        .qsy(freqHz: 14_025_000), .otherVfo(freqHz: 14_030_000), .split(txFreqHz: 14_030_000), .splitOff,
        .runScript(name: "x"), .rit(offsetHz: 100), .swapVfo, .changeMode(mode: .cw), .login(operator: "OK1XYZ"),
        .wipeLog, .version, .exportAdif, .exportCabrillo, .importLog, .esmOn, .esmOff, .autoRunSp(enabled: true),
        .setTour(params: "x"), .tourOff, .bonusStations(calls: "x"), .roverQth(county: "x"), .countyLine(counties: "x"),
        .countyLineOff, .spotMe(comment: ""), .cutNumbers(style: nil), .openSettingsTab(tabKey: "keys"), .rescore,
        .openSetup, .networkOn, .networkOff, .invalid(message: "x"),
    ] + CallFieldCommand.Action.allCases.map { .appAction(action: $0) }
        + CallFieldCommand.Setting.allCases.flatMap { [.toggle(setting: $0, on: true), .toggle(setting: $0, on: false)] }

    @Test func theCommandPolicyDecidesEveryCommand() {
        for command in Self.everyCommand {
            #expect((PluginCommandPolicy.refusal(command) == nil) == Self.expectAllowed(command), "\(command)")
        }
        // Every case is in the list (the switch above is exhaustive; this checks the samples cover it).
        #expect(Self.everyCommand.count == 31 + CallFieldCommand.Action.allCases.count
                    + 2 * CallFieldCommand.Setting.allCases.count)
    }

    @Test func commandsThatTransmitOrDestroyAreRefusedFromText() throws {
        func refusal(_ text: String) throws -> String? {
            let command: CallFieldCommand = try #require(try CallFieldCommands.parse(text, currentFreqHz: 14_025_000))
            return PluginCommandPolicy.refusal(command)
        }
        for refused in ["RPT", "ESM", "SPOTME", "SCRIPT run", "CLEARLOG", "CLEARLOGNOW", "EXIT", "EXITNOW", "RESET",
                        "POSTCONTEST", "OPOFF"] {
            #expect(try refusal(refused) != nil, "\(refused) must be refused")
        }
        for allowed in ["14030", "CW", "NOESM", "NORPT", "SPLIT", "NOSPLIT", "RIT 100", "REOPEN"] {
            #expect(try refusal(allowed) == nil, "\(allowed) must be allowed")
        }
    }

    @Test func canvasShapesCountAcrossTheContent() throws {
        let shapes: String = (0..<PluginUICanvas.maxShapes).map { _ in #"{"shape":"rect","x":0,"y":0,"w":1,"h":1}"# }
            .joined(separator: ",")
        let canvas: String = #"{"type":"canvas","shapes":["# + shapes + "]}"
        let content = try PluginUIContent.parse(try PluginJSON.parse(
            "{\"elements\":[" + Array(repeating: canvas, count: 3).joined(separator: ",") + "]}"))
        let drawn: Int = content.elements.reduce(0) { total, element in
            if case .canvas(let canvas) = element { return total + canvas.shapes.count }
            return total
        }
        #expect(drawn == PluginUIContent.maxShapesTotal)
        #expect(content.warnings.count == 1)
    }

    @Test func theKeyMessage() throws {
        let key = try PluginJSON.parse(PluginOutbound.key(action: "cq"))
        #expect(key == .object(["type": .string("key"), "action": .string("cq"), "phase": .string("press")]))
    }
}
