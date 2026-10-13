import Foundation
import MCLCore

/// What the console's styled lines depend on besides the log.
struct ConsoleCacheKey: Equatable {
    let filter: SpotFilter
    let analysisRevision: Int
}

/// The N1MM+ Telnet window's own options and buttons: the node software (detected from the greeting or chosen), auto
/// logon when the window opens, showing the buttons, the band map's SH/DX count, the button macros `{WAIT}` and
/// `{CONN}`, saving and loading button sets, and the console's colour-coded lines.
extension DxClusterModel {

    // MARK: - options (applied and saved at once, like the spot filter)

    /// The software chosen in the window (`auto` = from the greeting).
    public var configuredSoftware: ClusterSoftware {
        ClusterSoftware.from(config.config.dxCluster.clusterSoftware)
    }

    /// What the main connection's greeting named.
    public var detectedSoftware: ClusterSoftware? {
        main.software
    }

    /// The software the commands MCL builds are formatted for.
    public var software: ClusterSoftware {
        ClusterSoftware.effective(configured: configuredSoftware, detected: detectedSoftware)
    }

    public func setSoftware(_ software: ClusterSoftware) {
        update(\.clusterSoftware, software.rawValue)
    }

    public var autoLogon: Bool {
        config.config.dxCluster.autoLogon
    }

    public func setAutoLogon(_ on: Bool) {
        update(\.autoLogon, on)
    }

    public var showButtons: Bool {
        config.config.dxCluster.showButtons
    }

    public func setShowButtons(_ on: Bool) {
        update(\.showButtons, on)
    }

    public var showDxCount: Int {
        config.config.dxCluster.showDxCount
    }

    public func setShowDxCount(_ count: Int) {
        update(\.showDxCount, ClusterCommandFormat.clampedCount(count))
    }

    private func update<Value: Equatable>(_ field: WritableKeyPath<DxClusterConfig, Value>, _ value: Value) {
        guard config.config.dxCluster[keyPath: field] != value else { return }
        config.config.dxCluster[keyPath: field] = value
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
    }

    // MARK: - commands MCL builds

    /// `SH/DX` with the configured count (and only `call`'s spots), formatted for the node.
    public func showDxCommand(call: String? = nil) -> String {
        ClusterCommandFormat.showDx(count: showDxCount, call: call, software: software)
    }

    // MARK: - auto logon

    /// The DX Cluster window opened: with auto logon on and nothing connected, connect to the selected favourite and
    /// log in (the favourite's login, as the parallel connections do).
    public func windowOpened() {
        guard !closed, autoLogon, !main.connected, !main.connecting, let fav = selectedFavorite else { return }
        connect(fav, autoLogin: true)
    }

    // MARK: - buttons

    /// A button press: its parts in order — commands, `{WAIT}` (5 s) and `{CONN} name`. Presses queue up behind a
    /// button that is still waiting.
    public func runButton(_ command: String) {
        guard !closed else { return }
        let steps: [ClusterButtonMacro.Step] = ClusterButtonMacro.steps(command)
        guard !steps.isEmpty else { return }
        if !steps.contains(.wait) && buttonsQueued == 0 {
            perform(steps)
            return
        }
        let previous: Task<Void, Never>? = buttonTask
        let wait: @Sendable (Int) async -> Void = buttonWait
        buttonsQueued += 1
        buttonTask = Task { [weak self] in
            await previous?.value
            for step in steps {
                if Task.isCancelled { break }
                if step == .wait {
                    await wait(ClusterButtonMacro.waitMilliseconds)
                } else {
                    self?.perform([step])
                }
            }
            self?.buttonsQueued -= 1
        }
    }

    private func perform(_ steps: [ClusterButtonMacro.Step]) {
        guard !closed else { return }
        for step in steps {
            switch step {
            case .send(let command): send(command)
            case .connect(let name): connectNamed(name)
            case .wait: break
            }
        }
    }

    /// `{CONN} name`: the favourite of that name becomes the main connection (the current one is closed first) and
    /// logs in; an unknown name only says so in the status line.
    public func connectNamed(_ name: String) {
        guard !closed else { return }
        guard let fav = ClusterButtonMacro.favorite(named: name, in: favorites) else {
            status.show("{CONN}: cluster %s není v seznamu", .string(name))
            return
        }
        if main.currentFavorite?.connectionKey == fav.connectionKey && main.connected { return }
        selection = ClusterTexts.favLabel(fav, translator: language.translator)
        config.config.dxCluster.lastFavorite = fav.name
        config.saveSilently()
        let wasConnected: Bool = main.connected || main.connecting
        mainLane.run { session in
            if wasConnected {
                try session.disconnect(DxClusterSession.disconnectedText)
            }
            try session.connect(fav, autoLogin: true)
        }
    }

    // MARK: - button sets (N1MM saves and loads them as files)

    /// The ten buttons as the text of a button file.
    public var buttonsFileText: String {
        ClusterButtonFile.encode(macros)
    }

    /// Loads a button file; `false` (status) when it has no button.
    @discardableResult
    public func loadButtons(_ text: String) -> Bool {
        guard let commands = ClusterButtonFile.decode(text) else {
            status.show("Soubor neobsahuje žádné tlačítko")
            return false
        }
        config.config.dxCluster.commands = commands
        config.save(failureKey: ClusterTexts.macroSaveFailedKey)
        return true
    }

    // MARK: - console

    /// The traffic log's lines styled for the console: spot lines tinted by mode and greyed when the filter hides
    /// them. Lines already styled under the same filter and analysis are reused.
    public func consoleLines(analyzer: SpotAnalyzer, analysisRevision: Int) -> [ConsoleLine] {
        let filter: SpotFilter = spotFilter
        let key = ConsoleCacheKey(filter: filter, analysisRevision: analysisRevision)
        let log: [String] = self.log.snapshot()
        var cache: [String: ConsoleLine] = consoleCache?.key == key ? consoleCache?.lines ?? [:] : [:]
        var fresh: [String: ConsoleLine] = [:]
        var out: [ConsoleLine] = []
        out.reserveCapacity(log.count)
        for text in log {
            let line: ConsoleLine
            if let known = cache[text] {
                line = known
            } else {
                line = ConsoleLine.lines([text], filter: filter, analyzer: analyzer)[0]
                cache[text] = line
            }
            fresh[text] = line
            out.append(line)
        }
        consoleCache = (key, fresh)
        return out
    }
}
