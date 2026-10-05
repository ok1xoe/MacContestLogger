/// Change predicates of the draft against the **old** configuration (`ui/configurer/ConfigurerDraft.kt:202-246,
/// 319-327`), evaluated before `applied(to:now:)`. Texts are compared after Kotlin `trim()` exactly where Kotlin
/// trims, and by UTF-16 units (Kotlin `!=`). The unused `dxClusterOptionsDiffer`/`dxClusterFavoritesDiffer` are
/// dead code in Kotlin and are not carried over.
extension ConfigurerDraft {

    /// `rigDiffers`: any rig field; `device` and `host` trimmed, port `trim().toIntOrNull() ?: rig.port`.
    public func rigDiffers(_ rig: RigConfig) -> Bool {
        if rigMode != rig.mode || rigModel != rig.model || Self.differs(rigModelLabel, rig.modelLabel) {
            return true
        }
        if Self.differs(Self.trim(device), rig.device) || baud != rig.baud { return true }
        if dataBits != rig.dataBits || stopBits != rig.stopBits || parity != rig.parity { return true }
        if flow != rig.flowControl || dtr != rig.dtr || rts != rig.rts { return true }
        if Self.differs(Self.trim(host), rig.host) { return true }
        let port: Int = Self.trimmedInt(rigPort) ?? rig.port
        return port != rig.port
    }

    /// `clusterDiffers`: enabled, broker, port (`toIntOrNull() ?: 1883`, untrimmed), user, password, station id,
    /// TLS, sharing of spots. `interlock`, `serialServer`, `stationType` and `ruleEnforcement` are **not** compared
    /// (Kotlin) — changing only those does not restart the cluster connection.
    public func clusterDiffers(_ cluster: ClusterConfig) -> Bool {
        if clusterEnabled != cluster.enabled || Self.differs(Self.trim(brokerHost), cluster.brokerHost) {
            return true
        }
        let port: Int = ConfigurerRows.toIntOrNull(clusterPort) ?? 1883
        if port != cluster.port || Self.differs(username, cluster.username) { return true }
        if Self.differs(password, cluster.password) || Self.differs(Self.trim(stationId), cluster.stationId) {
            return true
        }
        return tls != cluster.tls || shareSpots != cluster.shareSpots
    }

    /// `scoringStationDiffers`: the station fields the score depends on — call, locator, CQ and ITU zones, rover
    /// QTH (all trimmed).
    public func scoringStationDiffers(_ station: StationConfig) -> Bool {
        Self.differs(Self.trim(call), station.call) || Self.differs(Self.trim(grid), station.gridSquare)
            || Self.differs(Self.trim(cqZone), station.cqZone) || Self.differs(Self.trim(ituZone), station.ituZone)
            || Self.differs(Self.trim(roverQth), station.roverQth)
    }

    /// `contestDirDiffers`: `contestDataDir.trim() != (config.contestDataDir ?: default)`.
    public func contestDirDiffers(_ config: AppConfig, defaultDir: String) -> Bool {
        Self.differs(Self.trim(contestDataDir), config.contestDataDir ?? defaultDir)
    }

    /// `broadcastDiffers`: the four switches and their trimmed targets.
    public func broadcastDiffers(_ broadcast: BroadcastConfig) -> Bool {
        if bcContactsEnabled != broadcast.contactsEnabled
            || Self.differs(Self.trim(bcContactsTargets), broadcast.contactsTargets) {
            return true
        }
        if bcRadioEnabled != broadcast.radioEnabled || Self.differs(Self.trim(bcRadioTargets), broadcast.radioTargets) {
            return true
        }
        if bcScoreEnabled != broadcast.scoreEnabled || Self.differs(Self.trim(bcScoreTargets), broadcast.scoreTargets) {
            return true
        }
        return bcAppInfoEnabled != broadcast.appInfoEnabled
            || Self.differs(Self.trim(bcAppInfoTargets), broadcast.appInfoTargets)
    }

    /// `wsjtxDiffers`.
    public func wsjtxDiffers(_ wsjtx: WsjtxConfig) -> Bool {
        if wxReceiveEnabled != wsjtx.receiveEnabled || Self.differs(Self.trim(wxReceiveBind), wsjtx.receiveBind) {
            return true
        }
        return wxSendEnabled != wsjtx.sendEnabled || Self.differs(Self.trim(wxSendTargets), wsjtx.sendTargets)
    }

    /// `n1mmDiffers`.
    public func n1mmDiffers(_ n1mm: N1mmRecvConfig) -> Bool {
        nrReceiveEnabled != n1mm.receiveEnabled || Self.differs(Self.trim(nrReceiveBind), n1mm.receiveBind)
    }

    /// `adifUdpDiffers`.
    public func adifUdpDiffers(_ adif: AdifUdpConfig) -> Bool {
        auReceiveEnabled != adif.receiveEnabled || Self.differs(Self.trim(auReceiveBind), adif.receiveBind)
    }

    /// Kotlin `String !=` (UTF-16 units, no canonical equivalence).
    static func differs(_ left: String, _ right: String) -> Bool {
        !left.utf16.elementsEqual(right.utf16)
    }
}
