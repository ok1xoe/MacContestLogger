import Foundation
import MCLCore

/// The signal features of the spectrum display (N1MM+ Spectrum Display): the red signal markers and their filter,
/// the spots over the spectrum, Shift+Up/Down to the next signal, the CQ frequency finder and the `@frequency` spots
/// of unknown signals. Nothing here transmits; the rig is only tuned and the spots stay local.
extension WaterfallModel {

    /// The mode the tuning tolerance and the CQ width go by.
    var currentMode: Mode {
        boundState?.mode ?? .cw
    }

    /// The tuning tolerance of the mode (Configurer → Telnet; N1MM: spots and signals within it are one).
    var toleranceHz: Double {
        Double(config.config.dxCluster.tuningToleranceHz(currentMode))
    }

    /// The spots on the frequencies of the current picture.
    var spectrumSpots: [SpectrumSpot] {
        guard let picture, let spotsProvider else { return [] }
        let lo: Double = Swift.min(picture.axis.hz(atBin: 0), picture.axis.hz(atBin: Double(picture.count - 1)))
        let hi: Double = Swift.max(picture.axis.hz(atBin: 0), picture.axis.hz(atBin: Double(picture.count - 1)))
        return spotsProvider(lo - toleranceHz, hi + toleranceHz)
    }

    /// The red signal markers (N1MM „Show red signal markers" with its filter).
    public var markers: [SpectrumSignal] {
        guard let picture, setup.flag(.showMarkers) else { return [] }
        return SpectrumSignals.markers(picture.signals, spots: spectrumSpots, filter: setup.markerFilter,
                                       toleranceHz: toleranceHz)
    }

    /// The spot labels over the spectrum (N1MM „Show these Spots", „Show only spots you can hear"); the tuned one is
    /// framed.
    public var overlaySpots: [SpectrumOverlaySpot] {
        guard let picture, setup.flag(.showSpots) else { return [] }
        let lo: Double = picture.hz(atFraction: 0)
        let hi: Double = picture.hz(atFraction: 1)
        return SpectrumSignals.overlay(spectrumSpots, signals: picture.signals, lowHz: Swift.min(lo, hi),
                                       highHz: Swift.max(lo, hi), onlyHeard: setup.flag(.onlyHeardSpots),
                                       toleranceHz: toleranceHz, tunedHz: Double(dialHz))
    }

    /// N1MM Shift+Up (`direction` +1, higher) / Shift+Down (−1) from `fromHz` (the entry window's frequency, else
    /// the dial): the next signal that is not a dupe or non-workable (with the CQ markers shown: the next CQ
    /// frequency). `false` = no spectrum (the window is closed or has no line yet), the keys then tune as plain arrows;
    /// at the edge of the spectrum nothing moves (N1MM stops there).
    public func jump(direction: Int, fromHz: Int64) -> Bool {
        guard isOpen, let picture else { return false }
        let from: Double = Double(fromHz > 0 ? fromHz : dialHz)
        let targets: [Double]
        if cqFrequencies.isEmpty {
            targets = SpectrumSignals.jumpTargets(picture.signals, spots: spectrumSpots, filter: setup.markerFilter,
                                                  toleranceHz: toleranceHz)
        } else {
            targets = cqFrequencies
        }
        if let next = SpectrumSignals.next(from: from, direction: direction, targets: targets,
                                           minStepHz: Swift.max(picture.binWidthHz, toleranceHz / 2)) {
            tuneRig(Int64(next.rounded()))
        }
        return true
    }

    /// N1MM's CQ button: shows up to five quiet frequencies (best first, numbered), or clears them when shown.
    public func toggleCqFrequencies() {
        if !cqFrequencies.isEmpty {
            cqFrequencies = []
            return
        }
        let mode: Mode = currentMode
        let width: Double = CqFrequencyFinder.widthHz(cw: mode == .cw, phone: !mode.isDigital && mode != .cw)
        cqFrequencies = pipeline.cqFrequencies(settings: pipelineSettings, widthHz: width)
    }

    /// The position of the CQ frequencies along the frequency axis with their rank (1…5).
    public var cqMarkers: [(rank: Int, fraction: Double)] {
        cqFrequencies.enumerated().compactMap { index, hz in
            fraction(ofHz: hz).map { (index + 1, $0) }
        }
    }

    /// A new picture: every 2 s the `@frequency` spots follow the unknown signals (when the option is on).
    func pictureChanged() {
        guard setup.flag(.unknownAsSpots) else {
            withdrawUnknownSpots()
            return
        }
        unknownCountdown -= 1
        guard unknownCountdown <= 0, let picture else { return }
        unknownCountdown = 2_000 / Self.refreshMs
        let spots: [SpectrumSpot] = spectrumSpots
        publishUnknown?(SpectrumSignals.unknownSpots(picture.signals, spots: spots, toleranceHz: toleranceHz))
        publishedUnknown = true
    }

    /// The `@frequency` spots go (the option was turned off, the window closed).
    func withdrawUnknownSpots() {
        guard publishedUnknown else { return }
        publishedUnknown = false
        unknownCountdown = 0
        publishUnknown?([])
    }
}

extension WaterfallModel {

    /// A click on a spot label (N1MM): the rig goes to the spot (with its split and call, like the band map).
    public func tuneToSpot(_ spot: SpectrumSpot) {
        if let dx = rig.spotForCall(spot.call) {
            if bindsOtherRadio {
                rig.tuneOtherToSpot(dx)
            } else {
                rig.tuneToSpot(dx)
            }
        } else {
            tuneRig(Int64(spot.freqHz.rounded()))
        }
    }
}
