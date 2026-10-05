import Foundation
import Testing
@testable import MCLCore

/// `JavaStringKey`: a dictionary key with Java `String` equality (by UTF-16 units), without
/// allocating an array of units on every lookup.
@Suite struct JavaStringKeyTests {

    /// Canonically equal texts (`Å` U+00C5 / `A` + U+030A, `K` / KELVIN SIGN) are different in Java.
    @Test func canonicallyEquivalentTextsAreDistinct() {
        #expect(JavaStringKey("\u{C5}") != JavaStringKey("A\u{30A}"))
        #expect(JavaStringKey("K") != JavaStringKey("\u{212A}"))
        var map: [JavaStringKey: Int] = [:]
        map[JavaStringKey("\u{C5}")] = 1
        map[JavaStringKey("A\u{30A}")] = 2
        #expect(map.count == 2)
        #expect(map[JavaStringKey("\u{C5}")] == 1)
        #expect(map[JavaStringKey("A\u{30A}")] == 2)
    }

    /// The same text from different storage (native, bridged `NSString`, substring) is one key.
    @Test func sameTextFromDifferentStorageIsEqual() {
        let native = "OK1XOE ěščř 😀"
        let bridged = NSString(string: native) as String
        let sliced = String(("x" + native).dropFirst())
        for other in [bridged, sliced] {
            #expect(JavaStringKey(native) == JavaStringKey(other))
            #expect(JavaStringKey(native).hashValue == JavaStringKey(other).hashValue)
        }
    }

    /// `nil` (Java `null`) is its own key, different from an empty text.
    @Test func nilIsDistinctFromEmpty() {
        #expect(JavaStringKey(nil) == JavaStringKey(nil))
        #expect(JavaStringKey(nil) != JavaStringKey(""))
        var map: [JavaStringKey: Int] = [:]
        map[JavaStringKey(nil)] = 1
        map[JavaStringKey("")] = 2
        #expect(map.count == 2)
    }

    @Test func differentTextsDiffer() {
        #expect(JavaStringKey("ab") != JavaStringKey("abc"))
        #expect(JavaStringKey("ab") != JavaStringKey("ba"))
        #expect(JavaStringKey("") == JavaStringKey(""))
    }
}
