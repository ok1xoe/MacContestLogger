/// Estimates received exchange field values from the callsign (cty.dat) for the spot colour in the bandmap. Port
/// of Java `engine/SpotExchangeEstimator.java`. A spot from the cluster carries no exchange — without an estimate
/// zone multipliers would not be evaluated. The estimate is a heuristic for the colour only; a real QSO has the real exchange.
///
/// A field with a non-empty `estimate` is filled by kind (`trim`, case-sensitive):
/// `iaruExch` (HQ abbreviation from `hqCalls`, otherwise the first ITU zone), `ituZone`, `cqZone` (first zone),
/// `continent` (`primaryContinent`), `grid` (from `gridByCall`); another kind nothing.
///
/// Java properties that are copied (table `GrabMeasured.estimate`, maintainer-only probe):
/// - `received`, `call` or `dxcc` `nil` → an empty map (even if the `grid` could be looked up);
/// - the HQ and grid maps are searched by the `trim` + `toUpperCase` callsign, `dxcc.resolve` gets the **original**;
/// - an empty HQ abbreviation (`isBlank`) is not inserted and does **not** fall back to the zone (a `null` value does);
/// - a first zone `null` → the text `"null"` (Java `String.valueOf(Object)`) is inserted;
/// - the result in field order, a duplicate id → the later value at the position of the first, a `nil` id is a `nil` key.
///
/// Leniency versus Java (a deliberate divergence from Java v1.1.1): a `nil` element of `received` (Java NPE)
/// is skipped.
public enum SpotExchangeEstimator {

    /// - Parameters:
    ///   - hqCalls: HQ callsign (upper case) → society abbreviation; the default is Java `Map.of()`.
    ///   - gridByCall: looked-up locators (callsign → locator, e.g. from HamQTH) for the kind `grid`.
    public static func estimate(_ received: [ContestDefinition.ExchangeField?]?, _ call: String?,
                                _ dxcc: (any DxccLookup)?,
                                hqCalls: JavaLinkedMap<String>? = JavaLinkedMap(),
                                gridByCall: JavaLinkedMap<String>? = JavaLinkedMap()) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        guard let received, let call, let dxcc else {
            return out
        }
        let upper = JavaText.trim(call).uppercased()
        let hq = hqCalls?[upper]
        let grid = gridByCall?[upper]
        let entity = dxcc.resolve(call)
        for field in received {
            guard let field else { continue }   // Java NPE — a recorded leniency
            guard let kind = field.estimate, !JavaText.isBlank(kind) else {
                continue
            }
            let value = estimateValue(JavaText.trim(kind), entity, hq: hq, grid: grid)
            if let value, !JavaText.isBlank(value) {
                out.put(field.id, value)
            }
        }
        return out
    }

    /// Java `switch (kind.trim())` — comparison by UTF-16 units.
    private static func estimateValue(_ kind: String, _ entity: DxccEntity?, hq: String?, grid: String?) -> String? {
        if JavaText.equals("iaruExch", kind) {
            // IARU exch: HQ callsign → abbreviation, otherwise ITU zone
            return hq ?? entity.flatMap { firstZone($0.itu) }
        }
        if JavaText.equals("ituZone", kind) {
            return entity.flatMap { firstZone($0.itu) }
        }
        if JavaText.equals("cqZone", kind) {
            return entity.flatMap { firstZone($0.cq) }
        }
        if JavaText.equals("continent", kind) {
            return entity?.primaryContinent
        }
        if JavaText.equals("grid", kind) {
            return grid   // the looked-up locator (HamQTH) — otherwise nil
        }
        return nil
    }

    /// Java `String.valueOf(zones.getFirst())`: a `null` element is the text `"null"`.
    private static func firstZone(_ zones: [Int?]?) -> String? {
        guard let zones, let first = zones.first else {
            return nil
        }
        return first.map { String($0) } ?? "null"
    }
}
