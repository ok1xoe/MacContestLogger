import Foundation
import MCLCore

/// Start-up check of the core's resources: the assembled app must carry its own resource bundle, otherwise it would
/// start without a shipped language and with the menu from code only — or, built by the native build system,
/// read from the build directory of the machine that built it (see `CoreResources`). The result is a list of
/// Czech messages (UI texts; translation key = the Czech text); empty = everything is in place.
public enum ResourceCheck {

    /// Checks the resources for the main bundle at `bundleURL` (an `.app`, or the directory of the executable).
    ///
    /// - Inside an app the bundle must be in `Contents/Resources` (where `scripts/bundle.sh` puts it): a bundle at the
    ///   app root would still be found by `CoreResources`, but it lies outside `Contents/` and breaks the code seal,
    ///   so it is reported. It must also lie **inside** the app after resolving symbolic links.
    /// - Outside an app the bundle is looked up beside the executable; for the running process itself the final
    ///   fallback is `CoreResources.bundle` (that is `Bundle.module` in tests and `swift run`).
    /// - `lang_en.json` must be a non-empty JSON object, the built-in `menu.json` must load.
    public static func verify(bundleURL: URL) -> [String] {
        let isApp: Bool = CoreResources.isApp(bundleURL)
        let resourceURL: URL = isApp
            ? bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            : bundleURL
        let bundle: Bundle
        // For an app only `Contents/Resources` counts (both arguments = that directory → a single candidate).
        let searchURL: URL = isApp ? resourceURL : bundleURL
        if let url = CoreResources.locate(mainBundleURL: searchURL, mainResourceURL: resourceURL),
           let found = Bundle(url: url) {
            bundle = found
        } else if !isApp, isCurrentProcess(bundleURL), let fallback = CoreResources.bundle {
            bundle = fallback
        } else if isApp, let misplaced = CoreResources.locate(mainBundleURL: bundleURL, mainResourceURL: nil) {
            return ["Balíček zdrojů leží mimo Contents/Resources: " + misplaced.path]
        } else {
            let expected: URL = resourceURL.appendingPathComponent(CoreResources.bundleName)
            return ["Chybí balíček zdrojů aplikace: " + expected.path]
        }
        var problems: [String] = []
        if isApp, !contains(bundleURL, bundle.bundleURL) {
            problems.append("Balíček zdrojů leží mimo aplikaci: " + bundle.bundleURL.resolvingSymlinksInPath().path)
        }
        problems.append(contentsOf: contentProblems(bundle))
        return problems
    }

    /// Problems with the content of a located bundle.
    static func contentProblems(_ bundle: Bundle) -> [String] {
        var problems: [String] = []
        if let bytes = LanguageCatalog.bundledBytes("en", in: bundle) {
            let object: Any? = try? JSONSerialization.jsonObject(with: Data(bytes))
            if bytes.isEmpty || !(object is [String: Any]) {
                problems.append("Vestavěný jazyk je prázdný nebo poškozený: lang_en.json")
            }
        } else {
            problems.append("Chybí vestavěný jazyk: lang_en.json")
        }
        if MenuConfigStore.bundled(in: bundle) == nil {
            problems.append("Chybí nebo je poškozené vestavěné menu: menu.json")
        }
        return problems
    }

    private static func isCurrentProcess(_ bundleURL: URL) -> Bool {
        bundleURL.resolvingSymlinksInPath().standardizedFileURL
            == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Whether `inner` lies inside `outer` after resolving links (`/var` vs `/private/var` included).
    private static func contains(_ outer: URL, _ inner: URL) -> Bool {
        let outerPath: String = outer.resolvingSymlinksInPath().standardizedFileURL.path
        let innerPath: String = inner.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix: String = outerPath.hasSuffix("/") ? outerPath : outerPath + "/"
        return innerPath.hasPrefix(prefix)
    }
}

/// `MacContestLogger --self-check`: the resource check without `NSApplication` (packaging script and CI).
public enum SelfCheck {

    /// Runs the check; problems go to `report` one per line. Returns the process exit code: 0 = OK, 1 = problems.
    public static func run(
        bundleURL: URL = Bundle.main.bundleURL,
        report: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> Int32 {
        let problems: [String] = ResourceCheck.verify(bundleURL: bundleURL)
        for problem in problems {
            report(problem)
        }
        return problems.isEmpty ? 0 : 1
    }
}
