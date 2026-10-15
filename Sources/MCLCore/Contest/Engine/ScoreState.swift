/// Aggregated score state (for the UI and checks). Port of Java record `engine/ScoreState.java`.
///
/// Types keep the Java domains: `int` → `Int32`, `long` → `Int64`. `multByGroup` is a Java
/// `LinkedHashMap` (order of first occurrence of the binding id, the key may be `nil`, comparison by
/// UTF-16); state equality is Java `Map.equals` — regardless of order.
public struct ScoreState: Equatable, Sendable {
    public let qsoCount: Int32
    public let qsoPoints: Int64
    public let multTotal: Int32
    public let multByGroup: JavaLinkedMap<Int32>
    public let bonusPoints: Int64
    public let qtcPoints: Int64
    public let total: Int64
    /// The scores of `scoring.parts` in definition order (Swift only); empty when the contest has no parts.
    public let parts: [PartScore]

    /// The score of one part of a combined contest (`scoring.parts`).
    public struct PartScore: Equatable, Sendable {
        public let id: String?
        /// The part's label, else its id.
        public let label: String
        public let qsoCount: Int32
        public let qsoPoints: Int64
        public let multTotal: Int32
        public let total: Int64

        public init(id: String?, label: String, qsoCount: Int32, qsoPoints: Int64, multTotal: Int32, total: Int64) {
            self.id = id
            self.label = label
            self.qsoCount = qsoCount
            self.qsoPoints = qsoPoints
            self.multTotal = multTotal
            self.total = total
        }
    }

    public init(qsoCount: Int32, qsoPoints: Int64, multTotal: Int32, multByGroup: JavaLinkedMap<Int32>,
                bonusPoints: Int64, qtcPoints: Int64, total: Int64, parts: [PartScore] = []) {
        self.qsoCount = qsoCount
        self.qsoPoints = qsoPoints
        self.multTotal = multTotal
        self.multByGroup = multByGroup
        self.bonusPoints = bonusPoints
        self.qtcPoints = qtcPoints
        self.total = total
        self.parts = parts
    }
}
