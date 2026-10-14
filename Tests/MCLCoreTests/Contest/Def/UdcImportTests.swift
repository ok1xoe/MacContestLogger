import Foundation
import Testing
@testable import MCLCore

/// N1MM `.udc` → YAML definition (the definition editor's „Importovat UDC…").
@Suite struct UdcImportTests {

    static let wpxLike = """
        [Contest]
        Name = MYWPX
        DisplayName = My WPX Test
        CabrilloName = MY-WPX
        Mode = CW
        DupeType = 3
        Multiplier1Name = Prefix
        PointsPerContact = 1
        CabrilloString = SNT, 4, SentNr, 4, CallSign, 13, RCV, 4, RcvNr, 4
        """

    static let rich = """
        [Author]
        AuthorName=Test Club
        [Contest]
        Name=TESTDX
        DisplayName=Test DX Contest
        CabrilloName=TEST-DX
        Mode = BOTH
        DupeType =4
        DupeQSOMinutesAgo = 30, True, False, True, False
        Multiplier1Name =CountryPrefix
        MultSqlString = CountryPrefix
        DoNotCountMeAsMult = True
        Multiplier2Name = Sect
        MultSqlString2 = Section
        IsMultPer = 1
        IsMult2Per = 4
        NumMults = 2
        PointsPerContact = 40m, 3, CW, 2, OK, 5, MyCountry, 1, SameContinent, 1, OtherContinent, 3
        PointsMultAtTimeGMT = 0000, 0559, 2
        PointsMultByMode = CW, 2
        PowerMult = QRP, 4, LP, 2, HP, 1
        IsWorkable = EUonly
        DefaultContestExchange = 001 LastCallSuff
        CabrilloString =SNT, 4, SentNr, 4, SentExch, 6, CallSign, 13, RCV, 4, RcvNr, 4, Exchange1, 6
        QsoErrorString = Any_not_Empty
        BonusPoints = OK1XOE, 10, F, +25
        MultipleSessions = 1200/60
        ResetMultsEverySession = 1
        QsoNumbersByBand = 2
        StartOfContest = 1, 12
        EndOfContest = 2, 12
        MinimumOffTime = 60
        WebAddress = https://example.org/rules
        """

    private static func check(_ result: UdcImport.Result, sets extra: [String] = []) -> DefinitionEditing.Check {
        let known = ["dxcc_entities", "wpx_prefixes", "cq_zones", "itu_zones", "grid_fields", "grid_squares",
                     "arrl_sections", "na_areas"] + extra
        return DefinitionEditing.check(result.yaml, fileId: result.id, knownSets: known)
    }

    @Test func parsesTheIniText() {
        let values = UdcImport.parse("[Contest]\n; comment\nName = ABC\nMode=CW\n#x\nEmpty =\n")
        #expect(values == ["name": "ABC", "mode": "CW", "empty": ""])
        #expect(UdcImport.decode(Data([0x4E, 0x61, 0x6D, 0x65, 0x3D, 0xE9])) == "Name=é")
    }

    @Test func wpxLikeContest() throws {
        let result = UdcImport.convert(UdcImport.parse(Self.wpxLike))
        #expect(result.id == "mywpx")
        let check = Self.check(result)
        #expect(!check.hasErrors, "\(check.issues) \(result.yaml)")
        let definition = try #require(check.definition)
        #expect(definition.metadata?.name == "My WPX Test")
        #expect(definition.modes == ["CW"])
        #expect(definition.dupe?.scope == .PER_BAND_MODE)
        #expect(definition.multipliers?.first??.set == "wpx_prefixes")
        #expect(definition.exchange?.received?.compactMap { $0?.id } == ["rst", "nr"])
        #expect(definition.cabrillo?.contestName == "MY-WPX")
    }

    @Test func richContestMapsTheParameters() throws {
        let result = UdcImport.convert(UdcImport.parse(Self.rich)) { prefix in
            ["OK": 503, "F": 227][prefix]
        }
        let check = Self.check(result)
        #expect(!check.hasErrors, "\(check.issues) \(result.yaml)")
        let d = try #require(check.definition)
        #expect(d.modes == ["CW", "SSB"])
        #expect(d.dupe?.reworkMinutes == 30)
        #expect(d.dupe?.scope == .PER_BAND)
        #expect(d.workable?.continentIs == "EU")
        #expect(d.scoring?.powerFactorFor("QRP") == 4)
        #expect(d.scoring?.qsoPoints?.factors?.count == 2)
        #expect(d.scoring?.qsoPoints?.rules?.first??.when?.bandIn == ["40m"])
        #expect(d.scoring?.qsoPoints?.rules?.contains { $0?.when?.entityIn == [503] } == true)
        #expect(d.scoring?.bonuses?.count == 1, "only the call is a bonus")
        #expect(d.multipliers?.first??.when?.not?.ownDxcc == true)
        #expect(d.multipliers?.last??.scope == .ONCE)
        #expect(d.multipliers?.last??.set == "arrl_sections")
        #expect(d.period?.sessions?.resetMultipliers == true)
        #expect(d.period?.sessions?.minutes == 60)
        #expect(d.period?.startWeekday == "SAT")
        #expect(d.period?.startTime == "1200")
        #expect(d.period?.durationHours == 24)
        #expect(d.numbering?.multiOpOnly == true)
        #expect(d.operating?.offTime?.minimumMinutes == 60)
        #expect(d.metadata?.officialUrl == "https://example.org/rules")
        #expect(d.exchange?.sent?.contains { $0?.derive == "lastCallSuffix" } == true)
        #expect(result.notes.contains { $0.contains("BonusPoints 'F, +25'") })
        #expect(result.yaml.hasPrefix("# Imported from an N1MM UDC file"))
    }

    @Test func unknownMultiplierMakesAnOpenSet() throws {
        let udc = """
            Name=XYZ
            Mode=SSB
            Multiplier1Name=Sect
            MultWindowType=Districts
            CabrilloString=SNT,4,CallSign,13,RCV,4,Exchange1,6
            """
        let result = UdcImport.convert(UdcImport.parse(udc))
        #expect(result.sets.keys.sorted() == ["xyz_districts"])
        let check = Self.check(result, sets: Array(result.sets.keys))
        #expect(!check.hasErrors, "\(check.issues) \(result.yaml)")
        let set = try MultiplierSetLoader.load(Data(try #require(result.sets["xyz_districts"]).utf8))
        #expect(set.id == "xyz_districts")
        #expect(check.definition?.exchange?.received?.first??.type == .RS)
    }

    @Test func noCabrilloStringFallsBackToSerial() throws {
        let result = UdcImport.convert(UdcImport.parse("Name=Plain\nDupeType=4\nPointsPerContact=1/600/10; 601/1200/13;"))
        let check = Self.check(result)
        #expect(!check.hasErrors, "\(check.issues) \(result.yaml)")
        #expect(check.definition?.dupe?.none == true)
        #expect(result.notes.contains { $0.contains("Distance table") })
    }

    @Test func countryPrefixWithoutDxccDataMatchesTheCall() throws {
        let udc = "Name=YB\nMode=SSB\nPointsPerContact = YB, 3, 7A, 3, MyCountry, 1, SameContinent, 1, OtherContinent, 2"
        let result = UdcImport.convert(UdcImport.parse(udc))
        let check = Self.check(result)
        #expect(!check.hasErrors, "\(check.issues) \(result.yaml)")
        let rules = try #require(check.definition?.scoring?.qsoPoints?.rules)
        #expect(rules.first??.when?.expr == "matches(call, 'YB.*')")
        #expect(rules[2]?.when?.ownDxcc == true)
        #expect(rules[3]?.when?.sameContinent == true)
        #expect(result.notes.isEmpty)
    }
}

