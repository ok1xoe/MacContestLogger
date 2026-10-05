import Foundation
import Testing
@testable import MCLCore

/// `DispatchSemaphore.wait` is "unavailable from asynchronous contexts" — it must not be
/// called directly from the body of an `async` function. An ordinary (non-`async`) function like this one
/// gets around that: the check does not depend on the runtime thread, only on whether the call is
/// lexically inside an `async` function.
private func waitForResponder(_ semaphore: DispatchSemaphore) {
    _ = semaphore.wait(timeout: .now() + 2)
}

@Suite struct SNTPClientTests {
    /// A verbatim port of half of Java `SntpClientTest.timestampRoundTripAndFormula`
    /// (the computation part): the same input, the same hard-coded expected numbers —
    /// `SntpClient.compute(1000, 3100, 3100, 1200)` → `offsetMs` 2000, `roundTripMs`
    /// 200. Before, the formula was recomputed here with the same expression as in the implementation
    /// (`((1500-1000)+(1600-1200))/2`), so a wrong reading of RFC 4330 present
    /// on both sides would pass the test — hence now hard-coded Java numbers, no recomputation.
    @Test func computesOffsetAndRoundTripPerRfc4330() {
        // t1 sent, t2 received at the server, t3 sent by the server, t4 received by us
        // (server 2 s ahead, path 200 ms).
        let r = SNTPClient.compute(t1: 1000, t2: 3100, t3: 3100, t4: 1200)
        #expect(r.offsetMs == 2000)
        #expect(r.roundTripMs == 200)
    }

    @Test func timestampRoundTripsThroughNtpFormat() {
        var buffer = [UInt8](repeating: 0, count: 48)
        SNTPClient.writeTimestamp(into: &buffer, at: 40, millis: 1_700_000_123_456)
        let read = SNTPClient.readTimestamp(buffer, at: 40)
        // The fractional part has a resolution of 1/2^32 s, so a millisecond may differ by 1.
        #expect(abs(read - 1_700_000_123_456) <= 1)
    }

    /// A port of Java `SntpClientTest.queriesFakeServer` — a hermetic server on
    /// the loopback (`LoopbackSntpServer`), no external network, deterministic.
    @Test func queriesFakeServer() async throws {
        let server = try LoopbackSntpServer()
        let done = DispatchSemaphore(value: 0)
        let responder = Thread {
            server.respondOnce(aheadMs: 5_000) // server 5 s ahead
            done.signal()
        }
        responder.start()
        defer {
            waitForResponder(done) // wait until the responder finishes
            server.close()
        }

        // Generous timeout: under load of the parallel suite the responding thread may start late.
        let result = try await SNTPClient.query(host: "127.0.0.1", port: server.port, timeoutMs: 10_000)
        // The SNTP offset estimation error is at most half the round-trip time (RFC 4330,
        // asymmetric path): under suite load t4 is read late and a fixed tolerance of
        // 200 ms was occasionally not enough (315 ms was seen). The tolerance therefore grows
        // with the measured round-trip time; 20 ms extra covers rounding of the NTP stamps.
        // The round-trip time is not bounded from above: under load of the parallel suite (the parity suites load the 3-core
        // CI runner) the t4 stamp is read late and the time exceeded even the query timeout (> 10 s on CI),
        // although the reply arrived in time. It must only be non-negative; the point of the test is carried by the offset, whose
        // tolerance grows from it.
        #expect(result.roundTripMs >= 0)
        #expect(abs(result.offsetMs - 5_000) <= result.roundTripMs / 2 + 20,
                "offset \(result.offsetMs), round-trip time \(result.roundTripMs)")
    }

    /// No Java ancestor — the Java original reads into a fixed 48-byte
    /// `DatagramPacket` buffer, so a short reply cannot occur there.
    /// Swift `readTimestamp` without a length check indexes `bytes[32...47]`, so a
    /// short/corrupt reply from a configured NTP host would crash the process
    /// (see `SNTPClient.QueryError.responseTooShort`). Verifies that `query`
    /// throws an error instead of crashing.
    @Test func shortResponseThrowsInsteadOfCrashing() async throws {
        let server = try LoopbackSntpServer()
        let done = DispatchSemaphore(value: 0)
        let responder = Thread {
            server.respondOnceWithShortResponse(byteCount: 10)
            done.signal()
        }
        responder.start()
        defer {
            waitForResponder(done)
            server.close()
        }

        do {
            _ = try await SNTPClient.query(host: "127.0.0.1", port: server.port, timeoutMs: 10_000)
            Issue.record("expected the error responseTooShort")
        } catch let error as SNTPClient.QueryError {
            #expect(error == .responseTooShort(10))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    /// No Java ancestor — Java `query` takes an `int` port without validation. The Swift version
    /// used to silently fall back to 123 on an invalid port; now it fails, so that a
    /// wrongly configured port does not lead to synchronisation from elsewhere without a trace.
    @Test func invalidPortThrowsInsteadOfFallingBackSilently() async {
        do {
            _ = try await SNTPClient.query(host: "127.0.0.1", port: 0, timeoutMs: 100)
            Issue.record("expected the error invalidPort")
        } catch let error as SNTPClient.QueryError {
            #expect(error == .invalidPort(0))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
