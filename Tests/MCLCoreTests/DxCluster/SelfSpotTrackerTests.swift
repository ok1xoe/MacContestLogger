import Testing
@testable import MCLCore

/// `SelfSpotTracker` against the effect sequence of `ui/EntryPanel.kt` of v1.1.1 (`:150-153`, `:204-211`, `:235-256`):
/// the anchor when the call turns non-blank, the self-spot at the anchor with the call cleared, the auto-prefill
/// within 100 Hz and `callFromSpot`.
@Suite struct SelfSpotTrackerTests {

    static let threshold: Int64 = 2_500

    static func spot(_ call: String, _ freq: Int) -> DxSpot {
        DxSpot(spotter: "S", freqHz: freq, dxCall: call, comment: "")
    }

    static func noSpot(_ freq: Int, _ tolerance: Int) -> DxSpot? { nil }

    /// Typed call, tuned away by at least the threshold → self-spot at the anchor and the call is cleared.
    @Test func typedCallIsSelfSpottedAtTheAnchorAndCleared() {
        var tracker = SelfSpotTracker()
        tracker.typed()
        tracker.callChanged("O", tunedFreqHz: 14_025_000)
        tracker.callChanged("OK1ABC", tunedFreqHz: 14_025_300)
        #expect(tracker.anchorHz == 14_025_000, "the anchor is where the call started")
        #expect(tracker.tunedChanged(14_027_499, call: "OK1ABC", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == nil)
        #expect(tracker.tunedChanged(14_027_500, call: "OK1ABC", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == .selfSpot(call: "OK1ABC", atHz: 14_025_000))
        #expect(tracker.anchorHz == 0)
        // The panel clears the field; the following anchor effect is a no-op.
        tracker.callChanged("", tunedFreqHz: 14_027_500)
        #expect(tracker.anchorHz == 0)
    }

    /// Downward distance counts the same (`abs`), and the raw call text goes out (normalised by `storeSpot`).
    @Test func distanceIsAbsoluteAndTheCallIsRaw() {
        var tracker = SelfSpotTracker()
        tracker.callChanged(" ok1abc ", tunedFreqHz: 7_010_000)
        #expect(tracker.tunedChanged(7_007_500, call: " ok1abc ", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == .selfSpot(call: " ok1abc ", atHz: 7_010_000))
    }

    /// A call from a spot is never self-spotted and stays in the field.
    @Test func callFromSpotIsNotSelfSpotted() {
        var tracker = SelfSpotTracker()
        tracker.prefilledFromSpot()
        tracker.callChanged("DL1ABC", tunedFreqHz: 14_025_000)
        #expect(tracker.callFromSpot)
        #expect(tracker.tunedChanged(14_100_000, call: "DL1ABC", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == nil)
        #expect(tracker.anchorHz == 14_025_000)
        // Typing makes it the operator's call; the anchor stays where the call started.
        tracker.typed()
        #expect(tracker.tunedChanged(14_100_001, call: "DL1ABD", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == .selfSpot(call: "DL1ABD", atHz: 14_025_000))
    }

    /// The anchor is only taken when the call turns non-blank: tuned at 0 there is no anchor and no self-spot until
    /// the call is cleared and typed again.
    @Test func noAnchorWithoutFrequency() {
        var tracker = SelfSpotTracker()
        tracker.callChanged("OK1ABC", tunedFreqHz: 0)
        #expect(tracker.anchorHz == 0)
        tracker.callChanged("OK1ABCD", tunedFreqHz: 14_025_000)
        #expect(tracker.anchorHz == 0, "still non-blank — the effect key did not change")
        #expect(tracker.tunedChanged(21_000_000, call: "OK1ABCD", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == nil)
        tracker.callChanged("", tunedFreqHz: 21_000_000)
        tracker.callChanged("O", tunedFreqHz: 21_000_000)
        #expect(tracker.anchorHz == 21_000_000)
    }

    /// Blank call and `f > 0`: the nearest spot within 100 Hz fills the field and marks it as from a spot.
    @Test func emptyCallIsPrefilledFromTheNearestSpot() {
        var tracker = SelfSpotTracker()
        var asked: [(Int, Int)] = []
        let action = tracker.tunedChanged(14_025_040, call: "", thresholdHz: Self.threshold) { freq, tolerance in
            asked.append((freq, tolerance))
            return Self.spot("dl1abc", 14_025_000)
        }
        #expect(action == .prefill(call: "dl1abc"))
        #expect(asked.count == 1 && asked[0] == (14_025_040, 100))
        #expect(tracker.callFromSpot)
        #expect(tracker.anchorHz == 14_025_040, "anchored where the call appeared")
        // Tuning away with a prefilled call never self-spots.
        #expect(tracker.tunedChanged(14_100_000, call: "dl1abc", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == nil)
    }

    /// No frequency or no spot: nothing; `f <= 0` does not even ask the buffer.
    @Test func noPrefillWithoutFrequencyOrSpot() {
        var tracker = SelfSpotTracker()
        var asked = 0
        let counting: (Int, Int) -> DxSpot? = { _, _ in
            asked += 1
            return nil
        }
        #expect(tracker.tunedChanged(0, call: "", thresholdHz: Self.threshold, nearest: counting) == nil)
        #expect(tracker.tunedChanged(-5, call: "\u{00A0}", thresholdHz: Self.threshold, nearest: counting) == nil)
        #expect(asked == 0)
        #expect(tracker.tunedChanged(14_025_000, call: "", thresholdHz: Self.threshold, nearest: counting) == nil)
        #expect(asked == 1)
        #expect(!tracker.callFromSpot)
    }

    /// A typed call replaced by a band map click (`prefillCall`) keeps its old anchor (the key stays non-blank);
    /// typing afterwards and tuning away from that old anchor self-spots — Kotlin behaviour.
    @Test func spotClickOverATypedCallKeepsTheOldAnchor() {
        var tracker = SelfSpotTracker()
        tracker.callChanged("OK1ABC", tunedFreqHz: 14_010_000)
        tracker.prefilledFromSpot()
        tracker.callChanged("DL1XYZ", tunedFreqHz: 14_020_000)
        #expect(tracker.tunedChanged(14_020_000, call: "DL1XYZ", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == nil)
        #expect(tracker.anchorHz == 14_010_000)
        tracker.typed()
        #expect(tracker.tunedChanged(14_020_100, call: "DL1XYZ", thresholdHz: Self.threshold, nearest: Self.noSpot)
            == .selfSpot(call: "DL1XYZ", atHz: 14_010_000))
    }

    /// Kotlin `isBlank`: NBSP alone counts as an empty call (prefill, no anchor).
    @Test func kotlinBlankCall() {
        var tracker = SelfSpotTracker()
        tracker.callChanged("\u{00A0}", tunedFreqHz: 14_025_000)
        #expect(tracker.anchorHz == 0)
        let action = tracker.tunedChanged(14_025_000, call: "\u{00A0}", thresholdHz: Self.threshold) { _, _ in
            Self.spot("OK1ABC", 14_025_000)
        }
        #expect(action == .prefill(call: "OK1ABC"))
    }
}
