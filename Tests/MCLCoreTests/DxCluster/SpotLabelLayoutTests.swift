import Testing
@testable import MCLCore

/// Port of `dxcluster/SpotLabelLayoutTest` (10).
@Suite struct SpotLabelLayoutTests {

    private static func row(_ i: Int, _ y: Float) -> SpotLabelLayout.Row {
        SpotLabelLayout.Row(index: i, trueY: y)
    }

    /// `labelY` of the output label of the given input index.
    private static func labelY(_ out: [SpotLabelLayout.Placed], _ index: Int) -> Float {
        out.first { $0.index == index }?.labelY ?? .nan
    }

    private static func near(_ actual: Float, _ expected: Float) -> Bool {
        abs(actual - expected) <= 0.001
    }

    @Test func emptyInput() {
        #expect(SpotLabelLayout.place([], rowH: 10, minY: 0, maxY: 100).isEmpty)
    }

    @Test func singleSpotStaysAtTrueY() {
        let out = SpotLabelLayout.place([Self.row(0, 50)], rowH: 10, minY: 0, maxY: 100)
        #expect(out.count == 1)
        #expect(Self.near(out[0].labelY, 50))
        #expect(Self.near(out[0].trueY, 50))
    }

    @Test func farApartSpotsUnchanged() {
        // spacing 30 >= rowH 10 → unchanged
        let out = SpotLabelLayout.place([Self.row(0, 20), Self.row(1, 50)], rowH: 10, minY: 0, maxY: 100)
        #expect(Self.near(Self.labelY(out, 0), 20))
        #expect(Self.near(Self.labelY(out, 1), 50))
    }

    @Test func twoCloseSpotsSplitSymmetricallyAroundMean() {
        // two spots at 50 and 54, rowH 10 → centre 52, spacing 10 → 47 and 57
        let out = SpotLabelLayout.place([Self.row(0, 50), Self.row(1, 54)], rowH: 10, minY: 0, maxY: 100)
        #expect(Self.near(Self.labelY(out, 0), 47))
        #expect(Self.near(Self.labelY(out, 1), 57))
    }

    @Test func denseClusterStacksContiguouslyCenteredOnMean() {
        // 5 spots close together around 50 (48,49,50,51,52 → mean 50), rowH 10
        // → contiguous rows of 10, centred: 30,40,50,60,70
        let rows = [Self.row(0, 48), Self.row(1, 49), Self.row(2, 50), Self.row(3, 51), Self.row(4, 52)]
        let out = SpotLabelLayout.place(rows, rowH: 10, minY: 0, maxY: 200)
        let expected: [Float] = [30, 40, 50, 60, 70]
        for (index, y) in expected.enumerated() {
            #expect(Self.near(Self.labelY(out, index), y))
        }
    }

    @Test func clampsToTopEdge() {
        // a cluster right at the top edge → nothing may be above minY
        let rows = [Self.row(0, 2), Self.row(1, 3), Self.row(2, 4)]
        let out = SpotLabelLayout.place(rows, rowH: 10, minY: 0, maxY: 200)
        for p in out {
            #expect(p.labelY >= 0, "labelY \(p.labelY) pod minY")
        }
        // the first label exactly at minY (shifted down)
        #expect(Self.near(Self.labelY(out, 0), 0))
        #expect(Self.near(Self.labelY(out, 1), 10))
        #expect(Self.near(Self.labelY(out, 2), 20))
    }

    @Test func clampsToBottomEdge() {
        // a cluster right at the bottom edge → nothing may be below maxY
        let rows = [Self.row(0, 96), Self.row(1, 97), Self.row(2, 98)]
        let out = SpotLabelLayout.place(rows, rowH: 10, minY: 0, maxY: 100)
        for p in out {
            #expect(p.labelY <= 100, "labelY \(p.labelY) above maxY")
        }
        #expect(Self.near(Self.labelY(out, 0), 80))
        #expect(Self.near(Self.labelY(out, 1), 90))
        #expect(Self.near(Self.labelY(out, 2), 100))
    }

    @Test func overflowStartsAtTop() {
        // more members than fit: 20 spots, rowH 10, area 0..100 (11 fit)
        // → starts at minY and runs continuously down
        let rows: [SpotLabelLayout.Row] = (0..<20).map { Self.row($0, 50) }
        let out = SpotLabelLayout.place(rows, rowH: 10, minY: 0, maxY: 100)
        #expect(out.count == 20)
        #expect(Self.near(Self.labelY(out, 0), 0))
        #expect(Self.near(Self.labelY(out, 1), 10))
    }

    @Test func neighboringClustersPushApart() {
        // two groups that would overlap after symmetric spreading are pushed apart
        // group A around 40 (38,42), group B around 50 (48,52), rowH 10
        let rows = [Self.row(0, 38), Self.row(1, 42), Self.row(2, 48), Self.row(3, 52)]
        let out = SpotLabelLayout.place(rows, rowH: 10, minY: 0, maxY: 200)
        // the sorted labelY must have spacing >= rowH
        let ys: [Float] = out.map(\.labelY).sorted()
        for i in 1..<ys.count {
            #expect(ys[i] - ys[i - 1] >= 10 - 0.001, "spacing \(ys[i] - ys[i - 1]) < rowH")
        }
    }

    @Test func preservesInputIndex() {
        let out = SpotLabelLayout.place([Self.row(7, 50), Self.row(3, 54)], rowH: 10, minY: 0, maxY: 100)
        // both indices present
        #expect(Self.near(Self.labelY(out, 7), 47))
        #expect(Self.near(Self.labelY(out, 3), 57))
    }
}
