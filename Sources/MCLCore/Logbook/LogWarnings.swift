/// Warnings about possible errors in the logbook (N1MM Log window → „Warning of Possible Errors").
/// Port of Java `logbook/LogWarnings`:
/// - **exchange differs** for the same station (zone, county…; the report and serial numbers naturally
///   change, those are not checked). The band is — as in Java — not compared, all QSOs
///   of the callsign are taken;
/// - **callsign is not in master.scp** (a possible typo);
/// - **zone does not fit the country** — the received CQ/ITU zone is not among the zones of the DXCC entity.
///
/// A pure function over the whole logbook; X-QSOs and deleted QSOs are not checked. The texts are fixed
/// in Czech as in Java (not via translation).
///
/// **Order**: the output keys go in the order of the first warning
/// (Java `LinkedHashMap`); the „differs" messages arise only after iterating the Java
/// `HashMap`s callsign → field ids → values, so the order of messages within a QSO (tooltip in the UI)
/// and the order of keys depend on Java hashing. It is emulated by `JavaHashMapOrder` (all three
/// levels are filled via `computeIfAbsent`).
public enum LogWarnings {

    /// Warnings by QSO id (only QSOs with some warning), in Java order.
    public struct Warnings: Equatable, Sendable {
        /// QSO id in the order of the first warning.
        public private(set) var ids: [Int64] = []
        private var messages: [Int64: [String]] = [:]

        public init() {}

        /// QSO messages in order of creation, `nil` = a QSO without warnings.
        public subscript(_ id: Int64) -> [String]? { messages[id] }

        public func containsKey(_ id: Int64) -> Bool { messages[id] != nil }
        public var isEmpty: Bool { ids.isEmpty }
        public var count: Int { ids.count }

        /// Java `add`: the same text (by UTF-16) is not added to a QSO a second time.
        mutating func add(_ id: Int64, _ message: String) {
            if var list = messages[id] {
                if list.contains(where: { JavaText.equals($0, message) }) { return }
                list.append(message)
                messages[id] = list
            } else {
                ids.append(id)
                messages[id] = [message]
            }
        }
    }

    /// - Parameters:
    ///   - receivedFields: received contest fields for the callsign (order as the stored exchange),
    ///     `nil` = none; in Swift typically `ContestSession.activeReceivedFields`, whose error
    ///     propagates out (Java lets it through too). Called twice per QSO as in Java.
    ///   - inScp: is the callsign in master.scp? `nil` = SCP is not loaded, do not check
    ///   - cqZones: CQ zones of the callsign's country (empty or `nil` = unknown)
    ///   - ituZones: ITU zones of the callsign's country (empty or `nil` = unknown)
    public static func analyze(
        _ qsos: [Qso],
        receivedFields: (String) throws -> [ContestDefinition.ExchangeField]?,
        inScp: ((String) -> Bool)?,
        cqZones: (String) -> Set<Int?>?,
        ituZones: (String) -> Set<Int?>?
    ) rethrows -> Warnings {
        var out = Warnings()
        let active = qsos.filter { !$0.deleted && !$0.xqso && $0.id != nil && !JavaText.isBlank($0.call) }

        // Values of stable exchange fields after the callsign: field → (value → QSO), Java HashMaps.
        var byCall = HashLevel<HashLevel<HashLevel<[Int64]>>>()
        for q in active {
            let id = q.id!
            let call = JavaText.trim(q.call).uppercased()
            let values = parse(q, try receivedFields(call))
            let fields = try receivedFields(call) ?? []
            for f in fields {
                guard let v = values[f.id], !isVariable(f.type) else { continue }
                byCall.update(call) { fieldMap in
                    fieldMap.update(f.id) { valueMap in
                        valueMap.update(v) { $0.append(id) }
                    }
                }
                if f.type == .CQ_ZONE {
                    zoneCheck(&out, id, v, cqZones(call), "CQ")
                } else if f.type == .ITU_ZONE {
                    zoneCheck(&out, id, v, ituZones(call), "ITU")
                }
            }
            if let inScp, !inScp(call) {
                out.add(id, "volačka není v master.scp")
            }
        }
        for call in byCall.order.keys {
            let fieldMap = byCall.values[call]!
            for field in fieldMap.order.keys {
                let valueMap = fieldMap.values[field]!
                guard valueMap.order.count > 1 else { continue }
                let sorted = valueMap.order.keys.compactMap { $0 }
                    .sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
                let message = "výměna " + (field ?? "null") + " se liší na jiných QSO: "
                    + sorted.joined(separator: " / ")
                for value in valueMap.order.keys {
                    for id in valueMap.values[value]! {
                        out.add(id, message)
                    }
                }
            }
        }
        return out
    }

    /// One level of a Java `HashMap<String, V>` filled via `computeIfAbsent`: iteration
    /// order from `JavaHashMapOrder`, values by UTF-16 keys in `JavaLinkedMap`.
    fileprivate struct HashLevel<Value: EmptyInit> {
        var order = JavaHashMapOrder()
        var values = JavaLinkedMap<Value>()

        mutating func update(_ key: String?, _ body: (inout Value) -> Void) {
            order.computeIfAbsent(key)
            var value = values[key] ?? Value()
            body(&value)
            values.put(key, value)
        }
    }

    /// The report and serial numbers change between QSOs, the rest of the exchange should be stable.
    private static func isVariable(_ type: ContestDefinition.FieldType?) -> Bool {
        type == .RST || type == .RS || type == .SERIAL || type == .QTC
    }

    private static func zoneCheck(_ out: inout Warnings, _ id: Int64, _ value: String,
                                  _ expected: Set<Int?>?, _ kind: String) {
        guard let expected, !expected.isEmpty else { return }
        // a non-numeric zone is handled by exchange validation (Java silently catches NumberFormatException)
        guard let zone = JavaInteger.parseInt(JavaText.trim(value)) else { return }
        if expected.contains(Int(zone)) { return }
        // Java sorts naturally: a single `null` element is printed as "null", with another element
        // it fails with an NPE — here leniently `null` first (a deliberate divergence from Java v1.1.1).
        let sorted = expected.sorted { a, b in
            switch (a, b) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x < y
            }
        }
        let list = sorted.map { $0.map(String.init) ?? "null" }.joined(separator: "/")
        out.add(id, kind + " zóna " + String(zone) + " nesedí k zemi (" + list + ")")
    }

    /// The received exchange split by Java `trim().toUpperCase().split("\\s+")` and assigned to
    /// fields by order (Java `HashMap.put`: a later field with the same id wins).
    private static func parse(_ q: Qso, _ fields: [ContestDefinition.ExchangeField]?) -> JavaLinkedMap<String> {
        var values = JavaLinkedMap<String>()
        guard let fields, !JavaText.isBlank(q.exchangeRcvd) else { return values }
        let tokens = splitOnRegexSpace(JavaText.trim(q.exchangeRcvd).uppercased())
        for (field, token) in zip(fields, tokens) {
            values.put(field.id, token)
        }
        return values
    }

    /// `split("\\s+")` over text after `trim()`: there is no `\s` at the edges, so it is enough to split
    /// on runs of `[ \t\n\x0B\f\r]`; empty text gives `[""]` as in Java.
    private static func splitOnRegexSpace(_ text: String) -> [String] {
        var out: [String] = []
        var current: [UInt16] = []
        var inSpace = false
        for unit in text.utf16 {
            if JavaChar.isRegexSpace(unit) {
                if !inSpace {
                    out.append(String(decoding: current, as: UTF16.self))
                    current = []
                }
                inSpace = true
            } else {
                current.append(unit)
                inSpace = false
            }
        }
        out.append(String(decoding: current, as: UTF16.self))
        return out
    }
}

/// A value that can arise empty (`computeIfAbsent(k, x -> new …())`).
fileprivate protocol EmptyInit {
    init()
}

extension Array: EmptyInit {}
extension LogWarnings.HashLevel: EmptyInit {}
