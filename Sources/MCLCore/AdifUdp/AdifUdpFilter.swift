import Foundation

/// Pure logic of Java `adifudp/AdifUdpListener` without the socket (that lives elsewhere): the datagram is decoded
/// as `new String(bytes, UTF_8)` (bad sequences → U+FFFD, `JavaUtf8`) and passed to the handler only
/// when, after Java `toLowerCase()`, it contains both `<call` and `<eor>` (search by UTF-16 units,
/// not Swift `contains` over graphemes — Java finds `<eor>` with an attached combining character).
public enum AdifUdpFilter {

    private static let callTag: [UInt16] = Array("<call".utf16)
    private static let eorTag: [UInt16] = Array("<eor>".utf16)

    /// Datagram text if it looks like an ADIF record; otherwise `nil` (Java silently discards it).
    public static func adif(from datagram: [UInt8]) -> String? {
        let text: String = JavaUtf8.decode(datagram)
        let lower: [UInt16] = Array(JavaText.toLowerCase(text).utf16)
        guard JavaText.indexOf(lower, callTag) >= 0, JavaText.indexOf(lower, eorTag) >= 0 else {
            return nil
        }
        return text
    }
}
