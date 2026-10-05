/// `overlaps(all, seg)` of the Band plan tab (`ui/configurer/BandPlanTab.kt:34-46`): does the row at `index`
/// overlap another row of the **same** region (exact `==`, unlike the case-insensitive
/// `BandPlanFile.overlaps`)? Bounds are the Kotlin-trimmed `toDoubleOrNull` values; a row whose own bound is not
/// a number never overlaps, another row with a non-numeric bound is ignored, a touch is not an overlap (strict
/// `f < ot && of < t`). Kotlin compares row identity (`o !== seg`); Swift compares the index.
public enum BandPlanOverlap {

    public static func overlaps(_ all: [BandSegmentDraft], _ index: Int) -> Bool {
        guard all.indices.contains(index) else { return false }
        let segment = all[index]
        guard let from = segment.fromVal(), let to = segment.toVal() else { return false }
        for other in all.indices where other != index {
            let row = all[other]
            guard row.region.utf16.elementsEqual(segment.region.utf16),
                  let otherFrom = row.fromVal(), let otherTo = row.toVal() else { continue }
            if from < otherTo && otherFrom < to {
                return true
            }
        }
        return false
    }
}
