import AppKit

/// Opens a URL in the system browser.
///
/// Port of `util/BrowserOpener.java`. The Java version first tries `java.awt.Desktop`
/// and on failure falls back to running the `open` command; on macOS both do the same thing,
/// so in Swift a single path via `NSWorkspace` remains. Opening a web page is not
/// critical — if it fails (empty or invalid URL), nothing simply happens.
public enum BrowserOpener {
    public static func open(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let target = URL(string: trimmed) else { return }
        NSWorkspace.shared.open(target)
    }
}
