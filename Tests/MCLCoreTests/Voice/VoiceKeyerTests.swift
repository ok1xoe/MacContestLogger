import Dispatch
import Foundation
import os
import Testing
@testable import MCLCore

/// Port of `voice/VoiceKeyerTest` (7 tests, same names) + error paths measured by the probe
/// `VK.errors` (maintainer-only probe).
///
/// Without success time bounds: the audio stand-in "plays" until the message cancels it, the test `await`s an event
/// (`Events.waitFor`) or a completion listener (`Done`) — no `DispatchTime` deadlines or semaphores. The only
/// time condition is the lower bound of the PTT delay (load can only lengthen it). Only a guard protects against hangs
/// the suite's `timeLimit` (`.ioSafetyNet`, 30 min).
@Suite(.ioSafetyNet) struct VoiceKeyerTests {

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Events in the order they came from the key queue; `waitFor` wakes up when an event is added.
    final class Events: Sendable {
        private struct State {
            var list: [String] = []
            var waiters: [(condition: @Sendable ([String]) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []
        }

        private let state = OSAllocatedUnfairLock<State>(initialState: State())

        func add(_ event: String) {
            let ready: [CheckedContinuation<Void, Never>] = state.withLock { s in
                s.list.append(event)
                let list: [String] = s.list
                let satisfied = s.waiters.filter { $0.condition(list) }.map(\.continuation)
                s.waiters.removeAll { $0.condition(list) }
                return satisfied
            }
            for continuation in ready { continuation.resume() }
        }

        var all: [String] { state.withLock { $0.list } }

        /// Waits until a condition over the events holds (without a deadline, does not block a pool thread).
        func waitFor(_ condition: @escaping @Sendable ([String]) -> Bool) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let now: Bool = state.withLock { s in
                    if condition(s.list) { return true }
                    s.waiters.append((condition, continuation))
                    return false
                }
                if now { continuation.resume() }
            }
        }
    }

    /// A message completion listener: remembers the error and wakes the waiter (`await`, without a semaphore).
    final class Done: Sendable {
        private struct State {
            var result: String??
            var waiter: CheckedContinuation<String?, Never>?
        }

        private let state = OSAllocatedUnfairLock<State>(initialState: State())

        var listener: VoiceKeyer.Listener {
            { [self] error in
                let waiter: CheckedContinuation<String?, Never>? = state.withLock { s in
                    s.result = .some(error)
                    defer { s.waiter = nil }
                    return s.waiter
                }
                waiter?.resume(returning: error)
            }
        }

        /// The error from the listener (`nil` = no error); waits until the listener is called.
        func value() async -> String? {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let ready: String?? = state.withLock { s in
                    if let result = s.result { return .some(result) }
                    s.waiter = continuation
                    return .none
                }
                if let ready { continuation.resume(returning: ready) }
            }
        }
    }

    let events = Events()

    var ptt: VoiceKeyer.Ptt {
        let events = self.events
        return { on in events.add(on ? "PTT on" : "PTT off") }
    }

    static func fileName(_ file: JavaPath) -> String {
        String(file.description.split(separator: "/").last ?? "")
    }

    /// The audio "plays" 5 steps of 1 ms, interruptibly; files from `untilCancelled` play until the message is
    /// cancelled (without a guard in steps — it could finish before the cancellation under load) — instead of Java
    /// "long" files (2,000 / 300 ms) and putting the test to sleep. Runs on the key queue, not in the shared pool.
    func audio(untilCancelled: Set<String> = []) -> VoiceKeyer.AudioOut {
        let events = self.events
        return { file, cancelled in
            let name = Self.fileName(file)
            events.add("play " + name)
            let endless: Bool = untilCancelled.contains(name)
            var step = 0
            while endless || step < 5 {
                if cancelled() {
                    events.add("cut " + Self.fileName(file))
                    return
                }
                Thread.sleep(forTimeInterval: 0.001)
                step += 1
            }
        }
    }

    /// Starts a message and waits (`await`) for the listener; returns the error from the listener.
    static func playAndWait(_ keyer: VoiceKeyer, _ files: [JavaPath]) async -> String? {
        let done = Done()
        keyer.play(files, listener: done.listener)
        return await done.value()
    }

    static func paths(_ names: String...) -> [JavaPath] {
        names.map { try! JavaPath($0) }
    }

    @Test func keysPlaysAllFilesThenUnkeys() async {
        let keyer = VoiceKeyer(audio: audio(), ptt: ptt, pttDelayMs: { 0 })
        let result = await Self.playAndWait(keyer, Self.paths("cq.wav", "mycall.wav"))
        keyer.close()
        #expect(result == nil)
        #expect(events.all == ["PTT on", "play cq.wav", "play mycall.wav", "PTT off"])
    }

    @Test func pttDelayComesBeforeAudio() async {
        let keyedAt = OSAllocatedUnfairLock<UInt64>(initialState: 0)
        let audioAt = OSAllocatedUnfairLock<UInt64>(initialState: 0)
        let keyer = VoiceKeyer(
            audio: { _, _ in audioAt.withLock { $0 = DispatchTime.now().uptimeNanoseconds } },
            ptt: { on in
                if on { keyedAt.withLock { $0 = DispatchTime.now().uptimeNanoseconds } }
            },
            pttDelayMs: { 80 })
        let result = await Self.playAndWait(keyer, Self.paths("cq.wav"))
        keyer.close()
        #expect(result == nil)
        let elapsedMs = (audioAt.withLock { $0 } - keyedAt.withLock { $0 }) / 1_000_000
        #expect(elapsedMs >= 70)
    }

    @Test func emptyMessageDoesNotKey() async {
        let keyer = VoiceKeyer(audio: audio(), ptt: ptt, pttDelayMs: { 0 })
        let events = self.events
        keyer.play([]) { _ in events.add("done") }
        #expect(events.all.isEmpty)
        // Instead of Java's sleep: the key queue is serial, so once the next message finishes, anything the empty
        // message would send or report would already be visible.
        let next = await Self.playAndWait(keyer, Self.paths("x.wav"))
        keyer.close()
        #expect(next == nil)
        #expect(events.all == ["PTT on", "play x.wav", "PTT off"])
    }

    @Test func stopCutsAudioAndUnkeys() async {
        let done = Done()
        let keyer = VoiceKeyer(audio: audio(untilCancelled: ["cq.wav", "cq2.wav"]), ptt: ptt, pttDelayMs: { 0 })
        keyer.play(Self.paths("cq.wav", "cq2.wav"), listener: done.listener)
        await events.waitFor { $0.contains("play cq.wav") }
        #expect(keyer.isPlaying)
        keyer.stop()
        #expect(await done.value() == nil)
        #expect(!keyer.isPlaying)
        keyer.close()
        #expect(events.all == ["PTT on", "play cq.wav", "cut cq.wav", "PTT off"])
    }

    /// `closeAndDrain` returns only after the running message released the PTT (the quit disconnects CAT after it);
    /// a message asked for afterwards does not key at all.
    @Test func closeAndDrainReturnsAfterThePttRelease() async {
        let keyer = VoiceKeyer(audio: audio(untilCancelled: ["cq.wav"]), ptt: ptt, pttDelayMs: { 0 })
        keyer.play(Self.paths("cq.wav")) { _ in }
        await events.waitFor { $0.contains("play cq.wav") }
        let events = self.events
        let seen: [String] = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            let thread = Thread {
                keyer.closeAndDrain()
                continuation.resume(returning: events.all)
            }
            thread.start()
        }
        #expect(seen == ["PTT on", "play cq.wav", "cut cq.wav", "PTT off"])
        let after = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            keyer.play(Self.paths("x.wav")) { _ in }
            let thread = Thread {
                keyer.closeAndDrain()
                continuation.resume(returning: events.all)
            }
            thread.start()
        }
        #expect(after == seen)
    }

    @Test func newMessageInterruptsRunningOne() async {
        let second = Done()
        let keyer = VoiceKeyer(audio: audio(untilCancelled: ["cq.wav"]), ptt: ptt, pttDelayMs: { 0 })
        keyer.play(Self.paths("cq.wav")) { _ in }
        await events.waitFor { $0.contains("play cq.wav") }
        keyer.play(Self.paths("exch.wav"), listener: second.listener)
        #expect(await second.value() == nil)
        keyer.close()
        #expect(events.all == ["PTT on", "play cq.wav", "cut cq.wav", "PTT off", "PTT on", "play exch.wav", "PTT off"])
    }

    @Test func audioFailureStillUnkeys() async {
        let keyer = VoiceKeyer(audio: { _, _ in throw Failure(description: "zvuková karta nedostupná") },
                               ptt: ptt, pttDelayMs: { 0 })
        let result = await Self.playAndWait(keyer, Self.paths("cq.wav"))
        keyer.close()
        #expect(result == "zvuková karta nedostupná")
        #expect(events.all == ["PTT on", "PTT off"])
    }

    @Test func pttFailureMeansNoAudio() async {
        let keyer = VoiceKeyer(audio: audio(), ptt: { _ in throw Failure(description: "rigctld odmítl PTT") },
                               pttDelayMs: { 0 })
        let result = await Self.playAndWait(keyer, Self.paths("cq.wav"))
        keyer.close()
        #expect(result == "rigctld odmítl PTT")
        #expect(events.all.isEmpty, "nothing is transmitted without keying")
    }

    /// The order of events and the error text for all error paths (`VK.errors`): PTT on/off throws,
    /// a file throws, combinations.
    @Test func errorPathsMatchJava() async {
        let rows = ProbeRows.rows(VoiceAudioMeasured.extra, "VK.errors")
        #expect(rows.count == 7)
        let scenarios: [String: (on: String?, off: String?, failAt: Int)] = [
            "ok": (nil, nil, -1), "audioFails": (nil, nil, 0), "secondFails": (nil, nil, 1),
            "pttOffFails": (nil, "rig odpojen", -1), "bothFail": (nil, "rig odpojen", 0),
            "pttOnFails": ("rigctld odmítl PTT", nil, -1), "pttOnAndOffFail": ("on", "off", -1),
        ]
        for row in rows {
            guard let scenario = scenarios[row[0]] else {
                Issue.record("unknown scenario \(row[0])")
                continue
            }
            let events = Events()
            let index = OSAllocatedUnfairLock(initialState: 0)
            let keyer = VoiceKeyer(
                audio: { file, _ in
                    events.add("play " + file.description)
                    let current = index.withLock { value in
                        defer { value += 1 }
                        return value
                    }
                    if current == scenario.failAt { throw Failure(description: "zvuk " + file.description) }
                },
                ptt: { on in
                    events.add(on ? "PTT on" : "PTT off")
                    if on, let message = scenario.on { throw Failure(description: message) }
                    if !on, let message = scenario.off { throw Failure(description: message) }
                },
                pttDelayMs: { 0 })
            let result = await Self.playAndWait(keyer, Self.paths("a.wav", "b.wav"))
            keyer.close()
            #expect(events.all.joined(separator: "|") == row[1], "\(row[0])")
            #expect(result ?? "<null>" == row[2], "\(row[0])")
        }
    }
}
