# MacContestLogger

A native macOS contest logger for amateur radio operators, in the spirit of N1MM+. It is a Swift
rewrite of the Java application (version 1.1.1) and shares its data format: contest definitions
(YAML), the SQLite logbook and `config.json`. The user interface is in Czech.

## Requirements

- macOS 14 or newer
- Swift 5.10+ toolchain (Xcode or the Command Line Tools) to build from source
- Optional: [Hamlib](https://hamlib.github.io/) `rigctld` for CAT control
- Recommended: two public reference data sets in your home directory (see below)

## Reference data (DXCC and world map)

The app does not ship country data or map outlines. It reads them from two folders in your home
directory, each a clone of a separate public repository:

```bash
git clone https://github.com/k0swe/dxcc-json ~/dxcc-json
git clone https://github.com/amazingproducer/dxcc-world-map ~/dxcc-world-map
```

| Folder | Used for | Without it |
|---|---|---|
| `~/dxcc-json` (`dxcc.json`, `cty.dat`) | DXCC country, continent and CQ/ITU zones of a callsign — needed for most contest multipliers and for the DXCC recalculation | countries and zones are not resolved; "Přepočet DXCC" reports missing country data |
| `~/dxcc-world-map` (`dxcc.geojson`) | country outlines in the world map window | the map is drawn without country outlines |

Update them now and then with `git pull` in each folder; restart the app afterwards.

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
    swift run mcl-manual --lang en --out-dir build/manual   # the English user guide as a PDF and as HTML
    swift run mcl-manual --lang cs --out-dir build/manual   # the Czech one (docs/cs/)
    scripts/shots.sh --lang cs|en [--only name]             # render the guide's screenshots offscreen

`mcl-manual` turns `docs/*.md` into one PDF (order and parts from `docs/README.md`; title page, contents with page
numbers, bookmarks, page numbers, links; a short chapter goes on below the previous one instead of leaving most of a
page empty) using only AppKit's text layout and PDFKit, so it needs nothing installed. `--html` writes the same guide
as one self-contained HTML file (images embedded as data URIs, linked contents, numbered chapters, light and dark
screen styles, an A4 print style that breaks pages where the PDF does), meant to be adjusted and exported to PDF from
a browser. Either or both can be requested in one run (`--out`, `--html`), or both by `--out-dir` as
`MacContestLogger-manual-<lang>.pdf/.html` (the English guide also as `MacContestLogger-manual.pdf/.html`). It fails
when a page or an image linked from the guide is missing; CI builds both languages on every pull request.

The guide exists in two languages. `--lang en` (the default) reads `docs/*.md` and takes each screenshot
`docs/img/<name>.png` from `docs/img/en/<name>.png` when that English screenshot exists; otherwise the Czech one is
used, its caption says so and the introduction adds a note. `--lang cs` reads `docs/cs/README.md` (chapter order) and
`docs/cs/*.md` with the Czech screenshots in `docs/img/`; a page not translated yet is taken from English with a
warning, and `--strict-lang` turns that into an error (`ManualLanguageTests` checks the Czech guide strictly as soon as
`docs/cs/README.md` exists). The title page, contents and dates follow the language. The screenshots are rendered
offscreen from the app's own views over a demo station (`scripts/shots.sh`, manifest `docs/screenshots.json`; see
[docs/screenshots.md](docs/screenshots.md)).

## Release

A release is built by `.github/workflows/release.yml`: pushing a version tag such as `v0.9.0` builds a
universal (arm64 and x86_64) DMG, checks it on an Intel runner and creates a draft GitHub
release with `MacContestLogger-<version>-macos-universal.dmg`, its `.sha256` and the user guide
`MacContestLogger-manual.pdf` and `MacContestLogger-manual.html` (English) and `MacContestLogger-manual-cs.pdf` and
`MacContestLogger-manual-cs.html` (Czech), built by `mcl-manual`; the app's Help menu downloads the one in the
application's language from the latest release. A suffix such as
`-rc1` stays in the file name; the bundle version is `0.9.0`. The version rules are in
`scripts/release-version.sh`. Locally:

    scripts/bundle.sh --config release --universal --version v0.9.0 --dmg --out <dir>

The app uses the same bundle identifier as the Java app.

### Signing and notarization

When the repository has the six secrets below, the release workflow signs the app with a Developer ID
Application certificate (hardened runtime, `packaging/MacContestLogger.entitlements`: microphone only, no
App Sandbox, which would block serial ports, `rigctld` and plugin scripts), signs the DMG, notarizes it with
`notarytool`, staples the ticket and checks the result with `spctl` (also on the Intel runner). Without the
secrets (forks, pull requests from forks) the workflow builds the same DMG unsigned, with an ad-hoc signed app,
and says "unsigned build (signing secrets not set)"; a partial set fails the build.

| Secret | Content |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Developer ID Application certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12` |
| `MACOS_CERT_PASSWORD` | the password chosen for that `.p12` export |
| `NOTARY_KEY_P8_BASE64` | App Store Connect API key (Users and Access → Integrations → Team Keys, role Developer), the downloaded `AuthKey_<id>.p8` as `base64 -i AuthKey_<id>.p8` |
| `NOTARY_KEY_ID` | the key ID of that API key |
| `NOTARY_ISSUER_ID` | the issuer ID shown above the team keys list |
| `APPLE_TEAM_ID` | the ten-character team ID; it selects the Developer ID identity |

Set them with `gh secret set <NAME>` (reads the value from standard input). Locally, a signed build is

    scripts/bundle.sh --config release --universal --dmg --sign "Developer ID Application: <name> (<team id>)" --timestamp

and `--sign -` runs the same hardened-runtime path with an ad-hoc signature (no notarization). Without `--sign`,
`scripts/bundle.sh` signs ad-hoc as before.

## Architecture

- `Sources/MCLCore` is the domain logic without UI: `Model/`, `Config/`, `Logbook/` (SQLite),
  `Yaml/` (our own YAML reader and writer, no external dependency), `Dxcc/` and `Callsign/`,
  `BandPlan/`, `Multiplier/` and `Contest/` (definitions, engine, exchange, runtime), `ScoreCheck/`,
  `IO/` (import and export), `Radio/`, `Net/`, `Keys/` and others.
- `Sources/MCLAppModel` holds the view-independent application state, `Sources/MacContestLogger`
  the AppKit/SwiftUI views and the app entry point.
- `Sources/mcl-scorecheck`, `Sources/mcl-synthlog` and `Sources/mcl-manual` (over `Sources/MCLManual`) are the
  command-line tools.
- Tests are in `Tests/MCLCoreTests` (mirroring `Sources/MCLCore`) and `Tests/MCLAppModelTests`.
- There are no external package dependencies: only the Swift standard library, Foundation, AppKit
  and, in tests, CryptoKit. `Sources/MMTTYCore`, `ModemKit`, `RTTYModem` and `RTTYSignalKit` are the
  RTTY modem vendored from RYRY (LGPL-3.0).

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
for the full text. The built-in RTTY modem uses the MMTTY core by JE3HHT through RYRY (GNU LGPL v3,
[`third-party/MMTTY/NOTICE.md`](third-party/MMTTY/NOTICE.md)). Bundled third-party code and data and their
licences are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
