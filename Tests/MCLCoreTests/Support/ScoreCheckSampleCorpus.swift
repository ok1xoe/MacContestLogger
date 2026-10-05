import Foundation
import Testing

/// Location of the sample corpus (424 anonymised third-party Cabrillo logs, `<set>/<log>`).
///
/// The logs are not part of the repository: they are third-party contest logs, so they stay in
/// the owner's local corpus directory. Only the derived references (per-log hashes and scores:
/// `scorecheck-reference/scorecheck-sample-reference-<cty|json>.tsv`, `cabrillo-sample-java.tsv`,
/// the `sample` entry of `io-import-java.json.gz`) are committed.
///
/// Resolution order:
/// 1. `MCL_SCORECHECK_SAMPLE_DIR` — used as is (a missing directory disables the tests, so
///    `MCL_SCORECHECK_SAMPLE_DIR=/nonexistent` forces the skip);
/// 2. `~/cq_deniky/scorecheck-sample`, if it exists.
///
/// Tests that need the logs use `.enabled(if: ScoreCheckSampleCorpus.available, ScoreCheckSampleCorpus.skipReason)`;
/// when the corpus is present, every log is still checked against the SHA-256 recorded in the
/// committed reference, so a wrong or modified corpus fails loudly instead of passing.
enum ScoreCheckSampleCorpus {

    static let environmentKey = "MCL_SCORECHECK_SAMPLE_DIR"

    /// The configured directory (whether or not it exists).
    static let directory: URL = {
        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("cq_deniky/scorecheck-sample", isDirectory: true)
    }()

    static let available: Bool = {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }()

    static let skipReason = Comment(rawValue:
        "sample corpus not found at \(directory.path) (set \(environmentKey); the logs are not in the repository)")
}
