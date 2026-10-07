# Text commands in the callsign field

Instead of a callsign, type a command into the **Callsign** field and confirm with **Enter**.
The command is executed, the field is cleared and the result is shown in the status line
of the main window. Case does not matter.

The set of commands is based on N1MM Logger+
([Callsign Box Text Commands](https://n1mmwp.hamdocs.com/manual-windows/entry-window/))
and DXLog ([Text commands](https://dxlog.net/docs/index.php?title=Keyboard_and_text_functions#Text_commands)).

## Frequency (kHz)

| Entry | Meaning | Example (at 14,074 kHz) |
|---|---|---|
| full frequency | QSY to the given frequency, also to another band | `14025.1` → 14,025.1 kHz · `7012` → 7,012 kHz |
| partial frequency | counted from the lower edge of the current band | `025.1` → 14,025.1 kHz · `250` → 14,250 kHz |
| `0` | start of the current band | `0` → 14,000 kHz |
| `+n` / `-n` | shift by n kHz | `+2` → 14,076 kHz · `-0.5` → 14,073.5 kHz |

### Second VFO and split (requires a connected transceiver via CAT)

| Entry | Meaning |
|---|---|
| `/14030`, `/025`, `/+2` | frequency of the **second VFO (B)**. Split is not turned on and reception on VFO A stays. A relative entry is counted from VFO B when it is known (split), otherwise from VFO A |
| frequency + **Ctrl+Enter** | **split**: the entered frequency is the transmit frequency. `+2` + Ctrl+Enter means transmit 2 kHz higher, `14030` + Ctrl+Enter transmit on 14,030 kHz |
| `SPLIT` | turns on split and leaves the VFO B frequency as it is |
| `NOSPLIT` / `SPLITOFF` | turns off split and transmission is on VFO A again |
| `SWAP` | swaps VFO A ↔ B (DXLog) |

When split is on, the info bar shows **SPLIT TX 14030.0** in red. The state is
read from the rig, so split turned on directly on the rig is shown too.

A decimal comma works the same as a dot (`14025,1`). A full frequency takes precedence:
`1830` on 20 m means 1,830 kHz (160 m), not 14,000 + 1,830. An entry that leads to no
band is not executed and, above all, is **not logged as a callsign**. The status line
shows why. With CAT connected, the rig is retuned as well.

## Mode

`CW`, `SSB`, `USB`, `LSB`, `AM`, `FM`, `RTTY`, `PSK` (`PSK31`, `PSK63`, `PSK125`, `PSK250`),
`FT8`, `FT4`, `JT65`, `DIGITAL` (`DIGI`)

The command switches the mode for logging QSOs and, with CAT connected, the rig's mode.
The default report switches to 599 or 59. `USB` and `LSB` are logged as SSB and the
sideband is chosen by CAT by convention according to the frequency (LSB below 10 MHz).
In a single-mode contest the mode is given by the definition, so the command is not executed.

## Other

| Command | Alias | Action |
|---|---|---|
| `OPON` | `LOGIN` | operator login; `OPON` alone opens the dialog, `OPON OK1XOE` sets it directly (like Ctrl+O) |
| `WIPELOG` | `CLEARLOG` | deletes all QSOs of the current log and resets the score. Asks first. In a cluster the deletion also takes effect on the other stations. |
| `VERSION` | `VER` | program version |
| `EXPORT` | | export the log to ADIF (like the menu) |
| `IMPORT` | | import QSOs from ADIF/Cabrillo (like the menu) |
| `WRITELOG` | `MAKELOG` | export the log to Cabrillo (like the menu) |
| `RESCORE` | | recalculates the contest score from scratch (like Nástroje → Přepočítat skóre / Tools → Recalculate score) |
| `ESM` | `ESMON` | turns on ESM (Enter sends messages), see [esm.md](esm.md) |
| `NOESM` | `ESMOFF` | turns it off |
| `AUTORSP` | `AUTORSPON` | turns on automatic Run/S&P switching based on the CQ frequency, see [run-sp.md](run-sp.md) |
| `NOAUTRSP` | `NOAUTORSP`, `AUTORSPOFF` | turns it off (like Alt+F11) |
| `SPLIT` | | turns on split (see above) |
| `NOSPLIT` | `SPLITOFF` | turns off split |
| `SWAP` | | swaps VFO A ↔ B |
| `SETUP` | | opens Settings |
| `TOUR 1200/30` | | contest session, dupes only within the session; `TOUR` without an argument takes the Snt field, `NOTOUR` turns it off — see [qso-party.md](qso-party.md) |
| `ROVERQTH HAM` | | my county (rover); without an argument a dialog |
| `COUNTYLINE DAD,JEF` | | county line: the QSO is logged for each county; `NOCOUNTYLINE` turns it off |
| `BONUS W1AW,K1BON` | | bonus stations (QSO party); without an argument a dialog |
| `SPOTME` | | spots your own station to the DX cluster (DXLog); Alt+P / Spot It spots the callsign from the field |
| `NETON` | `NET` | turns on network log synchronization (the cluster must be filled in under Settings) |
| `NETOFF` | `NONET` | turns off network synchronization; the station keeps logging locally |
| `OPOFF` | `LOGOUT` | logs the operator out, back to the default from the station details (DXLog) |
| `AUTORSP` / `RUNSP` | `RUNSPON` | turns on automatic Run/S&P switching (DXLog) |
| `NOAUTRSP` / `NORUNSP` | `RUNSPOFF` | turns it off |

### CW and CQ repeat

| Command / key | Alias | Action |
|---|---|---|
| `RPT`, **Alt+R** | | CQ repeat: F1, run to completion, pause, again. Typing a callsign pauses it (it resumes after the field is cleared), **Esc** or `NORPT` turns it off |
| **Ctrl+R** | | pause between CQs in seconds (1.8; a number above 100 = milliseconds, like N1MM) |
| `FULLABBREV` | | cut numbers T, A, U, E, D, N (DXLog) |
| `PROABBREV` | | cut numbers T and N (097 → TN7) |
| `SEMIABBREV` | | cut numbers: only zeros as T |
| `NOABBREV` | | cut numbers off |
| `WORKDUPE` | `WORKDUPEON` | ESM: a dupe in Run is made as a new QSO |
| `NOWORKDUPE` | `WORKDUPEOFF` | ESM: a QSO B4 is sent to a dupe |

All nine cut number styles from N1MM can be chosen in Settings → CW klíč (CW keyer).

### Program (DXLog)

| Command | Alias | Action |
|---|---|---|
| `BYE` | `EXIT`, `QUIT` | quits the program, asks first |
| `EXITNOW` | `QUITNOW` | quits the program immediately |
| `CLEARLOGNOW` | | deletes the log **without confirmation** |
| `NEW` | | new contest |
| `OPEN` | | open a contest |
| `CLOSE` | | closes the contest (free logging) |
| `COPYLOG` | | backup of the database next to it, with the time in the name (`log-20261128-120000.sqlite`) |
| `RELOAD` | `RELOADNOW` | reloads the contest definitions and opens the contest |
| `REOPEN` | `REOPENNOW` | restores the log from the database and recalculates the score |
| `BCLOG` | | broadcasts the whole log once over UDP broadcast |
| `RESET` | | reconnects the transceiver (CAT) and the CW keyer |
| `DEBUGCAT` | | CAT communication window |
| `AUTORELOAD` | | open the last contest straight away at startup |
| `NOAUTORELOAD` | | show the startup dialog at startup |
| `MSGS` | `MESSAGES`, `AMSGS` | Settings → Function Keys |
| `WKEY` | `WKSETUP` | Settings → CW klíč (CW keyer) |
| `NETCONFIG` | | Settings → Cluster |
| `BEACONS` | | loads a beacon file (N1MM `Beacons.txt`) into the bandmap for the duration given in the file header |

Beacon file format (N1MM): lines with `#` are comments, the first following line is the
number of hours, then `callsign;frequency kHz;locator;comment`, e.g.
`OZ7IGY/B;144471,1;JO55WM;`.

## Callsign vs. command

The keyword must make up the **entire** content of the field (only `OPON` and `LOGIN` take an argument).
`CW1A`, `NET1X` or `OPONX` are therefore normal callsigns and `WIPELOG NOW` is not executed.
A purely numeric entry cannot be a callsign, so it is taken as a frequency.

## Unsupported commands

These N1MM and DXLog commands control functions that MacContestLogger does not have (or that
make no sense on macOS):

| Command | Why |
|---|---|
| `LIGHT` (N1MM) | the application does not know the optical band |
| `ALIGN` | MMVARI tuning (digital decoder) |
| `QQSL` | Intelligent Quick QSL |
| `CTSPACE` / `NOCTSPACE`, `SOUND` / `NOSOUND` | settings of DXLog's internal keyer (the Winkeyer keeps its own) |
| `CWAUTO` / `NOCWAUTO` | automatic transmission while typing the callsign |
| `SYNCCW` / `SYNCSPEED` | SO2R / SO2V (one VFO for logging) |
| `MULT`, `RUN`, `RUN1`, `RUN2`, `PASSFREQ`, `REMOTE`, `ILOCK…` | multi-op station type, passing, interlock |
| `POSTCONTEST` | post-contest editing mode |
| `MORSERUNNER`, `SUPERSIM` | simulators |
| `SENDLOG`, `COPYLOGCLEAR` | sending to the SCP database; unclear function even in DXLog |
| `DEFINEKEYS`, `FOCUS` / `NOFOCUS` | key remapping, taking over focus |
| `CTYFILES` | the country file is taken from `~/dxcc-json`, it is not in Settings |

## RIT

| Command | Action |
|---|---|
| `RIT 120`, `RIT -50` | RIT to an offset in Hz |
| `NORIT`, `RITOFF`, `RITCLEAR`, `CLEARRIT` | RIT off |

## Scripts

| Command | Action |
|---|---|
| `SCRIPT name` | executes the lines of the file `scripts/name.txt` as text commands — see [scripting.md](scripting.md) |
