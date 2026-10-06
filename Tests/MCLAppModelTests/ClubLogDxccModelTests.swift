import Foundation
import MCLCore
import os
import Testing
@testable import MCLAppModel

/// DXCC from Club Log's `cty.xml` in the app: the start-up check (only with a key and the switch on, at most once a
/// day), the manual update (menu), the reload of the contest data onto the Club Log resolver, the fallback to the
/// local data and the texts. Every download is an in-memory fake; nothing reaches the network.
@MainActor @Suite struct ClubLogDxccModelTests {

    nonisolated static let xml: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <clublog date="2026-10-01T06:00:00+00:00" xmlns="https://clublog.org/cty/v1.2">
          <entities>
            <entity><adif>503</adif><name>CZECH REPUBLIC</name><prefix>OK</prefix><deleted>FALSE</deleted>
              <cqz>15</cqz><cont>EU</cont><long>14.50</long><lat>50.00</lat></entity>
            <entity><adif>230</adif><name>FEDERAL REPUBLIC OF GERMANY</name><prefix>DL</prefix>
              <deleted>FALSE</deleted><cqz>14</cqz><cont>EU</cont><long>10.00</long><lat>51.00</lat></entity>
          </entities>
          <exceptions>
            <exception record="1"><call>DL0CTY</call><entity>CZECH REPUBLIC</entity><adif>503</adif><cqz>15</cqz>
              <cont>EU</cont><start>2026-01-01T00:00:00+00:00</start></exception>
          </exceptions>
          <prefixes>
            <prefix record="2"><call>OK</call><entity>CZECH REPUBLIC</entity><adif>503</adif><cqz>15</cqz>
              <cont>EU</cont></prefix>
            <prefix record="3"><call>DL</call><entity>FEDERAL REPUBLIC OF GERMANY</entity><adif>230</adif>
              <cqz>14</cqz><cont>EU</cont></prefix>
          </prefixes>
          <invalid_operations/>
          <zone_exceptions/>
        </clublog>
        """

    nonisolated static let now: Date = Date(timeIntervalSince1970: 1_791_288_000) // 2026-10-06 12:00 UTC

    /// A fixed answer; counts the requests.
    final class Fetcher: DataFetcher, @unchecked Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        let status: Int
        let body: Data

        init(status: Int = 200, body: Data? = nil) throws {
            self.status = status
            self.body = try body ?? Gzip.compress(Data(ClubLogDxccModelTests.xml.utf8))
        }

        var requests: Int { count.withLock { $0 } }

        func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
            count.withLock { $0 += 1 }
            return (status, body)
        }
    }

    static func make(fetcher: Fetcher?, apiKey: String = "KEY", enabled: Bool = true,
                     state: ClubLogCtyCache.State? = nil) async throws -> TestApp {
        let app = try await TestApp.make(fixedNow: now, configure: { config, dataDir in
            config.clubLog.apiKey = apiKey
            config.clubLog.ctyEnabled = enabled
            if let state {
                let cache = ClubLogCtyCache(dataDir: dataDir)
                try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(state).write(to: cache.stateFile)
            }
        }, adjust: { environment in
            environment.network.clubLogCty = fetcher
        })
        await app.model.dataTools.settle()
        return app
    }

    static func usesClubLog(_ app: TestApp) -> Bool {
        app.model.contest.runtime.dxccLookup is ClubLogCtyResolver
    }

    @Test func startupDownloadsOnceAndSwitchesTheDxccSource() async throws {
        let fetcher = try Fetcher()
        let app = try await Self.make(fetcher: fetcher)
        #expect(fetcher.requests == 1)
        #expect(Self.usesClubLog(app))
        let lookup = try #require(app.model.contest.runtime.dxccLookup)
        // The exception of the file, and the local name of the entity by its ADIF number.
        #expect(lookup.resolve("DL0CTY")?.adifDxcc == 503)
        #expect(lookup.resolve("DL1ABC")?.adifDxcc == 230)
        #expect(app.model.status.message == "DXCC z Club Logu aktualizováno: 2 entit, 1 výjimek, 2 prefixů")
        #expect(app.model.messages.lines.map(\.text) == [app.model.status.message])
        #expect(app.model.dataTools.clubLogCtyStatus == ContestMessage("Poslední stažení cty.xml: %s",
                                                                        .string("2026-10-06 12:00 UTC")))
        // The same day the menu item asks for nothing.
        _ = MenuActions.perform("database.updateClubLogDxcc", app: app.model)
        await app.model.dataTools.settle()
        #expect(fetcher.requests == 1)
        #expect(app.model.status.message
            == "DXCC z Club Logu je aktuální, další stažení je možné po 2026-10-07 12:00 UTC")
    }

    @Test func startupWithoutKeyOrSwitchAsksNothingAndKeepsTheLocalData() async throws {
        for (key, enabled) in [("", true), ("KEY", false)] {
            let fetcher = try Fetcher()
            let app = try await Self.make(fetcher: fetcher, apiKey: key, enabled: enabled)
            #expect(fetcher.requests == 0)
            #expect(!Self.usesClubLog(app))
            #expect(app.model.contest.runtime.dxccLookup != nil)
            #expect(app.model.messages.lines.isEmpty)
            #expect(app.model.dataTools.clubLogCtyStatus == ContestMessage("cty.xml z Club Logu zatím nebyl stažen"))
        }
    }

    @Test func startupRespectsTheDailySpacing() async throws {
        let fetcher = try Fetcher()
        let state = ClubLogCtyCache.State(lastAttemptAt: Self.now.addingTimeInterval(-3600))
        let app = try await Self.make(fetcher: fetcher, state: state)
        #expect(fetcher.requests == 0)
        #expect(!Self.usesClubLog(app))
    }

    @Test func manualUpdateWithoutKeyOrNetworkSaysSo() async throws {
        let noKey = try await Self.make(fetcher: try Fetcher(), apiKey: "")
        noKey.model.dataTools.updateClubLogDxcc()
        await noKey.model.dataTools.settle()
        #expect(noKey.model.status.message == "Club Log: chybí API klíč (Nastavení → Score Reporting)")

        let inert = try await Self.make(fetcher: nil)
        inert.model.dataTools.updateClubLogDxcc()
        await inert.model.dataTools.settle()
        #expect(inert.model.status.message == "Síť je vypnutá (MCL_INERT_NETWORK)")
    }

    @Test func refusedKeyKeepsTheLocalDataAndIsReported() async throws {
        let fetcher = try Fetcher(status: 403, body: Data("Forbidden".utf8))
        let app = try await Self.make(fetcher: fetcher)
        #expect(fetcher.requests == 1)
        #expect(!Self.usesClubLog(app))
        let text = "Aktualizace DXCC z Club Logu selhala: Club Log odmítl API klíč (HTTP 403) (zůstávají dosavadní data)"
        #expect(app.model.status.message == text)
        #expect(app.model.messages.lines.map(\.text) == [text])
        #expect(app.model.dataTools.clubLogCtyResult == ClubLogDxccModelTests.failed(.forbidden))
    }

    @Test func switchingOffReturnsToTheLocalData() async throws {
        let app = try await Self.make(fetcher: try Fetcher())
        #expect(Self.usesClubLog(app))
        app.model.config.config.clubLog.ctyEnabled = false
        for _ in 0..<1000 where Self.usesClubLog(app) {
            await Task.yield()
            await app.model.dataTools.settle()
        }
        #expect(!Self.usesClubLog(app))
        #expect(app.model.contest.runtime.dxccLookup != nil)
    }

    static func failed(_ failure: ClubLogCtyCache.Failure) -> ContestMessage {
        DataToolsModel.failed(DataToolsModel.text(failure))
    }
}
