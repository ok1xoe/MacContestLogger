/// Dictionary key with Java `String` equality: by UTF-16 units, not canonically like Swift's
/// `String` (`Å` U+00C5 ≠ `A` + U+030A, `K` ≠ KELVIN SIGN). `nil` is Java `null`.
///
/// The key used to be built as `Array(text.utf16)` — the array was allocated on **every** lookup
/// (`JavaRegexCache`, `JavaLinkedMap`). Here only the text is held and both hash and equality are computed
/// over its UTF-8 bytes: Swift's `String` is always valid Unicode (no lone surrogate
/// units), so UTF-8 and UTF-16 are bijections of the same sequence of scalars and byte equality of
/// UTF-8 is exactly equality of UTF-16 units.
struct JavaStringKey: Hashable, Sendable {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    static func == (lhs: JavaStringKey, rhs: JavaStringKey) -> Bool {
        switch (lhs.text, rhs.text) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.utf8.count == right.utf8.count && left.utf8.elementsEqual(right.utf8)
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        guard let text else {
            hasher.combine(UInt8(0))
            return
        }
        hasher.combine(UInt8(1))
        // A native string has contiguous storage — bytes are hashed at once without allocation; a bridged
        // string without it (rare) is copied first so that both paths give the same hash.
        let done: Void? = text.utf8.withContiguousStorageIfAvailable { bytes in
            hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
        }
        if done == nil {
            Array(text.utf8).withUnsafeBytes { hasher.combine(bytes: $0) }
        }
        hasher.combine(text.utf8.count)
    }
}
