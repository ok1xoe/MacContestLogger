/// Incremental reading of received text from fldigi (Java `digital/RxTextStream`). fldigi keeps the RX text
/// in a growing buffer and a slice is taken from it over XML-RPC (`text.get_rx(start, length)`), so it is enough to
/// remember where we have read up to.
///
/// Like Java: the offset advances by the block length in **UTF-16 units before cleaning**;
/// cleaning drops characters `< U+0020` except `\n` (U+007F and U+0085 stay); trimming to `maxChars` units
/// from the front **may split a surrogate pair**, so the text is kept as `[UInt16]` (`textUnits` exactly like
/// Java, `text` is a Swift `String` in which a lone half becomes U+FFFD). `pending(len < offset)`
/// resets the offset (fldigi buffer cleared); the offset arithmetic overflows like Java `int`.
public final class RxTextStream {

    /// Slice of the fldigi RX buffer that has not been read yet.
    public struct Span: Equatable, Sendable {
        public let start: Int32
        public let length: Int32

        public init(start: Int32, length: Int32) {
            self.start = start
            self.length = length
        }
    }

    private let maxChars: Int32
    public private(set) var textUnits: [UInt16] = []
    /// The ranges of the text (UTF-16 offsets into `textUnits`) that arrived while the own station transmitted
    /// (fldigi's echo): their calls are not grabbed (N1MM). A Swift-only addition.
    public private(set) var transmitted: [Range<Int>] = []
    /// UTF-16 units dropped from the front so far (the trim and `clear`): `dropped + offset` is a position in all text
    /// ever received, so new text can be told from text already seen. A Swift-only addition.
    public private(set) var dropped: Int = 0
    private var nextOffset: Int32 = 0

    public init(maxChars: Int32) {
        self.maxChars = maxChars
    }

    /// What remains to be fetched if the fldigi RX buffer is `rxLength` characters long; `nil` if nothing
    /// has arrived since last time.
    public func pending(_ rxLength: Int32) -> Span? {
        if rxLength < nextOffset {
            nextOffset = 0 // the buffer in fldigi got shorter → read again from the start
        }
        if rxLength <= nextOffset {
            return nil
        }
        return Span(start: nextOffset, length: rxLength &- nextOffset)
    }

    /// Adds a fetched block. The offset advances by its actual length, so a shorter fldigi response is
    /// completed next time. Control characters are not let into the window.
    public func append(_ chunk: String?, transmitting: Bool = false) {
        guard let chunk, !chunk.isEmpty else { return }
        let units = Array(chunk.utf16)
        nextOffset &+= Int32(truncatingIfNeeded: units.count)
        let before: Int = textUnits.count
        textUnits.append(contentsOf: units.filter { $0 == 0x0A || $0 >= 0x20 })
        if transmitting && textUnits.count > before {
            if let last = transmitted.last, last.upperBound == before {
                transmitted[transmitted.count - 1] = last.lowerBound..<textUnits.count
            } else {
                transmitted.append(before..<textUnits.count)
            }
        }
        if textUnits.count > Int(maxChars) {
            let cut: Int = Swift.min(textUnits.count, textUnits.count - Int(maxChars))
            transmitted = transmitted.compactMap { range in
                let lower: Int = Swift.max(range.lowerBound - cut, 0)
                let upper: Int = range.upperBound - cut
                return upper > lower ? lower..<upper : nil
            }
            // Java `delete(0, length − max)`: the end beyond the length is clipped, a negative `max` deletes everything. The difference is
            // computed in `Int`, Java in `int`: for `maxChars` near `Int32.min` Java overflows and `delete` throws,
            // here everything is deleted (unreachable from the UI — a positive constant).
            dropped += cut
            textUnits.removeFirst(Swift.min(textUnits.count, textUnits.count - Int(maxChars)))
        }
    }

    /// Text for the window.
    public var text: String {
        JavaChar.string(textUnits)
    }

    /// Clears the window; the position in fldigi does not change, so the text does not start being read again.
    public func clear() {
        dropped += textUnits.count
        textUnits.removeAll()
        transmitted.removeAll()
    }

    /// `true` when the offset lies in text received while transmitting.
    public func isTransmitted(_ offset: Int) -> Bool {
        transmitted.contains { $0.contains(offset) }
    }
}
