import Testing
@testable import MCLCore

/// `JavaLinkedMap` = Java `LinkedHashMap<String, V>`: insertion order, keys by UTF-16,
/// `null` key and `null` value.
@Suite struct JavaLinkedMapTests {

    @Test func putKeepsFirstPositionAndReplacesValue() {
        var map = JavaLinkedMap<Int>()
        map.put("a", 1)
        map.put("b", 2)
        map.put("a", 3)
        #expect(map.keys == ["a", "b"])
        #expect(map["a"] == 3)
        #expect(map.count == 2)
    }

    @Test func duplicateKeysInInitDoNotTrap() {
        // A dictionary literal with the same key would crash; here Java put applies.
        let map = JavaLinkedMap<Int>([("x", 1), ("y", 2), ("x", 9)])
        #expect(map.keys == ["x", "y"])
        #expect(map["x"] == 9)
    }

    @Test func canonicallyEqualKeysStayDistinct() {
        let map = JavaLinkedMap<Int>([("K", 1), ("\u{212A}", 2), ("\u{00C5}", 3), ("A\u{030A}", 4)])
        #expect(map.count == 4)
        #expect(map["K"] == 1)
        #expect(map["\u{212A}"] == 2)
        #expect(map["\u{00C5}"] == 3)
        #expect(map["A\u{030A}"] == 4)
        #expect(map["\u{212B}"] == nil)
    }

    @Test func nilKeyAndNilValue() {
        let map = JavaLinkedMap<Int>([(nil, 5), ("n", nil)])
        #expect(map[nil] == 5)
        #expect(map.containsKey(nil))
        #expect(map["n"] == nil)
        #expect(map.containsKey("n"))
        #expect(!map.containsKey("zz"))
        #expect(map.entries.map(\.key) == [nil, "n"])
    }

    @Test func equalityIgnoresOrderLikeJavaMapEquals() {
        let a = JavaLinkedMap<Int>([("a", 1), ("b", nil)])
        let b = JavaLinkedMap<Int>([("b", nil), ("a", 1)])
        let c = JavaLinkedMap<Int>([("a", 1), ("c", nil)])
        #expect(a == b)
        #expect(a != c)
        #expect(JavaLinkedMap<Int>([("K", 1)]) != JavaLinkedMap<Int>([("\u{212A}", 1)]))
    }
}
