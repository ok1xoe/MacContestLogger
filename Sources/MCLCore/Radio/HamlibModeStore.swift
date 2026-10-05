import os

/// The live mode mapping of both rigs (shared by the app layer): Java keeps `HamlibModes` in one global
/// `static volatile` state that every rig reads on each conversion. Swift holds one store under a lock; both
/// `CatSession`s get its `provider`, so `configure` (Kotlin `applyModeSettings` at start, profile and Settings) changes
/// the mapping of a running connection at once.
public final class HamlibModeStore: Sendable {

    private let state: OSAllocatedUnfairLock<HamlibModeMapping>

    public init(_ initial: HamlibModeMapping = .default) {
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    /// The current mapping.
    public var mapping: HamlibModeMapping {
        state.withLock { $0 }
    }

    /// The provider to hand to every rig client — it reads the store on every call.
    public var provider: HamlibModeProvider {
        { [self] in self.mapping }
    }

    /// `HamlibModes.configure(Mode.fromAdif(config.dataMode), config.isRttyAfsk)`.
    public func configure(dataMode: Mode?, rttyAfsk: Bool) {
        let next = HamlibModeMapping(dataMode: dataMode, rttyAfsk: rttyAfsk)
        state.withLock { $0 = next }
    }
}
