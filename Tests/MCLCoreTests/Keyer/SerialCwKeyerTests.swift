import Foundation
import Testing
@testable import MCLCore

/// DTR/RTS keying: the element sequence (weight, word spacing, prosigns, speed changes), the scheduler's exact
/// line sequence with PTT delay and tail, abort, tune and the release on every exit. The lines and the sleeper are
/// recording fakes — no serial port, no wall clock.
@Suite(.ioSafetyNet) struct SerialCwKeyerTests {

    private static let ctx = CwMessageBuilder.Context(
        myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "15",
        cutNumbers: false, leadingZeros: false)

    private static func build(_ template: String) -> CwMessage {
        CwMessageBuilder.build(template, ctx)
    }

    private static func steps(_ elements: [CwElement]) -> [String] {
        elements.map { ($0.keyDown ? "+" : "-") + String(Int($0.ms.rounded())) }
    }

    // MARK: - element sequence

    @Test func plainTimingAt20Wpm() {
        // dit 60 ms: E = ., T = -, word gap 7 dits.
        let e = CwElements.sequence(Self.build("e t"), wpm: 20)
        #expect(Self.steps(e) == ["+60", "-420", "+180"])
        let a = CwElements.sequence(Self.build("an"), wpm: 20)
        #expect(Self.steps(a) == ["+60", "-60", "+180", "-180", "+180", "-60", "+60"])
    }

    @Test func contestSpacingUsesSixDits() {
        let e = CwElements.sequence(Self.build("e t"), wpm: 20, contestSpacing: true)
        #expect(Self.steps(e) == ["+60", "-360", "+180"])
    }

    @Test func weightMovesTimeFromSpaceToMark() {
        // weight 60: +0.2 dit (12 ms) on each mark, taken from the space after it.
        let e = CwElements.sequence(Self.build("i"), wpm: 20, weight: 60)
        #expect(Self.steps(e) == ["+72", "-48", "+72"])
        let light = CwElements.sequence(Self.build("i"), wpm: 20, weight: 40)
        #expect(Self.steps(light) == ["+48", "-72", "+48"])
        #expect(e[0].ms + e[1].ms == 120) // a dit and its space keep their length
    }

    @Test func prosignAndSpeedChange() {
        // AR as one character: .-.-. ; then "<" lowers by 2 WPM in the message builder's units.
        let ar = CwElements.sequence(CwMessage(parts: [.prosign("AR")]), wpm: 20)
        #expect(Self.steps(ar) == ["+60", "-60", "+180", "-60", "+60", "-60", "+180", "-60", "+60"])
        let faster = CwElements.sequence(CwMessage(parts: [.text("E"), .speed(20), .text("E")]), wpm: 20)
        #expect(Self.steps(faster) == ["+60", "-90", "+30"])
    }

    @Test func spacesAtTheEdgesAndUnknownCharactersSendNothing() {
        #expect(CwElements.sequence(Self.build("  "), wpm: 20).isEmpty)
        #expect(Self.steps(CwElements.sequence(CwMessage(parts: [.text(" e# ")]), wpm: 20)) == ["+60"])
    }

    // MARK: - scheduler

    private static func keyer(_ log: KeyLog, ptt: Bool = true, catPtt: Bool = false,
                              options: (inout CwKeyingOptions) -> Void = { _ in }) -> SerialCwKeyer {
        var o = CwKeyingOptions()
        o.serialPttDelayMs = 50
        o.serialPttTailMs = 30
        options(&o)
        let cat: (@Sendable (Bool) throws -> Void)? = catPtt ? { @Sendable on in log.add("cat ptt " + (on ? "on" : "off")) } : nil
        return SerialCwKeyer(lines: FakeKeyLines(log, ptt: ptt), catPtt: cat, sleeper: log.sleeper, options: o)
    }

    @Test func messageIsKeyedWithPttDelayAndTail() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.send(Self.build("en"), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["ptt on", "wait 50", "key down", "wait 60", "key up", "wait 180", "key down",
                               "wait 180", "key up", "wait 60", "key down", "wait 60", "key up", "wait 30",
                               "ptt off"])
    }

    @Test func withoutPttThereIsNoDelay() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log, ptt: false)
        defer { keyer.close() }
        try keyer.send(Self.build("e"), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["key down", "wait 60", "key up"])
    }

    @Test func catPttGoesWithTheLinePtt() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log, ptt: false, catPtt: true) { $0.serialPttDelayMs = 100 }
        defer { keyer.close() }
        try keyer.send(Self.build("t"), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["cat ptt on", "wait 100", "key down", "wait 180", "key up", "wait 30",
                               "cat ptt off"])
    }

    @Test func weightAndSpacingComeFromConfigure() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log, ptt: false)
        defer { keyer.close() }
        var o = CwKeyingOptions()
        o.weight = 60
        try keyer.configure(o, potSpeed: nil)
        try keyer.send(Self.build("i"), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["key down", "wait 72", "key up", "wait 48", "key down", "wait 72", "key up"])
    }

    @Test func abortReleasesAtOnce() throws {
        let log = KeyLog()
        log.holdAtWait(3) // inside the first dah of "T"
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.send(Self.build("tttt"), wpm: 20)
        #expect(log.waitUntilHeld())
        try keyer.abort()
        log.releaseHold()
        #expect(keyer.waitUntilIdle())
        let events = log.events
        #expect(Array(events.prefix(5)) == ["ptt on", "wait 50", "key down", "wait 180", "key up"])
        #expect(events.last == "ptt off")
        #expect(events.filter { $0 == "key down" }.count == 1)
        #expect(!events.contains("wait 30")) // no tail after an abort
    }

    @Test func queuedMessagesKeepPttOn() throws {
        let log = KeyLog()
        log.holdAtWait(2)
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.send(Self.build("e"), wpm: 20)
        #expect(log.waitUntilHeld())
        try keyer.send(Self.build("e"), wpm: 20)
        log.releaseHold()
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["ptt on", "wait 50", "key down", "wait 60", "key up", "key down", "wait 60", "key up",
                               "wait 30", "ptt off"])
    }

    @Test func tuneKeysAfterTheDelayAndReleases() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.tune(true)
        #expect(keyer.waitUntilIdle())
        #expect(log.events == ["ptt on", "wait 50", "key down"])
        try keyer.tune(false)
        #expect(keyer.waitUntilIdle())
        #expect(log.events.suffix(2) == ["key up", "ptt off"])
    }

    @Test func closeLeavesEverythingReleased() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log)
        try keyer.tune(true)
        #expect(keyer.waitUntilIdle())
        keyer.close()
        #expect(log.events.suffix(3) == ["key up", "ptt off", "close"])
    }

    @Test func lineFailureIsReportedOnTheNextSendAndReleases() throws {
        let log = KeyLog()
        log.failKey = true
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.send(Self.build("e"), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events.last == "ptt off")
        #expect(throws: CwKeyerError(.uncheckedIO, "Klíčování DTR/RTS selhalo: line broken")) {
            try keyer.send(Self.build("e"), wpm: 20)
        }
    }

    @Test func emptyMessageKeysNothing() throws {
        let log = KeyLog()
        let keyer = Self.keyer(log)
        defer { keyer.close() }
        try keyer.send(Self.build(" "), wpm: 20)
        #expect(keyer.waitUntilIdle())
        #expect(log.events.isEmpty)
    }

    // MARK: - monitor tone

    @Test func toneFollowsTheElements() {
        let elements = [CwElement(true, 10), CwElement(false, 10), CwElement(true, 10)]
        let pcm = CwToneRenderer.render(elements, pitchHz: 600, volume: 0.5, leadingSilenceMs: 5)
        let samples: [Int16] = stride(from: 0, to: pcm.count, by: 2).map {
            Int16(bitPattern: UInt16(pcm[$0]) | UInt16(pcm[$0 + 1]) << 8)
        }
        let perMs = CwToneRenderer.sampleRate / 1_000
        #expect(samples.count == 35 * perMs)
        #expect(samples.prefix(5 * perMs).allSatisfy { $0 == 0 })
        #expect(samples[(15 * perMs)..<(25 * perMs)].allSatisfy { $0 == 0 })
        let mark = samples[(5 * perMs)..<(15 * perMs)]
        #expect(mark.contains { $0 > 10_000 })
        #expect(mark.allSatisfy { abs(Int($0)) <= 16_000 })
        // Shaped edges: the first and last sample of a mark are silent.
        #expect(mark.first == 0)
        #expect(abs(Int(mark.last ?? 1)) < 200)
        #expect(CwToneRenderer.render(elements, pitchHz: 600, volume: 0).allSatisfy { $0 == 0 })
    }
}

/// The shared log of the fake lines, the fake sleeper and the CAT PTT fake.
final class KeyLog: @unchecked Sendable {
    private let condition = NSCondition()
    private var list: [String] = []
    private var holdAt: Int?
    private var waits = 0
    private var held = false
    var failKey = false

    lazy var sleeper: FakeCwSleeper = FakeCwSleeper(self)

    func add(_ event: String) {
        condition.lock()
        list.append(event)
        condition.unlock()
    }

    var events: [String] {
        condition.lock()
        defer { condition.unlock() }
        return list
    }

    /// The `n`-th wait (1-based) blocks until `releaseHold`, unless the keyer cancels it.
    func holdAtWait(_ n: Int) {
        condition.lock()
        holdAt = n
        condition.unlock()
    }

    func waitUntilHeld() -> Bool {
        let guardDate = Date(timeIntervalSinceNow: 30)
        condition.lock()
        defer { condition.unlock() }
        while !held {
            if !condition.wait(until: guardDate) { return false }
        }
        return true
    }

    func releaseHold() {
        condition.lock()
        holdAt = nil
        held = false
        condition.broadcast()
        condition.unlock()
    }

    func wait(_ ms: Double, cancelled: () -> Bool) -> Bool {
        condition.lock()
        list.append("wait " + String(Int(ms.rounded())))
        waits += 1
        if waits == holdAt {
            held = true
            condition.broadcast()
            while holdAt != nil {
                condition.wait()
            }
        }
        condition.unlock()
        return !cancelled()
    }

    func wake() {}
}

final class FakeCwSleeper: CwSleeper, @unchecked Sendable {
    private unowned let log: KeyLog

    init(_ log: KeyLog) {
        self.log = log
    }

    func begin() {}

    func wait(_ ms: Double, cancelled: @escaping () -> Bool) -> Bool {
        log.wait(ms, cancelled: cancelled)
    }

    func wake() {}
}

final class FakeKeyLines: CwKeyLines, @unchecked Sendable {
    private let log: KeyLog
    let hasPtt: Bool

    init(_ log: KeyLog, ptt: Bool) {
        self.log = log
        hasPtt = ptt
    }

    func setKey(_ down: Bool) throws {
        if down && log.failKey {
            throw ByteTransportError("line broken")
        }
        log.add(down ? "key down" : "key up")
    }

    func setPtt(_ on: Bool) throws {
        log.add(on ? "ptt on" : "ptt off")
    }

    func close() {
        log.add("close")
    }
}
