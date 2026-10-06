import Foundation
import os
import Testing
@testable import MCLCore

/// Club Log `cty.xml`: the parser over the synthetic fixture (every section), the resolver's lookup order (exceptions,
/// invalid operations, longest prefix, zone exceptions, all by the QSO date; `/P` `/MM` `/AM` and portable prefixes),
/// and the cache (24 h spacing with an injected clock, offline fallback, no key, HTTP 200/403/500, broken gzip).
/// No network: every download goes through an in-memory fetcher.
@Suite struct ClubLogCtyTests {

    // MARK: - fixtures

    static func fixtureXml() throws -> Data {
        let dir = try #require(Bundle.module.url(forResource: "clublog-cty", withExtension: nil))
        return try Data(contentsOf: dir.appendingPathComponent("cty.xml"))
    }

    static func fixture() throws -> ClubLogCtyData {
        try ClubLogCtyParser.parse(try fixtureXml())
    }

    static func date(_ text: String) -> Date {
        ClubLogCtyParser.parseDate(text)!
    }

    static let today: Date = date("2026-10-06T12:00:00+00:00")

    static func resolver(now: Date = today, local: [Int: ClubLogCtyResolver.LocalEntity] = [:]) throws
        -> ClubLogCtyResolver {
        ClubLogCtyResolver(try fixture(), localNames: local, now: { now })
    }

    /// Answers with a fixed response (or throws) and counts the requests; records the URLs.
    final class FakeFetcher: DataFetcher, @unchecked Sendable {
        enum Reply {
            case response(Int, Data)
            case failure(any Error)
        }
        private let lock = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let reply: Reply

        init(_ reply: Reply) {
            self.reply = reply
        }

        var requests: [URL] { lock.withLock { $0 } }

        func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
            lock.withLock { $0.append(url) }
            switch reply {
            case .response(let status, let data):
                return (status, data)
            case .failure(let error):
                throw error
            }
        }
    }

    static func tempCache() throws -> ClubLogCtyCache {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clublog-cty-\(UUID().uuidString)")
        return ClubLogCtyCache(dataDir: dir)
    }

    // MARK: - parser

    @Test func parsesEverySection() throws {
        let data = try Self.fixture()
        #expect(data.fileDate == "2026-10-01T06:00:00+00:00")
        // The entity without an ADIF number and the prefix without a call are skipped.
        #expect(data.entities.map(\.adif) == [503, 218, 291, 54, 15, 13, 230])
        #expect(data.exceptions.map(\.call) == ["KC4AAA", "DL0XX/P"])
        #expect(data.prefixes.map(\.call) == ["OK", "OK", "K", "W", "UA", "UA9", "DL", "X5"])
        #expect(data.invalidOperations.map(\.call) == ["OK0XX"])
        #expect(data.zoneExceptions == [ClubLogCtyData.ZoneException(
            record: 30, call: "UA9XYZ", zone: 18, start: Self.date("2024-01-01T00:00:00+00:00"))])
    }

    @Test func parsesEntityFieldsDatesAndTheDeletedFlag() throws {
        let data = try Self.fixture()
        let czech = try #require(data.entities.first { $0.adif == 503 })
        #expect(czech == ClubLogCtyData.Entity(adif: 503, name: "CZECH REPUBLIC", prefix: "OK", deleted: false,
                                               cqz: 15, cont: "EU", lat: 50.0, lon: 14.5,
                                               start: Self.date("1993-01-01T00:00:00+00:00")))
        let old = try #require(data.entities.first { $0.adif == 218 })
        #expect(old.deleted)
        #expect(old.end == Self.date("1992-12-31T23:59:59+00:00"))
        // The attribute form reads the same fields.
        let germany = try #require(data.entities.first { $0.adif == 230 })
        #expect(germany == ClubLogCtyData.Entity(adif: 230, name: "FEDERAL REPUBLIC OF GERMANY", prefix: "DL",
                                                 cqz: 14, cont: "EU", lat: 51.0, lon: 10.0))
        let exception = try #require(data.exceptions.first)
        #expect(exception.record == 1)
        #expect(exception.adif == 13)
        #expect(exception.lon == 166.67)
        #expect(exception.start == Self.date("2020-01-01T00:00:00+00:00"))
        #expect(exception.end == Self.date("2020-12-31T23:59:59+00:00"))
        let invalid = try #require(data.invalidOperations.first)
        #expect(invalid.record == 20)
        #expect(invalid.end == Self.date("2025-01-31T23:59:59+00:00"))
    }

    @Test func rejectsWhatIsNotACountryFile() {
        #expect(throws: ClubLogCtyParser.Error.self) { try ClubLogCtyParser.parse(Data("not xml".utf8)) }
        #expect(throws: ClubLogCtyParser.Error(reason: "cty.xml: chybí element <clublog>")) {
            try ClubLogCtyParser.parse(Data("<html><body/></html>".utf8))
        }
        #expect(throws: ClubLogCtyParser.Error(reason: "cty.xml: žádné entity nebo prefixy")) {
            try ClubLogCtyParser.parse(Data("<clublog><entities/><prefixes/></clublog>".utf8))
        }
    }

    // MARK: - resolver

    @Test func longestPrefixWithTheEntitysFields() throws {
        let r = try Self.resolver()
        let ok = try #require(r.resolve("OK1XOE"))
        #expect(ok == DxccEntity(entityCode: 503, name: "CZECH REPUBLIC", countryCode: "OK", continents: ["EU"],
                                 cq: [15], itu: nil, lat: 50.0, lon: 14.5, primaryPrefix: "OK", adifDxcc: 503))
        #expect(r.resolve("UA3ABC")?.adifDxcc == 54)
        #expect(r.resolve("UA9ABC")?.adifDxcc == 15)
        #expect(r.resolve("UA9ABC")?.cq == [17])
        #expect(r.resolve("W1AW")?.adifDxcc == 291)
        #expect(r.resolve(" ok1xoe ")?.adifDxcc == 503)
        #expect(r.resolve("ZZ1ZZ") == nil)
        #expect(r.resolve("") == nil)
        #expect(r.resolve(nil) == nil)
        // ADIF 0 = no DXCC.
        #expect(r.resolve("X5ABC") == nil)
    }

    @Test func prefixRecordsFollowTheQsoDate() throws {
        let r = try Self.resolver()
        #expect(r.resolve("OK1ABC", at: Self.date("1990-06-01T00:00:00+00:00"))?.adifDxcc == 218)
        #expect(r.resolve("OK1ABC", at: Self.date("1993-01-01T00:00:00+00:00"))?.adifDxcc == 503)
        // Deleted entities are not enumerated, but still resolve for their period.
        #expect(!r.entities().contains { $0.entityCode == 218 })
        #expect(r.entities().map(\.entityCode) == [13, 15, 54, 230, 291, 503])
    }

    @Test func exceptionOnlyInsideItsPeriod() throws {
        let r = try Self.resolver()
        let inside = try #require(r.resolve("KC4AAA", at: Self.date("2020-06-01T00:00:00+00:00")))
        #expect(inside.adifDxcc == 13)
        #expect(inside.lat == -77.85)
        #expect(inside.primaryContinent == "AN")
        // Outside it the prefix decides (KC4 → K → USA).
        #expect(r.resolve("KC4AAA", at: Self.date("2021-01-01T00:00:00+00:00"))?.adifDxcc == 291)
        #expect(r.resolve("KC4AAA", at: Self.date("2019-12-31T23:59:59+00:00"))?.adifDxcc == 291)
        // An exception matches the call as written.
        #expect(r.resolve("DL0XX/P")?.adifDxcc == 503)
        #expect(r.resolve("DL0XX")?.adifDxcc == 230)
    }

    @Test func invalidOperationOnlyInsideItsPeriod() throws {
        let r = try Self.resolver()
        #expect(r.resolve("OK0XX", at: Self.date("2025-01-15T00:00:00+00:00")) == nil)
        #expect(r.resolve("OK0XX", at: Self.date("2025-02-01T00:00:00+00:00"))?.adifDxcc == 503)
    }

    @Test func zoneExceptionOverridesTheCqZoneInsideItsPeriod() throws {
        let r = try Self.resolver()
        let now = try #require(r.resolve("UA9XYZ", at: Self.date("2026-01-01T00:00:00+00:00")))
        #expect(now.adifDxcc == 15)
        #expect(now.cq == [18])
        #expect(r.resolve("UA9XYZ", at: Self.date("2023-12-31T00:00:00+00:00"))?.cq == [17])
    }

    @Test func suffixesAndPortablePrefixes() throws {
        let r = try Self.resolver()
        #expect(r.resolve("OK1XOE/P")?.adifDxcc == 503)
        #expect(r.resolve("OK1XOE/QRP")?.adifDxcc == 503)
        #expect(r.resolve("OK1XOE/M")?.adifDxcc == 503)
        // Maritime and aeronautical mobile count for no entity.
        #expect(r.resolve("OK1XOE/MM") == nil)
        #expect(r.resolve("OK1XOE/AM") == nil)
        // The shorter part carries the prefix, on either side.
        #expect(r.resolve("DL/OK1XOE")?.adifDxcc == 230)
        #expect(r.resolve("OK1XOE/DL")?.adifDxcc == 230)
        #expect(r.resolve("DL/OK1XOE/P")?.adifDxcc == 230)
        // A single-digit suffix moves the call area.
        #expect(r.resolve("UA1ABC/9")?.adifDxcc == 15)
        #expect(r.resolve("UA9ABC/3")?.adifDxcc == 54)
    }

    @Test func undatedLookupUsesTheInjectedClock() throws {
        #expect(try Self.resolver(now: Self.date("2020-06-01T00:00:00+00:00")).resolve("KC4AAA")?.adifDxcc == 13)
        #expect(try Self.resolver(now: Self.date("2022-06-01T00:00:00+00:00")).resolve("KC4AAA")?.adifDxcc == 291)
    }

    @Test func namesAndItuZonesComeFromTheLocalDataByAdifNumber() throws {
        let local: [Int: ClubLogCtyResolver.LocalEntity] = [503: .init(name: "Czech Republic", itu: [28])]
        let r = try Self.resolver(local: local)
        let ok = try #require(r.resolve("OK1XOE"))
        #expect(ok.name == "Czech Republic")
        #expect(ok.itu == [28])
        #expect(r.resolve("DL1ABC")?.name == "FEDERAL REPUBLIC OF GERMANY")
        #expect(r.entities().first { $0.entityCode == 503 }?.name == "Czech Republic")
        // Built from another lookup: only entities with an ADIF number.
        let other = DxccEntity(entityCode: 7, name: "Somewhere", countryCode: "XX", continents: nil, cq: nil,
                               itu: [1], lat: .nan, lon: .nan, primaryPrefix: "XX", adifDxcc: nil)
        struct One: DxccLookup {
            let entity: DxccEntity
            func resolve(_ callsign: String?) -> DxccEntity? { nil }
            func entities() -> [DxccEntity] { [entity] }
        }
        #expect(ClubLogCtyResolver.localNames(from: One(entity: other)).isEmpty)
        #expect(ClubLogCtyResolver.localNames(from: nil).isEmpty)
    }

    @Test func specialCasesAndFillerPassTheQsoDate() throws {
        let r = try Self.resolver()
        let wrapped = DxccSpecialCases(r)
        #expect(wrapped.resolve("KC4AAA", at: Self.date("2020-06-01T00:00:00+00:00"))?.adifDxcc == 13)
        #expect(wrapped.resolve("KC4AAA")?.adifDxcc == 291)
        var qso = Qso()
        qso.call = "KC4AAA"
        qso.timestampUtc = Self.date("2020-06-01T10:00:00+00:00")
        #expect(DxccFiller.fill(&qso, r))
        #expect(qso.dxccEntity == 13)
        #expect(qso.continent == "AN")
        qso.timestampUtc = Self.date("2021-06-01T10:00:00+00:00")
        #expect(DxccFiller.refill(&qso, r))
        #expect(qso.dxccEntity == 291)
    }

    @Test func contestEnvironmentUsesClubLogOnlyWhenGiven() throws {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        let without = ContestEnvironment.load(dataRoot: root.path, dxccDir: nil, fallbackDataRoot: "/nonexistent")
        #expect(without.dxcc == nil)
        let with = ContestEnvironment.load(dataRoot: root.path, dxccDir: nil, fallbackDataRoot: "/nonexistent",
                                           clubLog: try Self.fixture())
        #expect(with.dxcc is ClubLogCtyResolver)
        #expect(with.dxcc?.resolve("OK1XOE")?.adifDxcc == 503)
    }

    // MARK: - cache

    @Test func spacingOfRequestsWithAnInjectedClock() {
        let t0 = Self.today
        let hour: TimeInterval = 3600
        var state = ClubLogCtyCache.State()
        #expect(ClubLogCtyCache.nextAllowed(.startup, state: state, now: t0) == nil)
        state.downloadedAt = t0
        state.lastAttemptAt = t0
        #expect(ClubLogCtyCache.nextAllowed(.startup, state: state, now: t0 + 23 * hour) == t0 + 24 * hour)
        #expect(ClubLogCtyCache.nextAllowed(.manual, state: state, now: t0 + 23 * hour) == t0 + 24 * hour)
        #expect(ClubLogCtyCache.nextAllowed(.startup, state: state, now: t0 + 24 * hour) == nil)
        // A failed attempt holds back the start-up check, not a manual update.
        state.lastAttemptAt = t0 + 30 * hour
        #expect(ClubLogCtyCache.nextAllowed(.startup, state: state, now: t0 + 31 * hour) == t0 + 54 * hour)
        #expect(ClubLogCtyCache.nextAllowed(.manual, state: state, now: t0 + 31 * hour) == nil)
        // A clock set back does not lock the update out.
        #expect(ClubLogCtyCache.nextAllowed(.manual, state: state, now: t0 - 48 * hour) == nil)
    }

    @Test func gzippedDownloadIsCachedAndAtMostOncePerDay() async throws {
        let cache = try Self.tempCache()
        let fetcher = FakeFetcher(.response(200, try Gzip.compress(try Self.fixtureXml())))
        let first = await cache.update(.startup, apiKey: " KEY+1 ", fetcher: fetcher, now: Self.today)
        let summary = try first.get().1
        #expect(summary == ClubLogCtyCache.Summary(entities: 7, exceptions: 2, prefixes: 8,
                                                   fileDate: "2026-10-01T06:00:00+00:00"))
        #expect(fetcher.requests.map(\.absoluteString) == ["https://cdn.clublog.org/cty.php?api=KEY%2B1"])
        #expect(try Data(contentsOf: cache.xmlFile) == (try Self.fixtureXml()))
        #expect(cache.load() == (try Self.fixture()))
        #expect(cache.readState() == ClubLogCtyCache.State(downloadedAt: Self.today, lastAttemptAt: Self.today,
                                                           fileDate: "2026-10-01T06:00:00+00:00"))

        // The same day: no request at start-up nor on demand.
        let later = Self.today + 6 * 3600
        for trigger in [ClubLogCtyCache.Trigger.startup, .manual] {
            let again = await cache.update(trigger, apiKey: "KEY+1", fetcher: fetcher, now: later)
            #expect(again.failure == .notDue(next: Self.today + 24 * 3600))
        }
        #expect(fetcher.requests.count == 1)
        // A day later it may ask again.
        let next = await cache.update(.startup, apiKey: "KEY+1", fetcher: fetcher, now: Self.today + 24 * 3600)
        #expect(next.failure == nil)
        #expect(fetcher.requests.count == 2)
    }

    @Test func plainXmlBodyIsAccepted() async throws {
        let cache = try Self.tempCache()
        let result = await cache.update(.manual, apiKey: "k", fetcher: FakeFetcher(.response(200, try Self.fixtureXml())),
                                        now: Self.today)
        #expect(result.failure == nil)
        #expect(cache.load()?.entities.count == 7)
    }

    @Test func noKeyMeansNoRequest() async throws {
        let cache = try Self.tempCache()
        let fetcher = FakeFetcher(.response(200, Data()))
        for key in ["", "   "] {
            let result = await cache.update(.startup, apiKey: key, fetcher: fetcher, now: Self.today)
            #expect(result.failure == .noKey)
        }
        #expect(fetcher.requests.isEmpty)
        #expect(cache.readState() == ClubLogCtyCache.State())
        #expect(cache.load() == nil)
    }

    @Test func failuresKeepTheCachedCopy() async throws {
        let cache = try Self.tempCache()
        let good = await cache.update(.manual, apiKey: "k", fetcher: FakeFetcher(.response(200, try Self.fixtureXml())),
                                      now: Self.today)
        #expect(good.failure == nil)
        let cached = cache.load()
        let cases: [(FakeFetcher.Reply, ClubLogCtyCache.Failure)] = [
            (.response(403, Data("Forbidden".utf8)), .forbidden),
            (.response(500, Data()), .http(500)),
            (.response(200, Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0xFF, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), .gzip),
            (.response(200, Data("<html>maintenance</html>".utf8)), .parse("cty.xml: chybí element <clublog>")),
        ]
        var day = Self.today
        for (reply, expected) in cases {
            day += 25 * 3600
            let result = await cache.update(.manual, apiKey: "k", fetcher: FakeFetcher(reply), now: day)
            #expect(result.failure == expected)
            #expect(cache.load() == cached)
            #expect(cache.readState().downloadedAt == Self.today)
            #expect(cache.readState().lastAttemptAt == day)
        }
    }

    @Test func offlineKeepsTheCacheAndHidesTheKey() async throws {
        let cache = try Self.tempCache()
        let error = URLError(.notConnectedToInternet,
                             userInfo: [NSURLErrorFailingURLStringErrorKey: "https://cdn.clublog.org/cty.php?api=SECRET"])
        let result = await cache.update(.startup, apiKey: "SECRET", fetcher: FakeFetcher(.failure(error)),
                                        now: Self.today)
        guard case .transport(let text)? = result.failure else {
            Issue.record("expected a transport failure, got \(String(describing: result.failure))")
            return
        }
        #expect(!text.contains("SECRET"))
        #expect(cache.load() == nil)
        // The attempt counts: no second request at start-up the same day, a manual one is allowed.
        let fetcher = FakeFetcher(.response(200, try Self.fixtureXml()))
        let again = await cache.update(.startup, apiKey: "SECRET", fetcher: fetcher, now: Self.today + 3600)
        #expect(again.failure == .notDue(next: Self.today + 24 * 3600))
        #expect(fetcher.requests.isEmpty)
        let manual = await cache.update(.manual, apiKey: "SECRET", fetcher: fetcher, now: Self.today + 3600)
        #expect(manual.failure == nil)
        #expect(ClubLogCtyCache.transportText(error, apiKey: "SECRET").contains("SECRET") == false)
    }

    @Test func loadFallsBackToTheRawFile() throws {
        let cache = try Self.tempCache()
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try Self.fixtureXml().write(to: cache.xmlFile)
        try Data("{broken".utf8).write(to: cache.compactFile)
        #expect(cache.load() == (try Self.fixture()))
    }

    @Test func gzipRoundTripAndRejection() throws {
        let text = Data("cty".utf8)
        #expect(try Gzip.decompress(try Gzip.compress(text)) == text)
        #expect(throws: Gzip.Error.self) { try Gzip.decompress(Data("plain".utf8)) }
        var corrupt = try Gzip.compress(Data(repeating: 65, count: 100))
        corrupt[corrupt.count - 8] ^= 0xFF
        #expect(throws: Gzip.Error(reason: "CRC32")) { try Gzip.decompress(corrupt) }
    }
}

fileprivate extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
