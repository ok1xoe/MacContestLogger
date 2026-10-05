import Testing
@testable import MCLCore

/// Unwipe (`wipeReversible`, `EP:569-589`) and who clears the memory (`EP:546, 565, 886, 992`).
@Suite struct WipeMemoryTests {

    private static let rstIds: [String?] = ["rst"]

    private static func form(call: String = "", exch: String = "", cexch: [(String?, String?)] = [],
                             rstSent: String = "599", rstRcvd: String = "599") -> EntryForm {
        var f = EntryForm()
        f.mode = .cw
        f.freqKHz = "14025.00"
        f.call = call
        f.exch = exch
        f.contestExchange = JavaLinkedMap(cexch)
        f.rstSent = rstSent
        f.rstRcvd = rstRcvd
        return f
    }

    @Test func wipeSavesCallAndExchange() {
        let start = Self.form(call: "OK1ABC", cexch: [("rst", "579"), ("nr", "12")], rstRcvd: "57")
        let out = WipeMemory().wipeReversible(form: start, contestActive: true, rstFieldIds: Self.rstIds)
        #expect(out.wiped)
        #expect(out.status == nil)
        #expect(out.form == start.wiped(contestActive: true, rstFieldIds: Self.rstIds))
        #expect(out.form.call.isEmpty)
        #expect(out.form.contestExchange["rst"] == "599")
        #expect(out.memory.lastWiped == WipedEntry(call: "OK1ABC", exch: "",
                                                   contestExchange: JavaLinkedMap([("rst", "579"), ("nr", "12")]),
                                                   rstRcvd: "57"))
    }

    @Test func secondAltWRestores() {
        let start = Self.form(call: "OK1ABC", exch: "", cexch: [("rst", "579"), ("nr", "12")], rstRcvd: "57")
        let first = WipeMemory().wipeReversible(form: start, contestActive: true, rstFieldIds: Self.rstIds)
        var wiped = first.form
        wiped.freqKHz = "7025.00"
        let second = first.memory.wipeReversible(form: wiped, contestActive: true, rstFieldIds: Self.rstIds)
        #expect(!second.wiped)
        #expect(second.status == .verbatim("Obnoveno OK1ABC"))
        #expect(second.status?.czech == "Obnoveno OK1ABC")
        #expect(second.memory.lastWiped == nil)
        #expect(second.form.call == "OK1ABC")
        #expect(second.form.contestExchange["nr"] == "12")
        #expect(second.form.contestExchange.keys == ["rst", "nr"])
        #expect(second.form.rstRcvd == "57")
        // Frequency and the sent report are not part of the memory.
        #expect(second.form.freqKHz == "7025.00")
        #expect(second.form.rstSent == "599")
    }

    /// "Effectively empty": contest values blank or equal to the sent report.
    @Test func emptinessIgnoresPrefilledReports() {
        let memory = WipeMemory(lastWiped: WipedEntry(call: "W1AW", exch: "5", contestExchange: JavaLinkedMap(),
                                                      rstRcvd: "599"))
        let prefilled = Self.form(cexch: [("rst", "599"), ("nr", " ")])
        #expect(!memory.wipeReversible(form: prefilled, contestActive: true, rstFieldIds: Self.rstIds).wiped)
        let typed = Self.form(cexch: [("rst", "599"), ("nr", "12")])
        let out = memory.wipeReversible(form: typed, contestActive: true, rstFieldIds: Self.rstIds)
        #expect(out.wiped)
        // Neither call nor exch was typed: the previous memory stays (Kotlin only saves a non-blank call/exch).
        #expect(out.memory == memory)
        #expect(out.form.contestExchange["nr"] == nil)
        let report = Self.form(cexch: [("rst", "57")], rstSent: "57")
        #expect(!memory.wipeReversible(form: report, contestActive: true, rstFieldIds: Self.rstIds).wiped)
    }

    @Test func freeExchangeIsSavedAndRestored() {
        let start = Self.form(exch: "15", rstRcvd: "55")
        let first = WipeMemory().wipeReversible(form: start, contestActive: false, rstFieldIds: [])
        #expect(first.memory.lastWiped?.exch == "15")
        #expect(first.form.rstRcvd == "599")
        let second = first.memory.wipeReversible(form: first.form, contestActive: false, rstFieldIds: [])
        #expect(second.form.exch == "15")
        #expect(second.form.rstRcvd == "55")
        #expect(second.status?.czech == "Obnoveno ")
    }

    /// An empty form without memory just wipes; Ctrl+W/logging forget.
    @Test func emptyWithoutMemoryWipesAndClearForgets() {
        let out = WipeMemory().wipeReversible(form: Self.form(), contestActive: false, rstFieldIds: [])
        #expect(out.wiped)
        #expect(out.memory.lastWiped == nil)
        var memory = WipeMemory(lastWiped: WipedEntry(call: "X", exch: "", contestExchange: JavaLinkedMap(),
                                                      rstRcvd: ""))
        memory.clear()
        #expect(memory.lastWiped == nil)
    }

    /// `isBlank` is Kotlin's: an NBSP-only call counts as empty.
    @Test func blankUsesKotlinSemantics() {
        let memory = WipeMemory(lastWiped: WipedEntry(call: "W1AW", exch: "", contestExchange: JavaLinkedMap(),
                                                      rstRcvd: "599"))
        let out = memory.wipeReversible(form: Self.form(call: "\u{00A0}"), contestActive: false, rstFieldIds: [])
        #expect(!out.wiped)
        #expect(out.form.call == "W1AW")
    }
}
