import Foundation
import Testing
@testable import MCLCore

/// `CabrilloReader.readFile` = Java v1.1.1:
/// - over the edge files `Fixtures/io-edge/CR*.log` (reference `io-edge-java.tsv`): every
///   QSO field by field, the exception category, decoding;
/// - over all logs of the sample `<set>/<log>` (reference `cabrillo-sample-java.tsv`,
///   a maintainer-only probe): the QSO count or the exception class and a SHA-256 over
///   **all QSO tuples** of the log. The logs are not distributed with the sources: they are read from
///   `ScoreCheckSampleCorpus.directory` and these tests are skipped when it is absent; the
///   reference itself is checked always (`sampleReferenceIsComplete`).
///
/// The input fingerprint (SHA-256 of bytes) tells "REGENERATE REFERENCE" apart (the input changed, the reference is stale)
/// from "MISMATCH" (the input matches, the result differs).
@Suite struct CabrilloJavaParityTests {

    private typealias Fixture = CabrilloEdgeFixture

    @Test func edgeFilesMatchJava() throws {
        try JavaV111Gate.run {
            let reference = try Fixture.edgeReference()
            #expect(reference.version["java.version"] == "21.0.2")
            #expect(reference.version["locale"] == "en_US")
            let dir = try Fixture.edgeDirectory()
            let onDisk = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".log") }
            #expect(Set(onDisk) == Set(reference.files.map(\.name)), "REGENERATE REFERENCE: a different set of edge files")
            try #require(reference.files.count == 29)

            var distinguished = 0
            var qsoCount = 0
            for file in reference.files {
                let url = dir.appendingPathComponent(file.name)
                let data = try Data(contentsOf: url)
                try #require(Fixture.sha256Hex(data) == file.sha256, "REGENERATE REFERENCE: \(file.name) has different bytes")
                #expect(Fixture.decoding(data) == Fixture.javaDecodingCategory(file.decoding),
                        "MISMATCH decoding: \(file.name)")
                let result = Fixture.readFile(url)
                #expect(Fixture.swiftReadCategory(result, message: true) == Fixture.javaReadCategory(file.read),
                        "MISMATCH read: \(file.name)")
                let javaQsos = reference.qsos[file.name] ?? []
                // A lone surrogate must not arise in a Cabrillo tuple (the reader splits only on ASCII); if
                // it appeared, a Swift `String` could not carry it and the case would have to go on the exception list.
                for tuple in javaQsos {
                    #expect(!tuple.contains { $0.range(of: "\\\\uD[89A-F][0-9A-F]{2}", options: .regularExpression) != nil },
                            "a lone surrogate in the Java tuple \(file.name) — an exception by name is needed")
                }
                guard case .success(let qsos) = result else {
                    #expect(javaQsos.isEmpty, "\(file.name): Java has QSOs, Swift an exception")
                    continue
                }
                #expect(qsos.count == javaQsos.count, "\(file.name): QSO count")
                for (index, (swift, java)) in zip(qsos, javaQsos).enumerated() {
                    let normalized = Fixture.normalized(java)
                    distinguished += normalized.distinguished
                    #expect(Fixture.tuple(swift) == normalized.tuple, "MISMATCH: \(file.name) QSO \(index)")
                    qsoCount += 1
                }
            }
            // How many times Java returned `""` (not `null`) in text — indistinguishable after
            // normalisation. The Cabrillo reader does not create `""` (tokens are not empty).
            print("CabrilloJavaParityTests: edge files \(reference.files.count), QSOs \(qsoCount), "
                  + "Java \"\" vs null distinguished: \(distinguished)")
            #expect(distinguished == 0)
            #expect(qsoCount > 50)
        }
    }

    @Test func sampleReferenceIsComplete() throws {
        let (version, logs) = try Fixture.sampleReference()
        #expect(version["java.version"] == "21.0.2")
        #expect(version["locale"] == "en_US")
        #expect(logs.count == 424)
        #expect(Set(logs.map(\.path)).count == 424)
    }

    @Test(.enabled(if: ScoreCheckSampleCorpus.available, ScoreCheckSampleCorpus.skipReason))
    func sampleLogsMatchJava() throws {
        try JavaV111Gate.run {
            let (version, logs) = try Fixture.sampleReference()
            #expect(version["java.version"] == "21.0.2")
            #expect(version["locale"] == "en_US")
            #expect(logs.count == 424)
            let dir = Fixture.sampleDirectory()

            var qsoTotal = 0
            var exceptions = 0
            var unreadable = 0
            var distinguished = 0
            let started = Date()
            for log in logs {
                let url = dir.appendingPathComponent(log.path)
                let data = try Data(contentsOf: url)
                try #require(Fixture.sha256Hex(data) == log.sha256, "REGENERATE REFERENCE: \(log.path) has different bytes")
                #expect(Fixture.decoding(data) == log.decoding, "MISMATCH decoding: \(log.path)")
                let result = Fixture.readFile(url)
                #expect(Fixture.swiftReadCategory(result) == Fixture.javaReadCategory(log.read), "MISMATCH read: \(log.path)")
                switch result {
                case .success(let qsos):
                    qsoTotal += qsos.count
                    distinguished += Int(log.javaEmptyTexts) ?? 0
                    var lines = Data()
                    for (index, q) in qsos.enumerated() {
                        lines.append(contentsOf: Array(Fixture.digestLine(index, q).utf8))
                    }
                    #expect(Fixture.sha256Hex(lines) == log.tupleDigest, "MISMATCH n-tic QSO: \(log.path)")
                case .failure(let error):
                    if case .unreadable = error { unreadable += 1 } else { exceptions += 1 }
                }
            }
            let seconds = Date().timeIntervalSince(started)
            print("CabrilloJavaParityTests: sample \(logs.count) logs, QSOs \(qsoTotal), exceptions \(exceptions), "
                  + "unreadable \(unreadable), Java \"\" vs null distinguished: \(distinguished), "
                  + "time \(Int(seconds * 1000)) ms")
            #expect(qsoTotal == 131_331)
            #expect(exceptions == 1)
            #expect(unreadable == 3)
            #expect(distinguished == 0)
        }
    }

    /// The largest readable log of the sample (`cqwpx-2026ph/hd8r.log`, 513 kB) — time measurement in debug.
    @Test(.enabled(if: ScoreCheckSampleCorpus.available, ScoreCheckSampleCorpus.skipReason))
    func largestReadableSampleLogTiming() throws {
        let url = Fixture.sampleDirectory().appendingPathComponent("cqwpx-2026ph/hd8r.log")
        let row = try #require(try Fixture.sampleReference().logs.first { $0.path == "cqwpx-2026ph/hd8r.log" })
        try #require(Fixture.sha256Hex(try Data(contentsOf: url)) == row.sha256, "REGENERATE REFERENCE: hd8r.log has different bytes")
        let started = Date()
        let qsos = try CabrilloReader().readFile(url)
        let seconds = Date().timeIntervalSince(started)
        print("CabrilloJavaParityTests: hd8r.log \(qsos.count) QSO za \(Int(seconds * 1000)) ms")
        #expect(!qsos.isEmpty)
    }
}
