# Third-party notices

MacContestLogger is licensed under the GNU General Public License v3.0 or later (see
`LICENSE`). The repository has no third-party code dependencies (the Swift package
uses only the Swift toolchain and Apple system frameworks). This file lists the third-party
**data** bundled in the repository, its origin and its licence. All of it is used only by
tests and development tools and none of it is compiled into the application, except the OpenJDK
macOS key table (a numeric mapping, see below).

## AD1C Amateur Radio Country Files (`cty.dat`)

- **Files:**
  - `Tests/MCLCoreTests/Fixtures/scorecheck-reference/cty/cty.dat` — unmodified snapshot,
    version `=VER20260611`, SHA-256
    `5a7e4cb1472a1b07461e21956494b0288c65f0e5d3841e6f50f5a9050615968d`;
  - derived small excerpts in the same format: `Tests/MCLCoreTests/Fixtures/scorecheck-cty-mini.dat`
    and the inline `cty.dat` snippets in `Tests/MCLCoreTests/Dxcc/CtyDxccResolverTests.swift`
    and `Tests/MCLCoreTests/Dxcc/DxccSpecialCasesTests.swift`.
- **Source:** Jim Reisert, AD1C — <https://www.country-files.com/>
- **Licence:** MIT-style permission notice, Copyright © 1994-2026 Jim Reisert, AD1C. The full
  notice is in `Tests/MCLCoreTests/Fixtures/scorecheck-reference/cty/COPYRIGHT.txt`.

## DXCC JSON (`dxcc.json`)

- **Files:** `Tests/MCLCoreTests/Fixtures/scorecheck-reference/dxcc-json/dxcc.json` —
  unmodified snapshot of commit `c6412409ddc67ed3045582dcc5382434462ed24b` (2024-11-16).
  The small hand-made test files `Tests/MCLCoreTests/Fixtures/dxcc-test.json` and
  `Tests/MCLCoreTests/Fixtures/dxcc-engine-gate.json` use the same schema.
- **Source:** k0swe/dxcc-json — <https://github.com/k0swe/dxcc-json>; the data is based on the
  ARRL DXCC entity list (<https://www.arrl.org/country-lists-prefixes>).
- **Licence:** Apache License 2.0. The full text is in
  `Tests/MCLCoreTests/Fixtures/scorecheck-reference/dxcc-json/LICENSE`, the notice in
  `Tests/MCLCoreTests/Fixtures/scorecheck-reference/dxcc-json/NOTICE.txt`.

## Callsign/locator aggregate (`ww_digi_grid.csv`)

- **File:** `Tests/MCLCoreTests/Fixtures/contest-data/multipliers/ww_digi_grid.csv`
  (columns `znacka;lokator;pocet` = callsign; Maidenhead locator; number of occurrences).
- **Origin:** an aggregate compiled by the author, Tomáš Kaplan, OK1XOE, from contest logs
  (the CQ WW Digi contest): for each callsign the reported grid locator and how many
  times it was seen. It contains no other data from the logs. It is distributed under the
  licence of this project (GPL-3.0-or-later).

## Other contest data

The rest of `Tests/MCLCoreTests/Fixtures/contest-data/` (contest definitions, band plan and
multiplier lists such as `iaru_hq.csv`, `na_areas.csv`, `ok_om_districts.csv`,
`sp_provinces.csv`) was written by the author from the public contest rules and is
distributed under the licence of this project.

## Measured tool output

Some fixtures are recorded output of third-party programs, kept to test compatibility
with them. They contain no source code of those programs:

- `Tests/MCLCoreTests/Fixtures/hamlib-rigctl-l-4.7.1.txt` — output of `rigctl -l` from
  Hamlib 4.7.1 (<https://hamlib.github.io/>), the list of supported rig models;
- `Tests/MCLCoreTests/Fixtures/mqtt-paho-transcript.tsv` — packet transcript between the
  Eclipse Paho MQTT client and a local Mosquitto broker;
- `Tests/MCLCoreTests/Fixtures/awt-vk-codes-jdk21.tsv` — the values of the `KeyEvent.VK_*`
  constants of JDK 21.

## OpenJDK macOS key table

- **Files:** `Tests/MCLCoreTests/Fixtures/awt-mac-keycodes-jdk21.tsv` and the table `macKeyTable` in
  `Sources/MCLCore/Keys/AwtKeyCodes+Mac.swift` — the mapping of macOS virtual key codes (`kVK`) to
  `java.awt.event.KeyEvent.VK_*` values, extracted from the `keyTable` array;
  `Tests/MCLCoreTests/Fixtures/awt-mac-chars-jdk21.tsv` and the tables in
  `Sources/MCLCore/Keys/AwtKeyCodes+Translate.swift` — the key locations of `keyTable`, the dead-key
  character table `charToDeadVKTable`, the modifier-key table `nsKeyToJavaModifierTable` and the numeric
  constants of the letter/digit mapping in `NsCharToJavaVirtualKeyCode`.
- **Source:** OpenJDK, `src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m`, tag `jdk-21+35`
  (<https://github.com/openjdk/jdk>), Copyright (c) 2011, 2019, Oracle and/or its affiliates.
- **Licence:** the source file is under the GNU General Public License version 2 with the Classpath
  Exception. Only the factual numeric key-code mapping (128 pairs of a `kVK` value and a public
  `KeyEvent.VK_*` constant, 128 key locations, 18 pairs of a dead-key character and a `VK_DEAD_*`
  constant, 6 modifier rows of a mask, left/right `kVK` and a `VK_*` constant, and a few numeric rule
  constants) is reproduced; no source code of the file is included. The extraction scripts are
  `Tools/keys/extract_mac_keytable.sh` and `Tools/keys/extract_mac_chars.sh`;
  they find the tables by their declaration names (`keyTable`, `charToDeadVKTable`,
  `nsKeyToJavaModifierTable`) and the second one accepts only the file with SHA-256
  `b478c7e8…`, because the rule constants were read from that revision by hand.

## Contest logs used for verification (not in the repository)

The scoring verification uses public contest logs (CQ WW, CQ WPX, CQ 160, CQ WW/WPX RTTY,
WW Digi) published by the contest organisers. The logs themselves are **not** part of the
repository; only derived reference results of a small sample are committed
(`Tests/MCLCoreTests/Fixtures/scorecheck-reference/scorecheck-sample-reference-*.tsv`,
`Tests/MCLCoreTests/Fixtures/cabrillo-sample-java.tsv`). The manifests and the selection list
of the full verification corpus are not part of this repository.
