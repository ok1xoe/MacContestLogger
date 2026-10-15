# MMTTY RTTY core (via RYRY)

MacContestLogger's built-in RTTY modem reuses the decoder and modulator of **MMTTY** through the macOS
port in **RYRY**.

- **MMTTY** — Copyright 2000-2013 Makoto Mori (JE3HHT) and Nobuyuki Oba (JA7UDE). MMTTY is free software
  under the GNU Lesser General Public License v3 or later. Original source: <https://github.com/n5ac/mmtty>.
- **RYRY** — a native macOS RTTY application based on MMTTY. Copyright 2026 Tomáš Kaplan, OK1XOE.
  GNU LGPL v3. Source: <https://github.com/ok1xoe/RYRY>, vendored from commit
  `8497703ac935922a5e4b9ede27df7c0dbeccb9c0`.

## Vendored files

| Directory | Contents | Origin |
|---|---|---|
| `Sources/MMTTYCore/mmtty/` | MMTTY's DSP classes (`Rtty`, `fir`, `Fft`, `CLX`), modified for portability | MMTTY via RYRY |
| `Sources/MMTTYCore/` (`RTTYCore.cpp`, `AFC.*`, `compat/`, `include/`) | the C API around the core, AFC, Windows/VCL compatibility | RYRY (AFC and the context from MMTTY) |
| `Sources/ModemKit/` | the generic modem interface | RYRY |
| `Sources/RTTYModem/` | the Swift RTTY modem over the C API | RYRY |
| `Sources/RTTYSignalKit/` | an independent AFSK test-signal generator and deterministic noise | RYRY |
| `Tests/RTTYModemTests/` (except `DecodeAccuracyTests.swift`) | the core and modem tests | RYRY |

Every vendored file keeps its copyright notice. Changes made for MacContestLogger are limited to the
provenance header of the Swift files and the build settings in `Package.swift`.

## Licence

These files are licensed under the GNU Lesser General Public License version 3 (`COPYING.LESSER` in this
directory), which supplements the GNU General Public License version 3 (`LICENSE` at the repository root).
MacContestLogger as a whole is distributed under the GPL-3.0-or-later, which LGPL-3.0 code may be combined with.
The complete corresponding source of the library is the directories listed above.
