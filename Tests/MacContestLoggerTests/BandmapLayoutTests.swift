import AppKit
import Foundation
@testable import MacContestLogger
import MCLAppModel
import MCLCore
import SwiftUI
import Testing

/// The band map's top area (header and top bar) at every window font size and at narrow window widths: measured with
/// `NSHostingController.sizeThatFits` (no window is shown), it never needs more width than the window offers from
/// `BandmapLayout.minWidth` up, so nothing is clipped and the frequency is always whole.
@MainActor @Suite struct BandmapLayoutTests {

    /// The longest texts the header and the top bar can show.
    final class LongestBar: BandmapBarSource {
        func radioName(_ language: LanguageModel) -> String { "Rig 2 · Yaesu FTDX-101D/MP with a long model name" }
        var tunedText: String { BandmapLayout.longestFrequency }
        var txText: String? { BandmapLayout.longestTx }
        var spotFont: Int = BandmapViewport.defaultSpotFont
        func setSpotFont(_ size: Int) { spotFont = size }
        func zoomIn() {}
        func zoomOut() {}
        func resetView() {}
        func showDx() {}
        var filterIsNarrow: Bool? { nil }
        func toggleFilterWidth() {}
        var canJumpToCq: Bool { true }
        func jumpToCq() {}
        var ritText: String { "RIT +9999" }
        func clearRit() {}
        var modeText: String { "RTTY" }
        func setMode(_ command: String) {}
        func editButtons(_ index: Int) {}
    }

    static func language() -> LanguageModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bandmap-layout-\(UUID().uuidString)")
        return LanguageModel(translator: .source, languageDir: dir)
    }

    /// The width the view takes when the window offers `width` (more than `width` = it would be clipped).
    static func neededWidth<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let controller = NSHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: width, height: 2000)).width
    }

    static func top(_ source: LongestBar, _ language: LanguageModel, fontSize: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BandmapHeader(model: source, language: language, fontSize: .constant(fontSize))
            BandmapTopBar(model: source, language: language)
        }
        .environment(\.windowFontSize, fontSize)
    }

    @Test(arguments: [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28])
    func theTopAreaFitsFromTheMinimumWidthUp(fontSize: Int) {
        let language = Self.language()
        let source = LongestBar()
        let minWidth: CGFloat = BandmapLayout.minWidth(fontSize: fontSize)
        for width in [minWidth, minWidth + 37, 460, 640, 900] where width >= minWidth {
            let needed: CGFloat = Self.neededWidth(Self.top(source, language, fontSize: fontSize), width: width)
            #expect(needed <= width + 0.5, "font \(fontSize), window \(width): the top area needs \(needed)")
        }
    }

    @Test func theMinimumWidthGrowsWithTheFontAndKeepsTheBaseAtTheDefault() {
        #expect(BandmapLayout.minWidth(fontSize: WindowFont.defaultSize) == BandmapLayout.baseMinWidth)
        var previous: CGFloat = 0
        for size in WindowFont.minSize...WindowFont.maxSize {
            let width: CGFloat = BandmapLayout.minWidth(fontSize: size)
            #expect(width >= previous)
            #expect(width >= BandmapLayout.monospacedWidth(BandmapLayout.longestFrequency, base: 18, fontSize: size))
            previous = width
        }
        #expect(BandmapLayout.minWidth(fontSize: WindowFont.maxSize) > BandmapLayout.baseMinWidth)
    }

    /// The gate can fail: a row that cannot shrink (the old header, every part fixed) needs more than the window.
    @Test func theMeasureSeesARowThatDoesNotFit() {
        let language = Self.language()
        let source = LongestBar()
        let rigid = HStack(spacing: 6) {
            Text(verbatim: source.radioName(language)).fixedSize()
            Text(verbatim: source.tunedText).windowFont(18, weight: .bold, design: .monospaced).fixedSize()
            Text(verbatim: source.txText ?? "").windowFont(13, weight: .bold, design: .monospaced).fixedSize()
        }
        .environment(\.windowFontSize, 28)
        let width: CGFloat = BandmapLayout.minWidth(fontSize: 28)
        #expect(Self.neededWidth(rigid, width: width) > width)
        // and the real top area, offered less than the frequency itself, reports that it needs more
        let frequency: CGFloat = BandmapLayout.monospacedWidth(BandmapLayout.longestFrequency, base: 18, fontSize: 28)
        let narrow: CGFloat = frequency - 40
        #expect(Self.neededWidth(Self.top(source, language, fontSize: 28), width: narrow) > narrow)
    }
}
