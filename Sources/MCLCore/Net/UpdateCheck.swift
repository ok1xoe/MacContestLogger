import Foundation

/// N1MM „Check for New Program Version": the latest published release of the public repository (GitHub's
/// `releases/latest`, which leaves out drafts and pre-releases) compared with the running version. Pure logic — the
/// app model makes the one HTTP GET, only when the user asks (the menu item) or opted in to the check at start.
public enum UpdateCheck {

    /// GitHub's API for the newest published release.
    public static let latestReleaseUrl = "https://api.github.com/repos/ok1xoe/MacContestLogger/releases/latest"
    /// The release page opened when the API gives no usable page.
    public static let releasesPageUrl = "https://github.com/ok1xoe/MacContestLogger/releases/latest"
    /// Only pages of the project's own releases are ever opened.
    static let releasePagePrefix = "https://github.com/ok1xoe/MacContestLogger/releases/"

    /// A published release.
    public struct Release: Equatable, Sendable {
        /// The tag (`v0.9.0`).
        public let tag: String
        /// The release page in the browser.
        public let pageUrl: String

        public init(tag: String, pageUrl: String) {
            self.tag = tag
            self.pageUrl = pageUrl
        }

        /// The version without the leading `v` (`0.9.0`).
        public var version: String {
            UpdateCheck.trimmedVersion(tag)
        }
    }

    /// What the check found.
    public enum Outcome: Equatable, Sendable {
        /// A newer release than the running one.
        case newer(Release)
        /// The running version is the newest (or newer, a development build).
        case upToDate(Release)
        /// The answer was not usable: the HTTP status, or `nil` for a body that is not a release.
        case failed(status: Int?)
    }

    /// The release of an API answer (`tag_name`, `html_url`); `nil` when the body is not one. A page outside the
    /// project's releases is replaced by `releasesPageUrl`.
    public static func parse(_ body: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tag = (object["tag_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tag.isEmpty, components(tag) != nil else {
            return nil
        }
        let page: String = (object["html_url"] as? String).flatMap { $0.hasPrefix(releasePagePrefix) ? $0 : nil }
            ?? releasesPageUrl
        return Release(tag: tag, pageUrl: page)
    }

    /// The outcome of an HTTP answer for the running `current` version (`nil` = unknown: any release is newer).
    public static func evaluate(status: Int, body: Data, current: String?) -> Outcome {
        guard status == 200 else { return .failed(status: status) }
        guard let release = parse(body) else { return .failed(status: nil) }
        guard let current, compare(release.tag, current) != nil else { return .newer(release) }
        return (compare(release.tag, current) ?? 0) > 0 ? .newer(release) : .upToDate(release)
    }

    /// `1` when `a` is newer than `b`, `0` when equal, `-1` when older; `nil` when either is not a version.
    /// `v0.10.0` > `v0.9.1`; missing parts count as 0; a pre-release (`1.0.0-rc1`) is older than its release.
    public static func compare(_ a: String, _ b: String) -> Int? {
        guard let left = components(a), let right = components(b) else { return nil }
        for index in 0..<max(left.numbers.count, right.numbers.count) {
            let x: Int = index < left.numbers.count ? left.numbers[index] : 0
            let y: Int = index < right.numbers.count ? right.numbers[index] : 0
            if x != y {
                return x > y ? 1 : -1
            }
        }
        switch (left.preRelease, right.preRelease) {
        case (false, true): return 1
        case (true, false): return -1
        default: return 0
        }
    }

    /// `v1.2.3-rc1` → `1.2.3-rc1`.
    static func trimmedVersion(_ text: String) -> String {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func components(_ text: String) -> (numbers: [Int], preRelease: Bool)? {
        let version: String = trimmedVersion(text)
        let parts: [Substring] = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = parts.first, !core.isEmpty else { return nil }
        var numbers: [Int] = []
        for piece in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard !piece.isEmpty, piece.allSatisfy(\.isASCII), let number = Int(piece), number >= 0 else {
                return nil
            }
            numbers.append(number)
        }
        return (numbers, parts.count > 1)
    }
}
