import Foundation
import os

/// Voice keyer (DVK, Java `voice/VoiceKeyer`): keys the transmitter, after a delay plays wav files
/// and unkeys. Runs on its own serial queue (the Java single-thread executor `voice-keyer`) so as not to
/// slow the UI; a new message interrupts the running one (as in N1MM pressing another F-key), `stop()` = Esc.
///
/// The order is fixed and unkeying goes sequentially after a `do/catch` that catches everything (Java `finally`) —
/// the transmitter must not stay keyed after an audio error or an interruption:
/// - **PTT on → delay (checks cancellation every ≤ 10 ms) → files → PTT off**;
/// - if PTT on fails, nothing is played, PTT off is not called and the error goes to the listener;
/// - a PTT off error is reported (`Odklíčování selhalo: …`) only when there was no error before;
/// - error text: Java `getMessage() ?: toString()` = Swift `String(describing:)` of the error;
/// - an empty list **increments the generation** (= stops the running message) and sends nothing;
/// - messages are queued in one queue; a message overridden in the meantime by a newer one (or `stop()`) does not
///   even start and its listener is not called; running playback is interrupted only by the `cancelled` check in `AudioOut`;
/// - the listener is called from the keyer queue (the caller wraps it in `@MainActor`).
///
/// **Divergence:** `play` after `close()` ends in Java with `RejectedExecutionException` (the generation was already incremented);
/// here the generation is just incremented and nothing runs.
public final class VoiceKeyer: Sendable {

    /// Playback of one file; blocks until the end or `cancelled() == true`.
    public typealias AudioOut = @Sendable (_ file: JavaPath, _ cancelled: @escaping @Sendable () -> Bool) throws -> Void
    /// PTT control (CAT); a no-op for VOX.
    public typealias Ptt = @Sendable (_ on: Bool) throws -> Void
    /// Feedback for the UI (`nil` = no error) — called from the keyer queue.
    public typealias Listener = @Sendable (_ error: String?) -> Void
    /// The wait between PTT on and the audio: `ms` or until `cancelled()` (on the keyer queue). Tests replace it with
    /// a wait they release themselves; the default is `sleep` below.
    public typealias Delay = @Sendable (_ ms: Int64, _ cancelled: @escaping @Sendable () -> Bool) -> Void

    private struct State {
        var generation: Int64 = 0
        var playing = false
        var closed = false
    }

    private let audio: AudioOut
    private let ptt: Ptt
    private let pttDelayMs: @Sendable () -> Int32
    private let delay: Delay
    private let queue = DispatchQueue(label: "voice-keyer")
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(audio: @escaping AudioOut, ptt: @escaping Ptt, pttDelayMs: @escaping @Sendable () -> Int32,
                delay: Delay? = nil) {
        self.audio = audio
        self.ptt = ptt
        self.pttDelayMs = pttDelayMs
        self.delay = delay ?? { ms, cancelled in VoiceKeyer.sleep(ms, cancelled) }
    }

    /// Plays files (interrupts the previous message). An empty list sends nothing.
    public func play(_ files: [JavaPath], listener: Listener?) {
        play(steps: files.isEmpty ? [] : [.play(files)], onAction: { _ in true }, listener: listener)
    }

    /// Plays a message with control macros: the files of each `.play` step in order, and `onAction` (called on the
    /// keyer queue; the caller hops to its own actor) for each `.action` step once the audio before it has finished,
    /// with the transmitter still keyed; the next audio starts only after it returned `true`. After Esc, a newer message or an error nothing further runs — no action either.
    /// A message without any audio sends nothing (the caller performs its actions itself).
    public func play(steps: [VoiceMessagePlanner.Step], onAction: @escaping @Sendable (CwMessage.Action) -> Bool,
                     listener: Listener?) {
        let files: [JavaPath] = steps.flatMap { step -> [JavaPath] in
            if case .play(let files) = step { files } else { [] }
        }
        let (gen, closed): (Int64, Bool) = state.withLock { s in
            s.generation += 1
            return (s.generation, s.closed)
        }
        if files.isEmpty || closed {
            return
        }
        queue.async { [self] in
            run(gen, steps, onAction, listener)
        }
    }

    private func isCancelled(_ gen: Int64) -> Bool {
        state.withLock { $0.generation != gen }
    }

    private func run(_ gen: Int64, _ steps: [VoiceMessagePlanner.Step],
                     _ onAction: @Sendable (CwMessage.Action) -> Bool, _ listener: Listener?) {
        let cancelled: @Sendable () -> Bool = { [self] in isCancelled(gen) }
        if cancelled() {
            return
        }
        state.withLock { $0.playing = true }
        var error: String?
        var keyed = false
        do {
            try ptt(true)
            keyed = true
            delay(Int64(pttDelayMs()), cancelled)
            stepLoop: for step in steps {
                switch step {
                case .play(let files):
                    for file in files {
                        if cancelled() {
                            break stepLoop
                        }
                        try audio(file, cancelled)
                    }
                case .action(let action):
                    if cancelled() {
                        break stepLoop
                    }
                    // `false` = the action did not complete: the rest of the message is dropped, never played out of
                    // order, and the transmitter is released below.
                    if !onAction(action) {
                        break stepLoop
                    }
                }
            }
        } catch let failure {
            error = String(describing: failure)
        }
        if keyed {
            do {
                try ptt(false)
            } catch let failure {
                error = error ?? "Odklíčování selhalo: " + String(describing: failure)
            }
        }
        state.withLock { $0.playing = false }
        listener?(error)
    }

    /// Java `sleep(ms, cancelled)`: waits in chunks ≤ 10 ms (at least 1 ms) until `ms` elapses
    /// or the message is cancelled. A negative or zero delay does not wait at all.
    private static func sleep(_ ms: Int64, _ cancelled: () -> Bool) {
        let end = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(ms, 0)) &* 1_000_000
        while !cancelled() {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= end { break }
            let left = (end - now) / 1_000_000
            let chunk = min(10, max(1, left))
            Thread.sleep(forTimeInterval: Double(chunk) / 1000.0)
        }
    }

    /// Interrupts the message transmission (Esc).
    public func stop() {
        state.withLock { $0.generation += 1 }
    }

    public var isPlaying: Bool {
        state.withLock { $0.playing }
    }

    /// Stops the message and accepts no more (Java `stop()` + `executor.shutdown()`).
    public func close() {
        state.withLock { s in
            s.generation += 1
            s.closed = true
        }
    }

    /// `close()`, then blocks until the message that was playing has finished — its PTT released. **Swift addition**
    /// (Java `close()` only calls `executor.shutdown()` and returns at once): the app quits only after it, so CAT
    /// never disconnects under a keyed transmitter. Blocks: call it on a thread of your own, never on the main thread
    /// or in Swift's pool.
    public func closeAndDrain() {
        close()
        queue.sync {}
    }
}
