/// Classification of a spot's colour in the Bandmap by dupe and the number of new multipliers (Java
/// `dxcluster.SpotColorClassifier`). Colours: `dupe` = grey, `good` = blue, `oneMult` = red,
/// `multiMult` = green.
public enum SpotColorClassifier {

    /// Java `SpotColorKey` (`DUPE`, `GOOD`, `ONE_MULT`, `MULTI_MULT`).
    public enum SpotColorKey: String, Sendable, CaseIterable {
        case dupe = "DUPE"
        case good = "GOOD"
        case oneMult = "ONE_MULT"
        case multiMult = "MULTI_MULT"
    }

    /// - Parameters:
    ///   - dupe: whether the spot is a duplicate
    ///   - newMultCount: number of NEW multipliers the QSO would bring
    public static func classify(dupe: Bool, newMultCount: Int) -> SpotColorKey {
        if dupe { return .dupe }
        if newMultCount >= 2 { return .multiMult }
        if newMultCount == 1 { return .oneMult }
        return .good
    }
}
