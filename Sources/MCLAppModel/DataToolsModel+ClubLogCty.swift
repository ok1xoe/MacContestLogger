import Foundation
import MCLCore
import Observation

/// DXCC from Club Log's `cty.xml`: the check at start-up (at most once a day, only with an API key and the switch on),
/// the manual update (menu and Settings), and the reload of the contest data when a new copy arrives or the switch
/// changes. The download runs in the background (the file work on `BlockingQueue`); nothing ever waits for it. A
/// failure keeps the last cached copy; without a copy the local DXCC data stay the source.
extension DataToolsModel {

    /// The check at start-up: quiet unless something was downloaded or failed.
    public func startClubLogDxccCheck() {
        observeClubLogSwitch()
        runClubLogDxcc(.startup)
    }

    /// „Aktualizovat DXCC z Club Logu" (the Database menu and Settings → Score Reporting).
    public func updateClubLogDxcc() {
        runClubLogDxcc(.manual)
    }

    private func runClubLogDxcc(_ trigger: ClubLogCtyCache.Trigger) {
        let previous: Task<Void, Never>? = clubLogChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.clubLogDxcc(trigger)
        }
        clubLogChain = task
        track {
            await task.value
        }
    }

    private func clubLogDxcc(_ trigger: ClubLogCtyCache.Trigger) async {
        let cache = ClubLogCtyCache(dataDir: dataDir)
        let manual: Bool = trigger == .manual
        defer { clubLogCtyRunning = false }
        clubLogCtyRunning = true
        if !manual {
            await refreshClubLogCtyStatus(cache)
            guard config.config.clubLog.ctyEnabled else { return }
        }
        guard let fetcher = clubLogFetcher else {
            if manual {
                report(ContestMessage("Síť je vypnutá (MCL_INERT_NETWORK)"), message: false)
            }
            return
        }
        let apiKey: String = config.config.clubLog.apiKey
        let at: Date = now()
        let url: URL
        do {
            url = try await BlockingQueue.run {
                try cache.begin(trigger, apiKey: apiKey, now: at)
            }
        } catch let failure as ClubLogCtyCache.Failure {
            // At start-up a missing key or a recent download is the normal case — nothing is shown.
            if manual {
                report(Self.text(failure), message: false)
            }
            return
        } catch {
            report(Self.failed(ContestMessage.verbatim(ErrorText.message(error))), message: true)
            return
        }
        if manual {
            status.show("Stahuji DXCC z Club Logu…")
        }
        let response: (status: Int, data: Data)
        do {
            response = try await fetcher.fetch(url)
        } catch {
            let text: String = ClubLogCtyCache.transportText(error, apiKey: apiKey)
            report(Self.failed(Self.text(.transport(text))), message: true)
            return
        }
        let accepted: Result<ClubLogCtyCache.Summary, ClubLogCtyCache.Failure>
        do {
            accepted = try await BlockingQueue.run {
                do throws(ClubLogCtyCache.Failure) {
                    return .success(try cache.accept(status: response.status, body: response.data, now: at).1)
                } catch {
                    return .failure(error)
                }
            }
        } catch {
            accepted = .failure(.write(ErrorText.message(error)))
        }
        switch accepted {
        case .failure(let failure):
            report(Self.failed(Self.text(failure)), message: true)
        case .success(let summary):
            if config.config.clubLog.ctyEnabled {
                await contest.reloadContestData()
            }
            report(ContestMessage("DXCC z Club Logu aktualizováno: %s entit, %s výjimek, %s prefixů",
                                  .int(summary.entities), .int(summary.exceptions), .int(summary.prefixes)),
                   message: true)
        }
        await refreshClubLogCtyStatus(cache)
    }

    /// The status line, and the Info window's messages for a result worth keeping.
    private func report(_ text: ContestMessage, message: Bool) {
        status.show(text)
        if message {
            messages.add(language.text(text), at: now())
        }
        clubLogCtyResult = text
    }

    /// The Settings line from the cache state.
    func refreshClubLogCtyStatus(_ cache: ClubLogCtyCache? = nil) async {
        let store: ClubLogCtyCache = cache ?? ClubLogCtyCache(dataDir: dataDir)
        let state: ClubLogCtyCache.State = (try? await BlockingQueue.run { store.readState() })
            ?? ClubLogCtyCache.State()
        if let downloaded = state.downloadedAt {
            clubLogCtyStatus = ContestMessage("Poslední stažení cty.xml: %s", .string(Self.utc(downloaded)))
        } else {
            clubLogCtyStatus = ContestMessage("cty.xml z Club Logu zatím nebyl stažen")
        }
    }

    /// Re-reads the contest data when the Club Log switch changes in Settings (the DXCC source changes).
    private func observeClubLogSwitch() {
        let current: Bool = config.config.clubLog.ctyEnabled
        if observedCtyEnabled == nil {
            observedCtyEnabled = current
        }
        withObservationTracking {
            _ = config.config.clubLog.ctyEnabled
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                let now: Bool = self.config.config.clubLog.ctyEnabled
                if now != self.observedCtyEnabled {
                    self.observedCtyEnabled = now
                    self.track { [weak self] in
                        await self?.contest.reloadContestData()
                    }
                }
                self.observeClubLogSwitch()
            }
        }
    }

    // MARK: - texts

    nonisolated static func failed(_ reason: ContestMessage) -> ContestMessage {
        ContestMessage("Aktualizace DXCC z Club Logu selhala: %s (zůstávají dosavadní data)",
                       parts: [.message(reason)])
    }

    nonisolated static func text(_ failure: ClubLogCtyCache.Failure) -> ContestMessage {
        switch failure {
        case .noKey:
            return ContestMessage("Club Log: chybí API klíč (Nastavení → Score Reporting)")
        case .notDue(let next):
            return ContestMessage("DXCC z Club Logu je aktuální, další stažení je možné po %s",
                                  .string(utc(next)))
        case .forbidden:
            return ContestMessage("Club Log odmítl API klíč (HTTP 403)")
        case .http(let code):
            return ContestMessage.verbatim("HTTP " + String(code))
        case .transport(let text):
            return ContestMessage.verbatim(text)
        case .gzip:
            return ContestMessage("poškozená data (gzip)")
        case .parse(let reason):
            return ContestMessage(reason)
        case .write(let text):
            return ContestMessage("nelze uložit: %s", .string(text))
        }
    }

    nonisolated static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}
