import Foundation
import MCLCore

/// The Entry window's view options (N1MM Entry window → right click) and what its parts show about the typed call:
/// the band buttons' and the call field's colours (`CallBandStatus`) and the bearing line.
extension EntryModel {

    // MARK: - the right-click menu

    public func isShown(_ section: EntrySection) -> Bool {
        !config.config.entryHiddenSections.contains(section.rawValue)
    }

    public func setShown(_ section: EntrySection, _ on: Bool) {
        var hidden: [String] = config.config.entryHiddenSections.filter { $0 != section.rawValue }
        if !on {
            hidden.append(section.rawValue)
        }
        config.config.entryHiddenSections = EntrySection.allCases.map(\.rawValue).filter { hidden.contains($0) }
        config.saveSilently()
        updateBandStatuses()
    }

    /// N1MM „Show GMT Time".
    public var showsUtcClock: Bool {
        get { config.config.entryShowUtcClock }
        set {
            config.config.entryShowUtcClock = newValue
            config.saveSilently()
        }
    }

    /// N1MM „Band Button Left Click Enabled".
    public var bandButtonsClick: Bool {
        get { config.config.entryBandButtonsClick }
        set {
            config.config.entryBandButtonsClick = newValue
            config.saveSilently()
        }
    }

    /// N1MM „Show User Information" (the call history line, `callHistoryShowUserInfo` of Settings → Contest).
    public var showsUserInformation: Bool {
        get { config.config.callHistoryShowUserInfo }
        set {
            config.config.callHistoryShowUserInfo = newValue
            config.saveSilently()
        }
    }

    public func showsBand(_ band: Band) -> Bool {
        !config.config.entryHiddenBands.contains(band.adif)
    }

    public func setShowsBand(_ band: Band, _ on: Bool) {
        var hidden: [String] = config.config.entryHiddenBands.filter { $0 != band.adif }
        if !on {
            hidden.append(band.adif)
        }
        config.config.entryHiddenBands = Band.allCases.map(\.adif).filter { hidden.contains($0) }
        config.saveSilently()
    }

    // MARK: - the typed call

    /// The typed call's status in the contest on the window's band (the call field's colour); `nil` outside a
    /// contest or without a call.
    public var callStatus: CallBandStatus? {
        guard contest.isActive, !KotlinStrings.isBlank(form.call), quickEdit == nil,
              let preview = contest.lastPreview else { return nil }
        return CallBandStatus(preview)
    }

    /// The typed call's status on each band of the band buttons (their colours), kept by `updatePreview`.
    func updateBandStatuses() {
        let wanted: Bool = contest.isActive && !KotlinStrings.isBlank(form.call) && quickEdit == nil
            && isShown(.bandButtons)
        let exchange: String = form.contestExchange.entries.map { ($0.0 ?? "") + "=" + ($0.1 ?? "") }
            .joined(separator: "\u{1}")
        let key: String? = wanted ? [form.call, form.mode.rawValue, exchange, contest.activeId ?? "",
                                     String(logbook.revision), previewQth ?? ""].joined(separator: "\u{2}") : nil
        guard key != bandStatusKey || (key == nil && !bandStatuses.isEmpty) else { return }
        bandStatusKey = key
        var next: [Band: CallBandStatus] = [:]
        if wanted {
            let mode: String = form.mode.rawValue
            let at: Date = now()
            for row in EntryGrid.of(contest).rows {
                if let result = contest.runtime.peek(call: form.call, band: row.band.adif, mode: mode,
                                                     exchange: form.contestExchange, ownQth: previewQth, at: at) {
                    next[row.band] = CallBandStatus(result)
                }
            }
        }
        if next != bandStatuses {
            bandStatuses = next
        }
    }

    /// N1MM's bearing line: short and long path beam headings and the short-path distance to the typed call's
    /// country; `nil` without a call, a country or the station's position.
    public var bearingLine: String? {
        let call: String = InfoLines.normalizedCall(form.call)
        guard !call.isEmpty else { return nil }
        let station = config.config.station
        let position = InfoLines.position(latitude: station.latitude, longitude: station.longitude)
        let info: CallsignInfo? = try? InfoLines.callsignInfo(typedCall: call, lookup: contest.runtime.dxccLookup,
                                                              myLat: position.lat, myLon: position.lon,
                                                              now: JavaInstant(date: now()))
        return InfoLines.bearing(info)
    }
}
