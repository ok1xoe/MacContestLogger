import Foundation

/// Locates the core's SwiftPM resource bundle (`MacContestLogger_MCLCore.bundle`: built-in menu, shipped languages)
/// so that it also works from an assembled `MacContestLogger.app` on another machine.
///
/// Why not plain `Bundle.module` (measured 2026-10-02, generated `resource_bundle_accessor.swift`):
/// - the native build system (Swift 6.1 on CI, the one that builds the release) looks only at
///   `Bundle.main.bundleURL/<name>.bundle` — for an app that is `MacContestLogger.app/<name>.bundle`, **not**
///   `Contents/Resources` — and then at the **absolute path of the build directory**; an app with the bundle in
///   `Contents/Resources` would therefore silently read from `.build/` and work only on the machine that built it;
/// - the Swift Build system (local Swift 6.4) looks at `Bundle.main.resourceURL`, the framework's resources and
///   `Bundle.main.bundleURL`, without an absolute path;
/// - both end in `fatalError` when nothing is found.
///
/// Order here: `Bundle.main.resourceURL` → `Bundle.main.bundleURL` → `Bundle.module` **only** when the process does
/// not run from an `.app` (tests, `swift run`, command-line tools) — inside an app a missing bundle yields `nil`, which
/// the start-up check reports, instead of a crash or a read from the build directory.
public enum CoreResources {

    /// Directory name of the core's resource bundle (SwiftPM `<package>_<target>.bundle`).
    public static let bundleName = "MacContestLogger_MCLCore.bundle"

    /// The resource bundle of the running process, or `nil` inside an app that lacks it.
    public static let bundle: Bundle? = {
        let mainURL: URL = Bundle.main.bundleURL
        if let url = locate(mainBundleURL: mainURL, mainResourceURL: Bundle.main.resourceURL),
           let found = Bundle(url: url) {
            return found
        }
        if isApp(mainURL) {
            return nil
        }
        return Bundle.module
    }()

    /// Whether the main bundle is an application bundle (`*.app`).
    public static func isApp(_ mainBundleURL: URL) -> Bool {
        mainBundleURL.pathExtension.lowercased() == "app"
    }

    /// Candidate locations in lookup order (without `Bundle.module`).
    public static func candidates(mainBundleURL: URL, mainResourceURL: URL?) -> [URL] {
        var result: [URL] = []
        if let resources = mainResourceURL {
            result.append(resources.appendingPathComponent(bundleName, isDirectory: true))
        }
        let beside: URL = mainBundleURL.appendingPathComponent(bundleName, isDirectory: true)
        if !result.contains(beside) {
            result.append(beside)
        }
        return result
    }

    /// The first candidate that exists as a directory.
    public static func locate(mainBundleURL: URL, mainResourceURL: URL?) -> URL? {
        for candidate in candidates(mainBundleURL: mainBundleURL, mainResourceURL: mainResourceURL) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }
}
