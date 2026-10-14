import Foundation
import MCLCore

/// N1MM function key files (`.mc`): the contest's associated files (Contest Setup → Associated Files) and the
/// separate files of each operator (Configurer → Other).
///
/// The configuration always holds the messages in use. A contest with an associated file of a set loads it when it
/// opens, and a change of that set (Settings) is written back to the file, as N1MM's editor saves to the file in its
/// title bar. With separate files per operator, an operator other than the station call works with a copy made from
/// the station's (master) messages when they first sign on (Ctrl+O / OPON); the messages of whoever signs off are
/// kept in their file under `FunctionKeys/` of the data directory, and the master goes back when the station call
/// signs on again.
@Observable @MainActor
public final class FunctionKeyFilesModel {

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let dataDir: URL
    /// The operator whose messages the configuration holds.
    public private(set) var owner: String
    /// The messages last loaded or written, per set: a commit that changes a set writes it back.
    @ObservationIgnored private var synced: [FunctionKeyKind: FunctionKeySet] = [:]

    init(config: ConfigModel, contest: ContestModel, operating: OperatingModel, status: StatusModel, dataDir: URL) {
        self.config = config
        self.contest = contest
        self.operating = operating
        self.status = status
        self.dataDir = dataDir
        owner = operating.operatorCall
        markSynced()
        watchOperator()
        watchRevision()
    }

    // MARK: - files

    /// The parsed file, `nil` = unreadable, too big (64 KB) or without a message.
    public nonisolated static func read(_ url: URL) -> FunctionKeySet? {
        guard let data = try? Data(contentsOf: url), data.count <= 65_536 else { return nil }
        let text: String = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return McFunctionKeys.parse(text)
    }

    /// Writes the set as an N1MM `.mc` file; `false` = the write failed.
    @discardableResult
    public nonisolated static func write(_ keys: FunctionKeySet, kind: FunctionKeyKind, to url: URL) -> Bool {
        let text: String = McFunctionKeys.format(keys, title: "MacContestLogger " + kind.rawValue + " function keys")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The clipboard text of a set (N1MM „Copy these Messages to the Clipboard").
    public static func clipboardText(_ keys: FunctionKeySet, kind: FunctionKeyKind) -> String {
        McFunctionKeys.format(keys, title: "MacContestLogger " + kind.rawValue + " function keys")
    }

    /// The active contest's associated file of a set, `nil` = none.
    public func associatedFile(_ kind: FunctionKeyKind) -> String? {
        guard let path = contest.activeSetup?.functionKeyFiles[kind.rawValue],
              !KotlinStrings.isBlank(path) else { return nil }
        return KotlinStrings.trim(path)
    }

    /// N1MM „Import and Assign a Different Function Key (.MC) file to this Contest" (and „Save … to a Different
    /// filename"): the set's file of the active contest; `nil` removes it. `false` = no contest or not saved.
    @discardableResult
    public func associate(_ kind: FunctionKeyKind, path: String?) async -> Bool {
        let value: String? = path.map(KotlinStrings.trim).flatMap { $0.isEmpty ? nil : $0 }
        let saved: Bool = await contest.updateSetup { setup in
            setup.functionKeyFiles[kind.rawValue] = value
        }
        if saved {
            synced[kind] = kind.messages(in: config.config)
        }
        return saved
    }

    // MARK: - contest

    /// The contest opened: each set with an associated file takes the file's messages (not while another operator
    /// than the station uses their own files — the master stays in its file).
    public func contestActivated() {
        guard !usesOperatorFile(owner) else {
            markSynced()
            return
        }
        var next: AppConfig = config.config
        var loaded: [String] = []
        for kind in FunctionKeyKind.allCases {
            guard let path = associatedFile(kind) else { continue }
            guard let keys = Self.read(URL(fileURLWithPath: path)) else {
                status.show("Soubor F-kláves %s nejde načíst", .string(path))
                continue
            }
            kind.set(keys, in: &next)
            loaded.append(kind.rawValue)
        }
        if next != config.config {
            config.config = next
            config.saveSilently()
            config.bumpRevision()
        }
        markSynced()
        if !loaded.isEmpty {
            status.show("F-klávesy závodu načteny: %s", .string(loaded.joined(separator: ", ")))
        }
    }

    // MARK: - operators

    /// The file of an operator's own messages.
    func operatorFile(_ call: String, _ kind: FunctionKeyKind) -> URL {
        let safe: String = call.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return dataDir.appendingPathComponent("FunctionKeys", isDirectory: true)
            .appendingPathComponent(safe + " " + kind.rawValue + ".mc")
    }

    /// The station call (the owner of the master messages).
    private var stationCall: String {
        KotlinStrings.uppercase(KotlinStrings.trim(config.config.station.call))
    }

    private func usesOperatorFile(_ call: String) -> Bool {
        config.config.functionKeysPerOperator && !call.isEmpty && call != stationCall
    }

    /// The master file of a set: the contest's associated one, otherwise the station's file under `FunctionKeys/`.
    private func masterFile(_ kind: FunctionKeyKind) -> URL {
        associatedFile(kind).map { URL(fileURLWithPath: $0) } ?? operatorFile(stationCall, kind)
    }

    private func file(of call: String, _ kind: FunctionKeyKind) -> URL {
        usesOperatorFile(call) ? operatorFile(call, kind) : masterFile(kind)
    }

    /// A new operator signed on: the messages in use are kept in the previous operator's file and the new operator's
    /// own ones (a copy of the master the first time) come in. Nothing happens without separate files.
    func operatorChanged() {
        let next: String = KotlinStrings.uppercase(KotlinStrings.trim(operating.operatorCall))
        let previous: String = owner
        guard next != previous else { return }
        owner = next
        guard config.config.functionKeysPerOperator,
              usesOperatorFile(previous) || usesOperatorFile(next) else { return }
        var updated: AppConfig = config.config
        for kind in FunctionKeyKind.allCases {
            Self.write(kind.messages(in: config.config), kind: kind, to: file(of: previous, kind))
            let own: URL = file(of: next, kind)
            let keys: FunctionKeySet? = Self.read(own) ?? Self.read(masterFile(kind))
            if let keys {
                kind.set(keys, in: &updated)
            }
        }
        if updated != config.config {
            config.config = updated
            config.saveSilently()
            config.bumpRevision()
        }
        markSynced()
        if usesOperatorFile(next) {
            status.show("F-klávesy operátora %s", .string(next))
        }
    }

    // MARK: - write back

    /// A Settings commit or a profile load changed a set: it goes to the file it came from (the contest's associated
    /// file or the operator's own file).
    func configCommitted() {
        for kind in FunctionKeyKind.allCases {
            let keys: FunctionKeySet = kind.messages(in: config.config)
            guard synced[kind] != keys else { continue }
            synced[kind] = keys
            let target: URL?
            if usesOperatorFile(owner) {
                target = operatorFile(owner, kind)
            } else {
                target = associatedFile(kind).map { URL(fileURLWithPath: $0) }
            }
            if let target, !Self.write(keys, kind: kind, to: target) {
                status.show("Soubor F-kláves %s nejde uložit", .string(target.path))
            }
        }
    }

    private func markSynced() {
        for kind in FunctionKeyKind.allCases {
            synced[kind] = kind.messages(in: config.config)
        }
    }

    private func watchOperator() {
        withObservationTracking {
            _ = operating.operatorCall
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.operatorChanged()
                self.watchOperator()
            }
        }
    }

    private func watchRevision() {
        withObservationTracking {
            _ = config.revision
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.configCommitted()
                self.watchRevision()
            }
        }
    }
}
