import Foundation
import Testing
@testable import MCLCore

/// Shared helpers of the integration tests: the rows of the JVM probe, its text escaping, and the runtime over the
/// fixtures' contest data (the probe's synthetic DXCC, my station OK1XOE in JN79).
enum IntegrationsFixture {

    static let ownCall = "OK1XOE"

    /// The rows of one kind (first column), split into columns, in probe order.
    static func rows(_ kind: String) -> [[String]] {
        IntegrationsJava.tsv.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.first == kind }
    }

    /// The probe's `esc`: UTF-16 units < 0x20, > 0x7E and `\` as `\uXXXX`; `nil` as `<null>`.
    static func escape(_ text: String?) -> String {
        guard let text else { return "<null>" }
        var out = ""
        for unit in text.utf16 {
            if unit >= 0x20 && unit < 0x7F && unit != 0x5C {
                out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            } else {
                out += String(format: "\\u%04X", Int(unit))
            }
        }
        return out
    }

    /// Reverses `escape` (`<null>` stays as is).
    static func unescape(_ text: String) -> String {
        let units = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x5C, i + 5 < units.count + 0, units[i + 1] == 0x75 {
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                if let value = UInt16(hex, radix: 16) {
                    out.append(value)
                    i += 6
                    continue
                }
            }
            out.append(units[i])
            i += 1
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// A runtime over the fixtures with the given contest activated (`nil` = none).
    static func runtime(contest: String?) throws -> ContestRuntime {
        let runtime = try SpotAnalysisFixture.environment().runtime
        if let contest {
            if let error = runtime.activate(id: contest) {
                Issue.record("activation failed: \(error.czech)")
                throw CancellationError()
            }
        }
        return runtime
    }

    /// An analyzer that sees no callbook, no grid data (the probe's `ContestController` had none).
    static func analyzer(_ runtime: ContestRuntime) throws -> SpotAnalyzer {
        let env = try SpotAnalysisFixture.environment()
        return SpotAnalyzer(runtime: runtime, bandPlan: env.bandPlan, digiFrequencies: env.digi, gridDatabase: env.gridDb,
                            gridFieldMap: env.fieldMap, callbook: { _ in nil }, gridLog: nil, now: { Date() })
    }

    static func loopback(_ port: Int) throws -> UdpEndpoint {
        try UdpEndpoint.resolve(host: "127.0.0.1", port: port)
    }
}
