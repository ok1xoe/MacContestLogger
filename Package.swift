// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacContestLogger",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MCLCore", targets: ["MCLCore"]),
        .executable(name: "mcl-scorecheck", targets: ["mcl-scorecheck"]),
        .executable(name: "MacContestLogger", targets: ["MacContestLogger"]),
    ],
    targets: [
        .target(name: "MCLCore", resources: [.process("Resources")]),
        // App models (state holders, main-thread hops, the resource check) — testable without AppKit windows.
        .target(name: "MCLAppModel", dependencies: ["MCLCore"]),
        // The SwiftUI/AppKit app; `scripts/bundle.sh` assembles it into `MacContestLogger.app`.
        .executableTarget(name: "MacContestLogger", dependencies: ["MCLAppModel", "MCLCore"]),
        .testTarget(name: "MCLAppModelTests", dependencies: ["MCLAppModel", "MCLCore"]),
        // the Java parity suite: command line over `ScoreCheckReport` (the logic lives in MCLCore so it can be tested).
        .executableTarget(name: "mcl-scorecheck", dependencies: ["MCLCore"]),
        // Development tool of the 20k measurement: a synthetic CQ WW CW log and core timings.
        .executableTarget(name: "mcl-synthlog", dependencies: ["MCLCore"]),
        .testTarget(
            name: "MCLCoreTests",
            dependencies: ["MCLCore"],
            // Probe tables read straight from disk by the tests (via `#filePath`), not from the bundle.
            exclude: ["Fixtures/jvm-probes"],
            resources: [
                // `.copy` keeps the directory **verbatim, including nesting**; `.process`
                // **flattens** the tree — measured: with `.process("Fixtures")` all 40 files
                // of `contest-data/` ended up directly in `Contents/Resources/`
                // and the `contests/`/`multipliers/` subdirectories vanished. The
                // `ContestCatalog.fromDir` and `MultiplierSetRegistry.loadDir` rely on
                // that nesting, so `.copy` is required here. `ContestDataLayoutTests` guards it.
                .copy("Fixtures/contest-data"),
                // Post-port microwave bands (section 76): a UHF definition with 23 cm - 3 cm for the end-to-end test.
                .copy("Fixtures/microwave"),
                // Java's broken test definition (`src/test/resources/contests/broken.yaml`)
                // for `ContestValidatorTests`; its own directory so it does not collide with
                // a name in `contest-data/`.
                .copy("Fixtures/contests-broken"),
                // Bytes of `DefinitionEditing.template` from Java for the byte-wise template comparison.
                .copy("Fixtures/definition-editing-java"),
                // `java.util.Properties` manifests from JDK 21: the output of `Properties.store` and a hand-written input for `load`.
                // The bytes are Latin-1, not UTF-8 — `.process` would not convert them, but `.copy`
                // guarantees that even line endings are left untouched.
                .copy("Fixtures/java-properties"),
                // References of the Java parity suite over the corpus: `<set>.<cty|json>.tsv.gz`
                // and the pinned snapshot `cty/cty.dat` (MIT, `cty/COPYRIGHT.txt`; bytes verbatim, `-text`)
                // and `dxcc-json/dxcc.json` (Apache-2.0, `dxcc-json/LICENSE` + `NOTICE.txt`) for the
                // `ScoreCheckParityTests` parity suite in dxcc.json mode. Also the reference of the sample
                // (`scorecheck-sample-reference-<cty|json>.tsv`); the sample logs themselves are not
                // in the repository (`MCL_SCORECHECK_SAMPLE_DIR`).
                .copy("Fixtures/scorecheck-reference"),
                // Error corpus of the gate against Java: `.copy` so the bytes
                // (BOM, CRLF) stay verbatim — the reference carries their SHA-256.
                // `.gitattributes` turns off line-ending conversion for it.
                .copy("Fixtures/definition-errors"),
                // Synthetic "full" definitions for the read arm of the same gate.
                .copy("Fixtures/definition-synthetic"),
                // Synthetic definitions for the engine gate only (`JavaEngineParityTests`, int/long overflow);
                // kept outside `definition-synthetic/` so the reference of the definitions gate does not move.
                .copy("Fixtures/engine-gate-synthetic"),
                // Synthetic definitions for the session gate only (`JavaSessionParityTests`: bonuses, QTC,
                // session from a definition, exceptions after a partial write); outside the other synthetic fixture directories.
                .copy("Fixtures/session-gate-synthetic"),
                // Synthetic edge-case Cabrillo logs for the `ScoreCheck` core: `.copy` so the bytes (BOM, CR, NBSP,
                // invalid UTF-8) stay verbatim; `.gitattributes` turns off line-ending conversion.
                .copy("Fixtures/scorecheck-edge"),
                // Edge-case inputs of the ADIF/Cabrillo readers:
                // `.copy` and `-text` so the bytes (BOM, CR, NBSP, Latin-1, invalid UTF-8) stay verbatim.
                .copy("Fixtures/io-edge"),
                // Synthetic Club Log `cty.xml` (every section) for the parser, resolver and cache tests.
                .copy("Fixtures/clublog-cty"),
                // Parity suite against Java over `io/`: synthetic definitions
                // (without the Cabrillo field order, without `cabrillo:`) and gzipped references of both arms —
                // `.copy` so the gzip bytes pass through unchanged.
                .copy("Fixtures/io-gate-synthetic"),
                .copy("Fixtures/io-export-java.json.gz"),
                .copy("Fixtures/io-import-java.json.gz"),
                // the Java parity suite: hand-made corpus and DSP PCM fixtures (`-text`) + gzipped
                // Java reference; `.copy` so the bytes pass through unchanged.
                .copy("Fixtures/radio-gate"),
                .copy("Fixtures/radio-logic-java.json.gz"),
                .copy("Fixtures/radio-conversation-java.json.gz"),
                // Reference of the logic arm of the Java parity suite; `.copy` so the gzip bytes pass through unchanged.
                .copy("Fixtures/net-logic-java.json.gz"),
                // Scripts and reference of the conversation arm of the Java parity suite.
                .copy("Fixtures/net-gate"),
                .copy("Fixtures/net-conversation-java.json.gz"),
                // Reference of the Java parity suite; `.copy` so the gzip bytes pass through unchanged.
                .copy("Fixtures/core-a-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/core-b-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/ui-a-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/ui-b-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/ui-c-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/ui-d-java.json.gz"),
                // Reference of the Java parity suite.
                .copy("Fixtures/ui-e-java.json.gz"),
                // Reference of the Java parity suite and its synthetic spot corpus.
                .copy("Fixtures/ui-f-java.json.gz"),
                // Reference of the Java parity suite; its synthetic corpus `net-g.txt` lives in
                // `ui-gate` with the spot corpus of fixture `f`.
                .copy("Fixtures/ui-g-java.json.gz"),
                // Reference of the Java parity suite; its synthetic corpus `tools-h.txt` lives in
                // `ui-gate` too.
                .copy("Fixtures/ui-h-java.json.gz"),
                .copy("Fixtures/ui-gate"),
                // Jackson profile merge of v1.1.1.
                .copy("Fixtures/profile-merge-java.tsv.gz"),
                // Flat fixtures are listed one by one because `.process("Fixtures")`
                // would overlap with the `.copy` rules above and SwiftPM rejects the overlap
                // ("duplicate resource rule"). A new flat fixture = a new line here;
                // if forgotten, the test will not find it and will fail, so it cannot go unnoticed.
                .process("Fixtures/contest-data-jackson.json"),
                .process("Fixtures/config-v1.1.1.json"),
                .process("Fixtures/logbook-v1.1.1.sqlite"),
                .process("Fixtures/logbook-legacy-no-contest-id.sqlite"),
                .process("Fixtures/dxcc-test.json"),
                // References of the `JavaDefinitionParityTests` gate.
                .process("Fixtures/contest-data-definitions.json"),
                .process("Fixtures/definition-errors-java.json"),
                .process("Fixtures/definition-write-cases.json"),
                .process("Fixtures/definition-write-java.json"),
                // References of the `JavaEngineParityTests` gate.
                .process("Fixtures/dxcc-engine-gate.json"),
                .process("Fixtures/engine-score-java.json"),
                .process("Fixtures/engine-exchange-java.json"),
                .process("Fixtures/engine-expressions-java.json"),
                // References of the `JavaSessionParityTests` gate.
                .process("Fixtures/session-live-java.json"),
                .process("Fixtures/session-replay-java.json"),
                .process("Fixtures/session-views-java.json"),
                // Reference of `ScoreCheckMeasuredTests` and its
                // own mini `cty.dat` (not the file from country-files.com).
                .process("Fixtures/scorecheck-edge-java.tsv"),
                .process("Fixtures/scorecheck-cty-mini.dat"),
                // Java result of the readers over `Fixtures/io-edge/`.
                .process("Fixtures/io-edge-java.tsv"),
                // Java result of `CabrilloReader` over the sample logs.
                .process("Fixtures/cabrillo-sample-java.tsv"),
                // Java result of `CabrilloExporter` and `QtcPlanner.cabrilloLine` (scenarios, functions and export →
                // ScoreCheck over 22 definitions).
                .process("Fixtures/cabrillo-export-java.tsv"),
                // YAML fuzz sample against Java.
                .process("Fixtures/yaml-fuzz-sample.tsv"),
                // Real output of `rigctl -l` (hamlib 4.7.1) for `HamlibRigList.parseLine` and `RigScanner`.
                .process("Fixtures/hamlib-rigctl-l-4.7.1.txt"),
                // Packet-level transcript of Paho (`MqttSyncTransport` v1.1.1) ↔ local Mosquitto:
                // CONNECT and SUBSCRIBE are compared byte for byte.
                .process("Fixtures/mqtt-paho-transcript.tsv"),
                // AWT `KeyEvent.VK_*` table from JDK 21,
                // from which `Sources/MCLCore/Keys/AwtKeyCodes+Table.swift` is generated.
                .process("Fixtures/awt-vk-codes-jdk21.tsv"),
                // macOS `kVK` → AWT VK table of JDK 21 (`keyTable` in OpenJDK `AWTEvent.m`, tag `jdk-21+35`;
                // `Tools/keys/extract_mac_keytable.sh`) for `AwtKeyCodesMacTests`.
                .process("Fixtures/awt-mac-keycodes-jdk21.tsv"),
                // Character branch and modifier keys of the same `AWTEvent.m`
                // (`Tools/keys/extract_mac_chars.sh`) for `AwtKeyTranslateTests`.
                .process("Fixtures/awt-mac-chars-jdk21.tsv"),
            ]
        ),
    ]
)
