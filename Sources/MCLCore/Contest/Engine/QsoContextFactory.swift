import os

/// QSO context build error: an expression in `stationClasses[].when.expr` (`StationClassifier`),
/// or a number above 2³¹−1 in a numeric received field (`ExchangeEngine.parse`). Java does not catch
/// either exception — they propagate to the caller.
public enum QsoContextError: Error, Equatable, Sendable {
    case expression(ExpressionError)
    case exchange(ExchangeError)
}

/// Builds a `QsoContext`: resolves the callsign to DXCC, determines the other station's class, parses the active
/// received fields (per `appliesWhen`). The own station (`ownEntity`) is resolved once from the operator's
/// callsign. Port of Java `engine/QsoContextFactory.java`.
///
/// **A class, not a struct:** reference semantics like the Java instance, on which `ContestSession`
/// sets the bonus-station predicate after construction (`setBonusPredicate`). The only holder
/// in Java is `ContestSession` (a private field), so a struct with a `mutating` setter inside
/// it would behave the same; a class was chosen for fidelity and because it holds `any DxccLookup`.
///
/// **`Sendable`:** Java builds the session (and with it the factory) in the background and takes it over on the main
/// thread, where both `build` and `setBonusPredicate` are called afterwards. The other state is immutable and `Sendable`
/// (`DxccLookup` is `Sendable`), the only mutable piece — the bonus predicate — is behind
/// `OSAllocatedUnfairLock`. A "non-`Sendable`, take over via `sending`" variant would not be enough:
/// `Task.detached` returns only `Sendable` values and the factory is also shared with the UI preview.
/// The lock costs one uncontended lock per `build`.
///
/// Java semantics (scenarios `ExchangeMeasured.factory`, maintainer-only probe):
/// - `ownItuZone` is never `nil`: `myItuZone` after Java `trim()`; if empty → the first ITU zone
///   of the own entity (a `nil` first element → the text `"null"`), otherwise `""`;
/// - `myGrid` is passed without normalization; `ownQth` empty/blank (Java `isBlank`) → `nil`,
///   otherwise `trim()` + upper case;
/// - a `nil` callsign goes to `dxcc.resolve(nil)` (resolvers return "nothing") and the bonus predicate is
///   not called for it; `myCall == nil` is not resolved at all;
/// - `receivedRaw == nil` → all fields `""`; a key present with a `nil` value → a `nil` input
///   (Java `getOrDefault`); keys by UTF-16.
public final class QsoContextFactory: Sendable {

    private let definition: ContestDefinition
    private let dxcc: any DxccLookup
    private let exchange: ExchangeEngine
    private let ownEntity: DxccEntity?
    private let myGrid: String?
    private let ownItuZone: String
    /// The predicate wrapped in a struct. **Not** a bare function as the lock state: a generic
    /// `OSAllocatedUnfairLock<function>` re-abstracts it on every `withLock` (an `inout` parameter)
    /// and writes it back two thunks deeper, so after ~10,000 `build` calls
    /// the predicate call overflows the stack (measured, test `bonusPredicateDoesNotGrowWithEveryBuild`).
    private struct BonusPredicate: Sendable {
        let test: @Sendable (String) -> Bool
    }

    /// Is the callsign a bonus station? (N1MM BONUS, set by `ContestSession`) Behind the lock —
    /// see the type description.
    private let bonus = OSAllocatedUnfairLock(initialState: BonusPredicate { _ in false })

    public init(definition: ContestDefinition, dxcc: any DxccLookup, exchange: ExchangeEngine,
                myCall: String?, myGrid: String? = nil, myItuZone: String? = nil) {
        self.definition = definition
        self.dxcc = dxcc
        self.exchange = exchange
        let ownEntity = myCall.flatMap { dxcc.resolve($0) }
        self.ownEntity = ownEntity
        self.myGrid = myGrid
        // My ITU zone: from the configuration, fallback from the DXCC entity (first zone).
        var zone = myItuZone.map(JavaText.trim) ?? ""
        if zone.isEmpty, let itu = ownEntity?.itu, let first = itu.first {
            zone = first.map { String($0) } ?? "null"   // Java String.valueOf(null)
        }
        self.ownItuZone = zone
    }

    /// Class of the other station for the given callsign (drives the dynamic exchange fields in the UI).
    public func workedClass(_ call: String?) throws(ExpressionError) -> String? {
        try StationClassifier.classify(definition, worked: dxcc.resolve(call), own: ownEntity)
    }

    /// `nil` → always false (Java `call -> false`).
    public func setBonusPredicate(_ bonus: (@Sendable (String) -> Bool)?) {
        let predicate = BonusPredicate(test: bonus ?? { _ in false })
        self.bonus.withLock { $0 = predicate }
    }

    /// - Parameter ownQth: my county (rover / county line), otherwise `nil`
    public func build(call: String?, band: String?, mode: String?, receivedRaw: JavaLinkedMap<String>?,
                      ownQth: String? = nil) throws(QsoContextError) -> QsoContext {
        let worked = dxcc.resolve(call)
        let workedClass: String?
        do {
            workedClass = try StationClassifier.classify(definition, worked: worked, own: ownEntity)
        } catch {
            throw .expression(error)
        }
        var received = JavaLinkedMap<ExchangeValue>()
        for field in exchange.activeReceivedFields(definition, workedClass) {
            let raw: String?
            if let receivedRaw {
                raw = receivedRaw.containsKey(field.id) ? receivedRaw[field.id] : ""
            } else {
                raw = ""
            }
            do {
                received.put(field.id, try exchange.parse(field, raw))
            } catch {
                throw .exchange(error)
            }
        }
        let isBonus = bonus.withLock { $0 }.test
        let qth: String? = ownQth.flatMap { JavaText.isBlank($0) ? nil : JavaText.trim($0).uppercased() }
        return QsoContext(call: call, band: band, mode: mode, received: received, workedEntity: worked,
                          ownEntity: ownEntity, workedClass: workedClass, ownGrid: myGrid, ownItuZone: ownItuZone,
                          ownQth: qth, bonusStation: call.map { isBonus($0) } ?? false)
    }
}
