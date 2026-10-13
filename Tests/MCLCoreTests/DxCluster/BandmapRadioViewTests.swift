import Foundation
import Testing
@testable import MCLCore

/// The band map's radio and navigation geometry (post-port, N1MM): the lowest frequency at the bottom, the arrow
/// markers, the receiver's filter, the band plan segment of „Go to Bottom/Top Of Band" and the zoom keys.
@Suite struct BandmapRadioViewTests {

    static let height: Float = 600

    @Test func theLowestFrequencyAtTheBottomFlipsEveryPosition() {
        var window = BandmapViewport(loHz: 14_000_000, hiHz: 14_100_000)
        let top: Float = window.yAt(14_000_000, height: Self.height)
        #expect(top == BandmapViewport.padTop)
        window.lowestAtBottom = true
        #expect(window.yAt(14_000_000, height: Self.height) == Self.height - BandmapViewport.padBottom)
        #expect(window.yAt(14_100_000, height: Self.height) == BandmapViewport.padTop)
        #expect(window.yAt(14_025_000, height: Self.height) > window.yAt(14_075_000, height: Self.height))
        // `freqAt` is the inverse of `yAt` in both directions.
        let y: Float = window.yAt(14_025_000, height: Self.height)
        #expect(abs(window.freqAt(y, height: Self.height) - 14_025_000) <= 4)
        // The drag zoom keeps lo below hi whichever end is higher on screen.
        let upper: Float = window.yAt(14_080_000, height: Self.height)
        let lower: Float = window.yAt(14_020_000, height: Self.height)
        let zoomed: Bool = window.dragZoom(from: upper, to: lower, height: Self.height, bounds: 14_000_000...14_350_000)
        #expect(zoomed)
        #expect(abs(window.loHz - 14_020_000) <= 4)
        #expect(abs(window.hiHz - 14_080_000) <= 4)
        // The labels follow: the higher frequency is placed above.
        let spots: [DxSpot] = [DxSpot(spotter: "A", freqHz: 14_030_000, dxCall: "LOW", comment: ""),
                               DxSpot(spotter: "A", freqHz: 14_070_000, dxCall: "HIGH", comment: "")]
        let placed: [SpotPlacement] = BandmapLayout.place(spots: spots, viewport: window, height: Self.height,
                                                          rowH: 14)
        #expect(placed.map(\.spot.dxCall) == ["HIGH", "LOW"])
    }

    @Test func markersAreHitLeftOfTheAxisNearTheirFrequency() {
        let window = BandmapViewport(loHz: 14_000_000, hiHz: 14_100_000)
        let y: Float = window.yAt(14_030_000, height: Self.height)
        #expect(window.hitsMarker(14_030_000, x: 40, y: y + 9, axisX: 60, height: Self.height))
        #expect(!window.hitsMarker(14_030_000, x: 40, y: y + 11, axisX: 60, height: Self.height))
        #expect(!window.hitsMarker(14_030_000, x: 61, y: y, axisX: 60, height: Self.height))
        #expect(!window.hitsMarker(14_200_000, x: 40, y: y, axisX: 60, height: Self.height))
        #expect(!window.hitsMarker(nil, x: 40, y: y, axisX: 60, height: Self.height))
    }

    @Test func thePassbandSitsOnTheSidebandOrAroundTheFrequency() {
        #expect(BandmapViewport.passband(rxHz: 14_200_000, passbandHz: 2_400, rawMode: "USB")
            == 14_200_000...14_202_400)
        #expect(BandmapViewport.passband(rxHz: 7_100_000, passbandHz: 2_400, rawMode: "LSB")
            == 7_097_600...7_100_000)
        #expect(BandmapViewport.passband(rxHz: 14_074_000, passbandHz: 3_000, rawMode: "PKTUSB")
            == 14_074_000...14_077_000)
        #expect(BandmapViewport.passband(rxHz: 14_025_000, passbandHz: 500, rawMode: "CW")
            == 14_024_750...14_025_250)
        #expect(BandmapViewport.passband(rxHz: 14_025_000, passbandHz: 0, rawMode: "CW") == nil)
    }

    @Test func theSubBandIsTheSegmentOfTheTunedFrequencyOrTheBand() {
        let segments: [BandPlan.Segment] = [
            BandPlan.Segment(category: .cw, lowHz: 14_000_000, highHz: 14_070_000),
            BandPlan.Segment(category: .digi, lowHz: 14_070_000, highHz: 14_099_000),
            BandPlan.Segment(category: .phone, lowHz: 14_101_000, highHz: 14_350_000),
        ]
        let bounds: ClosedRange<Int64> = 14_000_000...14_350_000
        #expect(BandmapViewport.subBand(tunedHz: 14_025_000, segments: segments, bounds: bounds)
            == 14_000_000...14_070_000)
        #expect(BandmapViewport.subBand(tunedHz: 14_070_000, segments: segments, bounds: bounds)
            == 14_070_000...14_099_000)
        #expect(BandmapViewport.subBand(tunedHz: 14_250_000, segments: segments, bounds: bounds)
            == 14_101_000...14_350_000)
        // Between segments (the beacon gap) and without a plan: the whole band.
        #expect(BandmapViewport.subBand(tunedHz: 14_100_000, segments: segments, bounds: bounds) == bounds)
        #expect(BandmapViewport.subBand(tunedHz: 14_025_000, segments: [], bounds: bounds) == bounds)
    }

    static func key(_ code: UInt16, _ chars: String, flags: UInt = 0,
                    kind: MacKeyEvent.Kind = .keyDown) -> MacKeyEvent {
        MacKeyEvent(kind: kind, keyCode: code, characters: chars, charactersIgnoringModifiers: chars,
                    modifierFlags: flags)
    }

    @Test func zoomKeysAreTheKeypadAndCommandEqualsMinus() {
        let command: UInt = 1 << 20
        #expect(BandmapZoomKey.decode(Self.key(69, "+")) == 1)
        #expect(BandmapZoomKey.decode(Self.key(78, "-")) == -1)
        #expect(BandmapZoomKey.decode(Self.key(78, "-", kind: .keyUp)) == -1)
        #expect(BandmapZoomKey.decode(Self.key(24, "=", flags: command)) == 1)
        #expect(BandmapZoomKey.decode(Self.key(30, "+", flags: command)) == 1)
        #expect(BandmapZoomKey.decode(Self.key(27, "-", flags: command)) == -1)
        // Without Command the main keyboard's = and - are left alone; Ctrl/Option combinations too.
        #expect(BandmapZoomKey.decode(Self.key(24, "=")) == nil)
        #expect(BandmapZoomKey.decode(Self.key(27, "-")) == nil)
        #expect(BandmapZoomKey.decode(Self.key(69, "+", flags: 1 << 18)) == nil)
        #expect(BandmapZoomKey.decode(Self.key(27, "-", flags: command | (1 << 19))) == nil)
        #expect(BandmapZoomKey.decode(MacKeyEvent(kind: .flagsChanged, keyCode: 69)) == nil)
    }
}
