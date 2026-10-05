import Testing
@testable import MCLCore

/// Port of `dxcluster/SpotColorClassifierTest` (4).
@Suite struct SpotColorClassifierTests {

    @Test func dupeIsGrayRegardlessOfMultCount() {
        #expect(SpotColorClassifier.classify(dupe: true, newMultCount: 0) == .dupe)
        #expect(SpotColorClassifier.classify(dupe: true, newMultCount: 1) == .dupe)
        #expect(SpotColorClassifier.classify(dupe: true, newMultCount: 3) == .dupe)
    }

    @Test func noMultIsGood() {
        #expect(SpotColorClassifier.classify(dupe: false, newMultCount: 0) == .good)
    }

    @Test func oneMult() {
        #expect(SpotColorClassifier.classify(dupe: false, newMultCount: 1) == .oneMult)
    }

    @Test func twoOrMoreMult() {
        #expect(SpotColorClassifier.classify(dupe: false, newMultCount: 2) == .multiMult)
        #expect(SpotColorClassifier.classify(dupe: false, newMultCount: 4) == .multiMult)
    }
}
