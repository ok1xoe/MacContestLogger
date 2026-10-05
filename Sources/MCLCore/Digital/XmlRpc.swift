import Foundation

/// Minimal XML-RPC (Java `digital/XmlRpc`): building a call with scalar parameters and reading
/// a scalar response. The fldigi HTTP client (`FldigiClient`) lives in its own file.
///
/// Behaviour like Java (probes `research/` and `voice-audio/`):
/// - `call`: `Integer`/`Long` → `<int>`, `Double` → `<double>` with `Double.toString` (`1.0E20`, `-0.0`,
///   `NaN`), `null` → `<string>null</string>`, escaping only `& < >`;
/// - `parseResponse`: any `<fault>` in the document → the first `<string>` in the document as the message, otherwise
///   `XML-RPC fault`; otherwise the **first** `<value>` in the document (by element names including the prefix, regardless of
///   namespaces) and in it the first element: `int`/`i4`/`i8` via `Integer.parseInt` (`i8` above the
///   `int` range is an error), `double` via `Double.parseDouble`, `boolean` = `"1"` (`true` is **false**),
///   `base64` via the MIME decoder (skips unknown characters), another element → its text; without an element =
///   the **untrimmed** value text (`<struct>` gives the joined text). Text = Java `getTextContent`: text
///   and CDATA of descendants, without comments and instructions.
/// - an invalid document → `Neplatná XML-RPC odpověď: <cause>`; the cause text comes from libxml2, not Xerces,
///   and is not compared — except `<!DOCTYPE`, which is rejected with the same text as
///   in Java (`disallow-doctype-decl`), **if the document is otherwise well-formed** (Xerces stops at DOCTYPE
///   before it sees a later error; libxml2 parses the whole document and returns its own text). The
///   `[Fatal Error]` print on stderr is not copied.
/// - **Divergence:** an undeclared namespace prefix (`<x><q:value>u</q:value></x>`) is taken by Java (a parser without
///   namespaces) as a valid document, libxml2 rejects it → `Failure`. fldigi does not send
///   prefixes (a deliberate divergence from Java v1.1.1).
///
/// Parsing: `XMLDocument` validates the document and detects DTDs; the search tree is then built by
/// `XMLParser` over the same bytes, because `XMLDocument` drops text nodes consisting only of whitespace
/// (`<value>\n  \n</value>` must give `"\n  \n"` like Java) — measured, no `XMLNode.Options` option
/// preserves them.
public enum XmlRpc {

    /// Call parameter (Java `Object`: `Integer`/`Long`, `Double`, `Boolean`, anything else via
    /// `String.valueOf`). `Float` (Java `Float.toString`) is not used by the application.
    public enum Param: Sendable, Equatable {
        case int(Int64)
        case double(Double)
        case bool(Bool)
        case string(String?)
    }

    /// Response value (Java `String`, `Integer`, `Double`, `Boolean`, `byte[]`).
    public enum Value: Sendable, Equatable {
        case string(String)
        case int(Int32)
        case double(Double)
        case bool(Bool)
        case bytes([UInt8])
    }

    /// Java `IllegalStateException` from `parseResponse` (`getMessage()` verbatim).
    public struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    static let invalidPrefix = "Neplatná XML-RPC odpověď: "
    static let doctypeMessage = "DOCTYPE is disallowed when the feature "
        + "\"http://apache.org/xml/features/disallow-doctype-decl\" set to true."

    public static func call(_ method: String, _ params: Param...) -> String {
        call(method, params: params)
    }

    public static func call(_ method: String, params: [Param]) -> String {
        var out = "<?xml version=\"1.0\"?><methodCall><methodName>" + escape(method) + "</methodName><params>"
        for param in params {
            out += "<param><value>"
            switch param {
            case .int(let value): out += "<int>" + String(value) + "</int>"
            case .double(let value): out += "<double>" + JavaDouble.toString(value) + "</double>"
            case .bool(let value): out += "<boolean>" + (value ? "1" : "0") + "</boolean>"
            case .string(let value): out += "<string>" + escape(value ?? "null") + "</string>"
            }
            out += "</value></param>"
        }
        return out + "</params></methodCall>"
    }

    /// Value from the response; `nil` for a response without `<value>`. An error (fault, invalid document or number)
    /// → `Failure`.
    public static func parseResponse(_ xml: String) throws(Failure) -> Value? {
        let root = try parse(Data(xml.utf8))
        if root.first(named: "fault") != nil {
            let message = root.first(named: "string")?.textContent ?? "XML-RPC fault"
            throw Failure(message: message)
        }
        guard let value = root.first(named: "value") else {
            return nil
        }
        for case .element(let element) in value.children {
            let text = element.textContent
            switch element.name {
            case "int", "i4", "i8":
                let trimmed = JavaText.trim(text)
                guard let number = JavaInteger.parseInt(trimmed) else {
                    throw Failure(message: invalidPrefix + "For input string: \"" + trimmed + "\"")
                }
                return .int(number)
            case "double":
                do {
                    return .double(try JavaDouble.parse(JavaText.trim(text)))
                } catch {
                    throw Failure(message: invalidPrefix + error.message)
                }
            case "boolean":
                return .bool(JavaText.trim(text) == "1")
            case "base64":
                do {
                    return .bytes(try mimeDecode(JavaText.trim(text)))
                } catch {
                    throw Failure(message: invalidPrefix + error.message)
                }
            default:
                return .string(text)
            }
        }
        return .string(value.textContent) // no type = string
    }

    static func escape(_ text: String) -> String {
        let amp = JavaText.replace(text, "&", "&amp;")
        let lt = JavaText.replace(amp, "<", "&lt;")
        return JavaText.replace(lt, ">", "&gt;")
    }

    // MARK: - Document tree

    final class Element {
        let name: String
        var children: [Node] = []

        init(name: String) {
            self.name = name
        }

        /// Java `getTextContent()` of an element.
        var textContent: String {
            var out = ""
            for child in children {
                switch child {
                case .text(let text): out += text
                case .element(let element): out += element.textContent
                }
            }
            return out
        }

        /// Java `getElementsByTagName(name).item(0)` over the document: the first element in document
        /// order (pre-order), including itself.
        func first(named target: String) -> Element? {
            if name == target { return self }
            for case .element(let element) in children {
                if let found = element.first(named: target) { return found }
            }
            return nil
        }
    }

    enum Node {
        case element(Element)
        case text(String)
    }

    private static func parse(_ data: Data) throws(Failure) -> Element {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw Failure(message: invalidPrefix + error.localizedDescription)
        }
        if document.dtd != nil {
            throw Failure(message: invalidPrefix + doctypeMessage)
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let builder = TreeBuilder()
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw Failure(message: invalidPrefix + (parser.parserError?.localizedDescription ?? "neplatný dokument"))
        }
        return root
    }

    /// Builds the tree from `XMLParser` events (element names qualified as they stand in the document).
    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: Element?
        private var stack: [Element] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let element = Element(name: elementName)
            if let parent = stack.last {
                parent.children.append(.element(element))
            } else if root == nil {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.children.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            stack.last?.children.append(.text(String(decoding: block, as: UTF8.self)))
        }
    }

    // MARK: - Base64 (Java `Base64.getMimeDecoder()`)

    private static let base64Table: [Int8] = {
        var table = [Int8](repeating: -1, count: 256)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        for (index, byte) in alphabet.enumerated() {
            table[Int(byte)] = Int8(index)
        }
        table[Int(UInt8(ascii: "="))] = -2
        return table
    }()

    /// `Base64.getMimeDecoder().decode(String)`: text → ISO-8859-1 bytes (a character above U+00FF = `?`),
    /// characters outside the alphabet are skipped, `=` ends the data. Errors and their texts like `Base64.Decoder.decode0`
    /// (JDK 21).
    static func mimeDecode(_ text: String) throws(JavaIllegalArgumentError) -> [UInt8] {
        let src: [UInt8] = text.unicodeScalars.map { $0.value <= 0xFF ? UInt8($0.value) : 0x3F }
        var out: [UInt8] = []
        var bits: Int32 = 0
        var shiftto: Int32 = 18
        var sp = 0
        while sp < src.count {
            let value = base64Table[Int(src[sp])]
            sp += 1
            if value < 0 {
                if value == -2 {
                    var badEnding = shiftto == 18
                    if shiftto == 6 {
                        if sp == src.count {
                            badEnding = true
                        } else {
                            badEnding = src[sp] != UInt8(ascii: "=")
                            sp += 1
                        }
                    }
                    if badEnding {
                        throw JavaIllegalArgumentError(message: "Input byte array has wrong 4-byte ending unit")
                    }
                    break
                }
                continue
            }
            bits |= Int32(value) << shiftto
            shiftto -= 6
            if shiftto < 0 {
                out.append(UInt8(truncatingIfNeeded: bits >> 16))
                out.append(UInt8(truncatingIfNeeded: bits >> 8))
                out.append(UInt8(truncatingIfNeeded: bits))
                shiftto = 18
                bits = 0
            }
        }
        if shiftto == 6 {
            out.append(UInt8(truncatingIfNeeded: bits >> 16))
        } else if shiftto == 0 {
            out.append(UInt8(truncatingIfNeeded: bits >> 16))
            out.append(UInt8(truncatingIfNeeded: bits >> 8))
        } else if shiftto == 12 {
            throw JavaIllegalArgumentError(message: "Last unit does not have enough valid bits")
        }
        while sp < src.count {
            let value = base64Table[Int(src[sp])]
            sp += 1
            if value < 0 {
                continue
            }
            throw JavaIllegalArgumentError(message: "Input byte array has incorrect ending byte at " + String(sp))
        }
        return out
    }
}
