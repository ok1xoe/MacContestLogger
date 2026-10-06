import Foundation

/// Fills in the QSO's country data (DXCC entity number, name, continent) from the callsign.
///
/// The columns in the log and the writing to ADIF, CSV and the wire protocol existed
/// earlier, nobody just populated them -- so a QSO left without `DXCC`, `COUNTRY`
/// and `CONT`. It is filled in at write time, not only at export, because the country file
/// changes over time: what was valid on the day of the QSO should stay with the QSO.
///
/// Only what is missing is filled in. An imported QSO carries its own data and it is
/// not overwritten -- a foreign log may have the country determined more precisely (e.g. by hand for a callsign
/// that the prefix does not determine unambiguously).
///
/// Port of the Java `dxcc/DxccFiller.java` (final utility class, static methods only).
///
/// The lookup is made as of the QSO time (`resolve(_:at:)` with `timestampUtc`): only Club Log's `cty.xml` has
/// date-ranged records, the other sources ignore the date, so their results are unchanged.
///
/// **Differences forced by the `Qso` port:**
/// - The Java `Qso` is a class and `fill` mutates it in place; the Swift `Qso` is a `struct`,
///   so the parameters are `inout`. The caller pattern from `AppState` (fill the log ->
///   save only the changed ones) is thus preserved.
/// - The Java `null` in `qso`/`qsos` cannot be expressed in Swift (`inout` has no `nil`);
///   the Java test `nullArgumentsAreSafe` is therefore covered only in its half
///   about `dxcc == null`, where `nil` really can be passed for `DxccLookup?`.
/// - The Java `Qso.dxccName`/`continent` are `String` with a possible `null`; the Swift
///   port has a non-optional `String` with an empty value. "Missing" is the same
///   in both cases (`isBlank`), so `fill` behaves identically. For `refill` they
///   diverge in a single corner: for a QSO with an **empty** (not `null`) name
///   and an entity **without** a name, Java would report a change, we would not -- but both variants leave
///   the field equally empty, only the returned flag differs.
public enum DxccFiller {

    /// Fills in the missing country data for one QSO.
    ///
    /// When nothing is missing, it returns `false` **without querying the resolver** (short-circuit
    /// like in Java -- on a big log this saves thousands of lookups).
    ///
    /// The DXCC number is written only when the entity knows it (`adifDxcc != nil`):
    /// the internal identity of the entity does not belong outside, from `cty.dat` it is the record order.
    ///
    /// - Returns: `true` when something changed (the caller may save it).
    @discardableResult
    public static func fill(_ qso: inout Qso, _ dxcc: (any DxccLookup)?) -> Bool {
        guard let dxcc else {
            return false
        }
        let needsEntity = qso.dxccEntity == nil
        let needsName = JavaText.isBlank(qso.dxccName)
        let needsContinent = JavaText.isBlank(qso.continent)
        if !needsEntity && !needsName && !needsContinent {
            return false
        }
        if JavaText.isBlank(qso.call) {
            return false
        }
        guard let e = dxcc.resolve(qso.call, at: qso.timestampUtc) else {
            return false
        }
        var changed = false
        if needsEntity, let adif = e.adifDxcc {
            qso.dxccEntity = adif
            changed = true
        }
        if needsName, let name = e.name, !JavaText.isBlank(name) {
            qso.dxccName = name
            changed = true
        }
        if needsContinent, let continent = e.primaryContinent, !JavaText.isBlank(continent) {
            qso.continent = continent
            changed = true
        }
        return changed
    }

    /// Fills in the country data for the whole log (QSOs written before the filling
    /// was added). Returns only the QSOs where something changed -- the caller saves those,
    /// not the whole log.
    @discardableResult
    public static func fillAll(_ qsos: inout [Qso], _ dxcc: (any DxccLookup)?) -> [Qso] {
        guard let dxcc else {
            return []
        }
        var changed: [Qso] = []
        for index in qsos.indices where fill(&qsos[index], dxcc) {
            changed.append(qsos[index])
        }
        return changed
    }

    /// Recomputes the country for one QSO from today's data -- unlike `fill` it
    /// **overwrites** even what is already filled in. A manual user action over the whole
    /// log: used when the stored values turn out to be wrong (the record order
    /// in `cty.dat` used to get into the ADIF field instead of the DXCC number).
    ///
    /// A QSO whose callsign the resolver does not know stays untouched -- its country
    /// may have been entered by hand and must not be guessed.
    ///
    /// It can also **clear**: when the new resolver does not know the ADIF number, the earlier
    /// (wrong) number is deleted -- better nothing than a number that is not DXCC.
    ///
    /// - Returns: `true` when something really changed.
    @discardableResult
    public static func refill(_ qso: inout Qso, _ dxcc: (any DxccLookup)?) -> Bool {
        guard let dxcc, !JavaText.isBlank(qso.call) else {
            return false
        }
        guard let e = dxcc.resolve(qso.call, at: qso.timestampUtc) else {
            return false
        }
        let name = e.name ?? ""
        let continent = e.primaryContinent ?? ""
        let changed = qso.dxccEntity != e.adifDxcc
            || !javaEquals(qso.dxccName, name)
            || !javaEquals(qso.continent, continent)
        if changed {
            qso.dxccEntity = e.adifDxcc
            qso.dxccName = name
            qso.continent = continent
        }
        return changed
    }

    /// Java `Objects.equals` over `String`: **exact** equality of UTF-16 units.
    /// Swift `==` is canonical equivalence, so it would treat "Juan Fernández" in NFD
    /// and in NFC as the same string and would not report a change, whereas Java
    /// would -- and `refill` is precisely about whether to write to the log.
    private static func javaEquals(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }

    /// Recomputes the country for the whole log; returns only the QSOs that changed.
    @discardableResult
    public static func refillAll(_ qsos: inout [Qso], _ dxcc: (any DxccLookup)?) -> [Qso] {
        guard let dxcc else {
            return []
        }
        var changed: [Qso] = []
        for index in qsos.indices where refill(&qsos[index], dxcc) {
            changed.append(qsos[index])
        }
        return changed
    }
}
