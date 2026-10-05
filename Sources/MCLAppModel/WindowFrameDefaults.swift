import Foundation

/// SwiftUI/AppKit keep a frame record per window in the user defaults (`NSWindow Frame <autosave name>`) and place a
/// window by it when it reopens; `NSOpenPanel`/`NSSavePanel` keep their expanded size (`NSNavPanelExpandedSizeFor…`).
/// The JVM version has no such record — with nothing saved in `config.windowGeometry` a window opens at the platform
/// default placement — and the config file is the only geometry store. The app removes these records
/// before SwiftUI starts, whenever a window's autosave name reappears (`removeRecord(autosaveName:in:)`), and on quit.
public enum WindowFrameDefaults {

    /// Prefix of AppKit's frame records.
    public static let keyPrefix = "NSWindow Frame "
    /// Prefix of the open/save panels' size records (`NSNavPanelExpandedSizeForOpenMode`, `…ForSaveMode`).
    public static let navPanelPrefix = "NSNavPanelExpandedSizeFor"

    /// Removes every frame and panel-size record of `store`'s own domains; returns the removed keys (sorted). A key
    /// that stays visible afterwards (it lives in the global domain, which is not the app's to change) is not
    /// reported.
    @discardableResult
    public static func removeFrameRecords(in store: some FrameRecordStore) -> [String] {
        let keys: [String] = store.recordKeys().filter(isRecord).sorted()
        for key in keys {
            store.removeRecord(forKey: key)
        }
        return keys.filter { !store.hasRecord(forKey: $0) }
    }

    /// The record AppKit writes for a window whose autosave name SwiftUI assigned again: removed (nothing for an
    /// empty name). `true` = a record was there.
    @discardableResult
    public static func removeRecord(autosaveName: String, in store: some FrameRecordStore) -> Bool {
        guard !autosaveName.isEmpty else { return false }
        let key: String = keyPrefix + autosaveName
        guard store.hasRecord(forKey: key) else { return false }
        store.removeRecord(forKey: key)
        return true
    }

    static func isRecord(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix) || key.hasPrefix(navPanelPrefix)
    }
}

/// The key-value store the frame records live in: `UserDefaults` in the app; tests use an in-memory store, so no test
/// ever creates a defaults domain (a plist in `~/Library/Preferences`).
public protocol FrameRecordStore {
    func recordKeys() -> [String]
    func hasRecord(forKey key: String) -> Bool
    func removeRecord(forKey key: String)
}

extension UserDefaults: FrameRecordStore {
    public func recordKeys() -> [String] {
        Array(dictionaryRepresentation().keys)
    }

    public func hasRecord(forKey key: String) -> Bool {
        object(forKey: key) != nil
    }

    public func removeRecord(forKey key: String) {
        removeObject(forKey: key)
    }
}
