import Testing

extension Trait where Self == TimeLimitTrait {
    /// A guard against hangs for I/O tests (own threads, sockets, processes, pty) — not a speed measure.
    ///
    /// The time `timeLimit` runs from the start of the test and also counts waiting to return to the shared Swift pool after each
    /// `await`. Swift Testing starts all tests at once, so under `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`
    /// (one pool thread) and on CI with 3 vCPUs every continuation of an I/O test queues behind CPU-heavy
    /// parity tests; an I/O test thus takes almost as long as the whole run (~2 min locally, ~6.5 min on GitHub runners) and a shorter bound brought it down even though
    /// nothing was hung. The bound is therefore above the length of the whole run.
    static var ioSafetyNet: Self { .timeLimit(.minutes(30)) }
}
