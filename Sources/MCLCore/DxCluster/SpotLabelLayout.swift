/// Layout of spot labels in the Bandmap so that they do not overlap (Java `dxcluster.SpotLabelLayout`).
///
/// Each spot has a "true" y-position `Row.trueY` by its frequency. When two labels are closer than
/// `rowH`, they spread symmetrically around the centroid (mean) of the group; neighbouring groups push
/// each other away. The result is clamped into the area `[minY, maxY]`. Pure logic without UI, deterministic.
///
/// Arithmetic is Java `float` step by step (`Float` IEEE 754, same order of operations and `int`
/// → `float` conversion), stable sorting by `Float.compare` (`-0.0 < 0.0`, `NaN` largest), `Math.max(float)`
/// is Java's (`NaN` wins, `max(-0.0, 0.0) = 0.0`).
public enum SpotLabelLayout {

    /// Input row: spot index + its "true" y by frequency.
    public struct Row: Equatable, Sendable {
        public let index: Int
        public let trueY: Float

        public init(index: Int, trueY: Float) {
            self.index = index
            self.trueY = trueY
        }
    }

    /// Output row: spot index, frequency anchor `trueY`, shifted `labelY`.
    public struct Placed: Equatable, Sendable {
        public let index: Int
        public let trueY: Float
        public let labelY: Float

        public init(index: Int, trueY: Float, labelY: Float) {
            self.index = index
            self.trueY = trueY
            self.labelY = labelY
        }
    }

    /// Internal cluster of contiguous labels stacked by `rowH`, centred around `center`.
    private struct Cluster {
        var members: [Row]
        var sumTrueY: Float

        init(_ row: Row) {
            members = [row]
            sumTrueY = row.trueY
        }

        var center: Float {
            sumTrueY / Float(Int32(truncatingIfNeeded: members.count))
        }

        /// y of the first (topmost) label of the cluster.
        func top(_ rowH: Float) -> Float {
            center - half(rowH)
        }

        /// y of the last (bottommost) label of the cluster.
        func bottom(_ rowH: Float) -> Float {
            center + half(rowH)
        }

        /// Java `(members.size() - 1) * rowH / 2f`.
        private func half(_ rowH: Float) -> Float {
            let span: Float = Float(Int32(truncatingIfNeeded: members.count - 1)) * rowH
            return span / 2
        }

        mutating func absorb(_ other: Cluster) {
            members.append(contentsOf: other.members)
            sumTrueY += other.sumTrueY
        }
    }

    /// - Parameters:
    ///   - rows: spots with `trueY` (need not be sorted)
    ///   - rowH: minimum vertical spacing of two labels (row height)
    ///   - minY: upper bound of the area
    ///   - maxY: lower bound of the area
    /// - Returns: for each input spot its `labelY`; output order = ascending by `labelY`
    public static func place(_ rows: [Row], rowH: Float, minY: Float, maxY: Float) -> [Placed] {
        if rows.isEmpty { return [] }

        // Stable sort by `Float.compare` (Java `List.sort` = TimSort).
        let sorted: [Row] = rows.enumerated().sorted { left, right in
            let order = compare(left.element.trueY, right.element.trueY)
            return order != 0 ? order < 0 : left.offset < right.offset
        }.map(\.element)

        // Merge neighbouring clusters while they overlap; a merge can trigger a collision
        // with the previous one → propagate back.
        var clusters: [Cluster] = []
        for row in sorted {
            var cluster = Cluster(row)
            while let prev = clusters.last {
                let reach: Float = prev.bottom(rowH) + rowH
                if reach > cluster.top(rowH) {
                    var merged = prev
                    merged.absorb(cluster)
                    cluster = merged
                    clusters.removeLast()
                } else {
                    break
                }
            }
            clusters.append(cluster)
        }

        // Expand the clusters into individual labels.
        var placed: [Placed] = []
        for cluster in clusters {
            var y: Float = cluster.top(rowH)
            for member in cluster.members {
                placed.append(Placed(index: member.index, trueY: member.trueY, labelY: y))
                y += rowH
            }
        }

        // Clamp the whole column into [minY, maxY].
        let first: Float = placed[0].labelY
        let last: Float = placed[placed.count - 1].labelY
        var shift: Float = 0
        if first < minY {
            shift = minY - first
        } else if last > maxY {
            shift = javaMax(maxY - last, minY - first) // if it does not fit, the top edge takes priority
        }
        if shift != 0 {
            return placed.map { Placed(index: $0.index, trueY: $0.trueY, labelY: $0.labelY + shift) }
        }
        return placed
    }

    /// Java `Float.compare`: `-0.0 < 0.0`, `NaN` is the largest and equals itself.
    static func compare(_ a: Float, _ b: Float) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let left: Int32 = a.isNaN ? 0x7FC0_0000 : Int32(bitPattern: a.bitPattern)
        let right: Int32 = b.isNaN ? 0x7FC0_0000 : Int32(bitPattern: b.bitPattern)
        return left == right ? 0 : (left < right ? -1 : 1)
    }

    /// Java `Math.max(float, float)`.
    static func javaMax(_ a: Float, _ b: Float) -> Float {
        if a.isNaN { return a }
        if b.isNaN { return b }
        if a == 0 && b == 0 {
            return a.sign == .minus ? b : a
        }
        return a >= b ? a : b
    }
}
