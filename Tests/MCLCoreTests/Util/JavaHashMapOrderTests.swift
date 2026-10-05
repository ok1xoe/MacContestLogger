import Testing
@testable import MCLCore

/// `JavaHashMapOrder` = the iteration order of a Java `HashMap<String, …>` (`String.hashCode`, spreading `h ^ (h >>> 16)`, table growth, the difference of `put`
/// (to the end of the bucket, growth after insertion) and `computeIfAbsent` (to the start of the bucket, growth before insertion)
/// and tree bins). The table `JavaHashMapOrderMeasured` is measured on Java.
@Suite struct JavaHashMapOrderTests {

    /// Key from the table: `~` = null, `""` = empty, `\uXXXX` = a UTF-16 unit (like the probe).
    static func decode(_ token: Substring) -> String? {
        if token == "~" { return nil }
        if token == "\"\"" { return "" }
        let units = Array(token.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x5C, i + 5 < units.count, units[i + 1] == 0x75 {
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                out.append(UInt16(hex, radix: 16)!)
                i += 6
            } else {
                out.append(units[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    struct Row {
        let op: String
        let name: String
        let tableLength: Int
        let treeBins: Int
        let keys: [String?]
        let order: [Int]
    }

    static let rows: [Row] = JavaHashMapOrderMeasured.rows.split(separator: "\n").map { line in
        let p = line.split(separator: "\t", omittingEmptySubsequences: false)
        let keys = p[4].isEmpty ? [] : p[4].split(separator: " ").map(decode)
        let order = p[5].isEmpty ? [] : p[5].split(separator: " ").map { Int($0)! }
        return Row(op: String(p[0]), name: String(p[1]), tableLength: Int(p[2])!, treeBins: Int(p[3])!,
                   keys: keys, order: order)
    }

    static func run(_ op: String, _ keys: [String?]) -> JavaHashMapOrder {
        var map = JavaHashMapOrder()
        for key in keys {
            if op == "put" { map.put(key) } else { map.computeIfAbsent(key) }
        }
        return map
    }

    @Test func everyMeasuredOrderMatchesJava() {
        #expect(JavaHashMapOrderMeasured.javaVersion == "21.0.2")
        var failures: [String] = []
        for row in Self.rows {
            let map = Self.run(row.op, row.keys)
            let expected = row.order.map { row.keys[$0] }
            if map.keys != expected || map.tableLength != row.tableLength || map.treeBinCount != row.treeBins {
                failures.append("\(row.op) \(row.name): length \(map.tableLength)/\(row.tableLength), "
                    + "stromy \(map.treeBinCount)/\(row.treeBins)")
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// The table must cover what it exists for: hundreds of keys, table growth,
    /// tree bins in both operations and the difference between `put` and `computeIfAbsent`.
    @Test func measuredTableCoversResizesAndTrees() {
        #expect(Self.rows.count == 88)
        #expect(Self.rows.contains { $0.keys.count >= 1000 && $0.tableLength == 2048 })
        #expect(Self.rows.filter { $0.op == "put" && $0.treeBins > 0 }.count >= 5)
        #expect(Self.rows.filter { $0.op == "cia" && $0.treeBins > 0 }.count >= 5)
        let put13 = Self.rows.first { $0.op == "put" && $0.name == "rand-13" }!
        let cia13 = Self.rows.first { $0.op == "cia" && $0.name == "rand-13" }!
        #expect(put13.tableLength == 32 && cia13.tableLength == 16)
        // 8 keys with an identical hash in a table of 16: put does nothing yet (a tree only from the 9th),
        // computeIfAbsent already wants a tree, and because the table is < 64 it enlarges it
        let put8 = Self.rows.first { $0.op == "put" && $0.name == "samehash-8" }!
        let cia8 = Self.rows.first { $0.op == "cia" && $0.name == "samehash-8" }!
        #expect(put8.tableLength == 16 && cia8.tableLength == 32)
        // a repeated key after crossing the threshold enlarges the table only for computeIfAbsent
        let putRepeat = Self.rows.first { $0.op == "put" && $0.name == "repeat-after-threshold-13" }!
        let ciaRepeat = Self.rows.first { $0.op == "cia" && $0.name == "repeat-after-threshold-13" }!
        #expect(putRepeat.tableLength == 32 && ciaRepeat.tableLength == 32)
    }

    @Test func stringHashCodeIsJavas() {
        #expect(JavaHashMapOrder.hashCode("") == 0)
        #expect(JavaHashMapOrder.hashCode("OK1XOE") == -1_962_453_447)
        #expect(JavaHashMapOrder.hashCode("Aa") == JavaHashMapOrder.hashCode("BB"))
        #expect(JavaHashMapOrder.hashCode("polygenelubricants") == Int32.min)
        // by UTF-16 units: a character outside the BMP = two units
        #expect(JavaHashMapOrder.hashCode("\u{1F600}") == 1_772_899)
        #expect(JavaHashMapOrder.hashCode("K\u{212A}") == 10_815)
    }

    @Test func putAppendsAndComputeIfAbsentPrependsInBucket() {
        // "Aa" and "BB" have the same hash → the same bin; the order in the bin is the iteration order
        var put = JavaHashMapOrder()
        put.put("Aa")
        put.put("BB")
        #expect(put.keys == ["Aa", "BB"])
        var cia = JavaHashMapOrder()
        cia.computeIfAbsent("Aa")
        cia.computeIfAbsent("BB")
        #expect(cia.keys == ["BB", "Aa"])
        // a repeated insertion does not change the order
        cia.computeIfAbsent("Aa")
        put.put("Aa")
        #expect(cia.keys == ["BB", "Aa"] && put.keys == ["Aa", "BB"])
        #expect(cia.count == 2 && cia.contains("Aa") && !cia.contains("AA"))
    }

    @Test func canonicallyEqualKeysAreDistinct() {
        var map = JavaHashMapOrder()
        map.put("K")
        map.put("\u{212A}")
        map.put("\u{00C5}")
        map.put("A\u{030A}")
        #expect(map.count == 4)
    }

    @Test func nullKeyGoesToBucketZero() {
        var map = JavaHashMapOrder()
        map.put("OK1XOE")
        map.put(nil)
        #expect(map.keys.first == .some(nil))
        #expect(map.contains(nil))
    }
}
