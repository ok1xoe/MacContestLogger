# MacContestLogger

A native macOS contest logger for amateur radio operators, in the spirit of N1MM+. It is a Swift
rewrite of the Java application (version 1.1.1) and shares its data format: contest definitions
(YAML), the SQLite logbook and `config.json`. The user interface is in Czech.

## Requirements

- macOS 14 or newer
- Swift 5.10+ toolchain (Xcode or the Command Line Tools) to build from source
- Optional: [Hamlib](https://hamlib.github.io/) `rigctld` for CAT control, `~/dxcc-json` and
  `~/dxcc-world-map` as external reference data for DXCC lookup and the world map

## Features

- Entry panel with Run and Search & Pounce modes, ESM, F-key messages, text commands in the callsign
  field, dupe check, SCP and N+1 suggestions, call history and "worked before"
- Declarative contest definitions (YAML) with a multiplier engine, score bar, statistics and the
  definition editor; Cabrillo 3.0, ADIF, EDI, CSV and text import and export, log merging, printing
- CAT control of two rigs (split, RIT, SO2V/SO2R, antennas, rotator, footswitch), CW over CAT or
  Winkeyer, voice keyer, fldigi, CQ repeat loop, contest recording and QSO playback
- DX cluster and RBN, band map, available multipliers, callbook lookups (HamQTH, QRZ.com),
  WSJT-X, N1MM and ADIF over UDP, clock check
- Network (multi-operator) log synchronisation over MQTT against a separate cluster authority that is
  not part of this repository
- Microwave bands (23 cm to 3 cm) in addition to the 13 bands of the Java version. A logbook that
  contains a microwave QSO cannot be opened by the Java version.

## Build and run

    swift build
    scripts/bundle.sh --config release            # build/app/MacContestLogger.app
    open build/app/MacContestLogger.app

`scripts/bundle.sh [--config debug|release] [--version vX.Y.Z] [--dmg] [--universal] [--skip-build] [--out DIR]`
assembles the app bundle (ad-hoc signed, no sandbox; `--dmg` adds an unsigned DMG). It ends with
`MacContestLogger --self-check`, which verifies the bundled resources without opening a window.
The first start of an unsigned app that came from a DMG needs right-click, Open.

## Tests

    scripts/test.sh                  # all tests
    scripts/test.sh --filter Name    # a subset

Use `scripts/test.sh` instead of a bare `swift test`: with only the Command Line Tools installed the
swift-testing macro plugin is not loaded automatically, and the script passes it explicitly (with
Xcode the extra flag is harmless). The test suite contains parity tests that compare results with
reference outputs of the Java version 1.1.1 (the `*-java.*` files under `Tests/MCLCoreTests/Fixtures/`).
`scripts/a11y-audit.py` checks the accessibility rules of the views, and CI also runs
`scripts/quit-e2e.py` against a debug bundle.

## User documentation

The user guide (in English) is in [`docs/`](docs/README.md): first steps, every window, operating modes,
the network logbook, data import/export and the definition editor.

## Data and configuration

Application data lives in `~/Library/Application Support/MacContestLogger` (configuration,
logbooks, backups, language files). Set `MCL_DATA_DIR=<dir>` to use a different directory, for
example a throwaway one for experiments. Contest definitions are read from an external directory
(`contests/*.yaml` and `multipliers/*.yaml`) that you choose in the settings; a reference set is in
`Tests/MCLCoreTests/Fixtures/contest-data/`.

Do not run this app at the same time as the Java version: both use the same `config.json` and
logbook databases.

### Safe runs without hardware

Two environment variables make the app inert, for scripted or exploratory runs that must never key
a transmitter or touch the network:

- `MCL_INERT_HARDWARE=1` opens no rig, serial port, audio device, rotator, OTRSP, footswitch or
  fldigi connection.
- `MCL_INERT_NETWORK=1` keeps the DX cluster, callbook services, browser opener, MQTT sync, UDP
  receivers and broadcasters, and the NTP probe inert.

Any value except an unset variable or exactly `0` counts as "inert". For scripted runs use
`scripts/smoke-run.py`, which launches a re-signed copy under a throwaway bundle identifier with a
temporary data directory and both switches set. The first tests with a real rig belong into a dummy
load or with the power at minimum: opening a serial port can briefly key a transmitter whose PTT or
CW is on DTR/RTS. Spotting (Spot It, Ctrl+P, SPOTME) sends a public spot to the cluster.

SIGTERM, SIGINT and SIGHUP run the regular quit, and the transmitter is released first.

## Command-line tools

    swift run mcl-scorecheck --help    # recompute a Cabrillo log's score and compare it with CLAIMED-SCORE
    swift run mcl-synthlog --help      # generate synthetic logs

## Release

A release is built by `.github/workflows/release.yml`: pushing a tag `v1.x.x` (or newer) builds a
universal (arm64 and x86_64) unsigned DMG, checks it on an Intel runner and creates a draft GitHub
release with `MacContestLogger-<version>-macos-universal.dmg` and its `.sha256`. A suffix such as
`-rc1` stays in the file name; the bundle version is `1.2.3`. The version rules are in
`scripts/release-version.sh`. Locally:

    scripts/bundle.sh --config release --universal --version v1.2.3 --dmg --out <dir>

The DMG is neither signed nor notarized, and it uses the same bundle identifier as the Java app.

## Architecture

- `Sources/MCLCore` is the domain logic without UI: `Model/`, `Config/`, `Logbook/` (SQLite),
  `Yaml/` (our own YAML reader and writer, no external dependency), `Dxcc/` and `Callsign/`,
  `BandPlan/`, `Multiplier/` and `Contest/` (definitions, engine, exchange, runtime), `ScoreCheck/`,
  `IO/` (import and export), `Radio/`, `Net/`, `Keys/` and others.
- `Sources/MCLAppModel` holds the view-independent application state, `Sources/MacContestLogger`
  the AppKit/SwiftUI views and the app entry point.
- `Sources/mcl-scorecheck` and `Sources/mcl-synthlog` are the command-line tools.
- Tests are in `Tests/MCLCoreTests` (mirroring `Sources/MCLCore`) and `Tests/MCLAppModelTests`.
- There are no external package dependencies: only the Swift standard library, Foundation, AppKit
  and, in tests, CryptoKit.

`Tests/MCLCoreTests/Fixtures/contest-data/` is the reference set of contest definitions and
multiplier lists; `Package.swift` copies it with `.copy` because `.process` would flatten the
`contests/` and `multipliers/` subdirectories (`ContestDataLayoutTests` guards this).
`multipliers/ww_digi_grid.csv` is an aggregate compiled by the author from CQ WW Digi contest logs
(see `THIRD_PARTY_NOTICES.md`).

## License

Copyright © 2026 Tomáš Kaplan, OK1XOE.

MacContestLogger is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version (GPL-3.0-or-later). See [`LICENSE`](LICENSE)
for the full text. Bundled third-party data and its licences are listed in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
