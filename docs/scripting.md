# Scripts and plugins

Equivalent of DXLog **Scripts** and N1MM external applications.

## Macro scripts

A text file `~/Library/Application Support/MacContestLogger/scripts/<name>.txt`,
each line one **callsign-field text command** (see [text-commands.md](text-commands.md)),
`#` = comment. To run it: type `SCRIPT name` into the callsign field and press Enter.

```
# scripts/run20.txt — přechod na Run na 20 m CW
CW
14025
NOSPLIT
RIT 0
RUNSP
```

The commands are executed in order as if the operator were typing them; a nested
`SCRIPT` is not run, to avoid loops.

## Plugins

Plugins that show their own windows and read the log while they run are described in
[Plugin windows](plugin-windows.md); the event plugins below are unaffected by them.

An executable file (a script with `#!`, a program) in a subdirectory according to
the event:

| Directory `.../MacContestLogger/plugins/` | When it runs | JSON on stdin |
|---|---|---|
| `qso-logged/` | after a QSO is logged (not an import) | time, callsign, band, frequency, mode, reports, exchanges, operator, contest, uuid |
| `contest-opened/` | after a contest is opened | contest id and name, callsign |
| `spot-received/` | on every spot from the DX cluster | callsign, frequency, spotter, comment |
| `qso-edited/` | an operator edited a QSO of this station (not an import, not a cluster-sync arrival, not a simulated QSO) | `old` and `new`, each with the fields of `qso-logged` |
| `qso-deleted/` | an operator deleted a QSO of this station (same exclusions) | the fields of `qso-logged` |
| `contest-closed/` | the operator switched to another contest or chose Contest, None | `contestId`, `name` |
| `app-started/` | once the start-up is complete | `version`, `contestId`, `name` (the last two `null` without a contest) |
| `app-quitting/` | first step of the quit, before the shutdown | `version`, `contestId`, `name` |
| `band-changed/` | the band of the active entry window changed | `radio`, `oldBand`, `newBand` (ADIF, e.g. `20m`) |
| `mode-changed/` | the mode of the active entry window changed | `radio`, `oldMode`, `newMode` |
| `frequency-changed/` | the frequency settled on a new value (see below) | `radio`, `oldFreqHz`, `newFreqHz` |
| `self-spotted/` | someone spotted your callsign ("Byl jsi spotnut", RBN) | `spotter`, `freqHz`, `source` (`skimmer` or `human`), `snr`, `wpm` (`null` when unknown) |
| `new-multiplier/` | a QSO logged here made at least one multiplier new (active contest, not a dupe) | `contestId`, `call`, `band`, `mode`, `multipliers` (a list of `{set, key}`) |
| `score-changed/` | the score of the active contest changed (see below) | `contestId`, `qsos`, `qsoPoints`, `mults`, `bonusPoints`, `qtcPoints`, `total` |
| `score-reported/` | after a post to the scoreboard | `host`, `status` (HTTP status, 0 = no answer), `accepted`, `message` |
| `clublog-upload/` | after each Club Log upload attempt | `outcome` (`ok`, `rejected`, `retry`), `call`, `status` (the status text) |

- The environment variable `MCL_EVENT` carries the event name in the directory form (`qso-logged`,
  `frequency-changed`, ...).
- Whatever the plugin prints to stdout (at most 50 lines) appears in the messages
  window under the plugin name; a non-zero exit code is reported.
- A plugin that runs longer than 10 s is terminated. Several plugins for one event
  run one after another in alphabetical order.

### Throttling and scope

- `radio` is the 0-based index of the radio / VFO (the second entry window in SO2V and SO2R is `1`). The band,
  mode and frequency events come from the active entry window, with or without a rig; the first value seen only
  sets the baseline. Typing a frequency by hand can pass through other bands on the way.
- `band-changed` and `mode-changed` run at once on a change. `frequency-changed` runs only after the frequency
  has stayed put for 1 s, so tuning the VFO starts one plugin run, not one per poll; two runs are always at least
  1 s apart, and going back to the last reported frequency within that second runs nothing.
- `score-changed` is coalesced: it runs once, 3 s after the last change, with the latest score, so a rescore or a
  burst of QSOs gives one run; an unchanged score is not repeated. It needs an active contest.
- `qso-edited`, `qso-deleted`, `new-multiplier`, `score-changed` and the band, mode and frequency events never
  run for the pileup simulator.
- `app-quitting` starts the quit's plugin deadline (10 s): later plugins are not started and a running one is
  terminated at the deadline, so quitting is never delayed beyond it.
- No payload carries a local path, a password, an API key or the scoreboard URL (only its host).

Example — every QSO into your own file:

```sh
#!/bin/sh
# plugins/qso-logged/append.sh
python3 -c 'import json,sys; q=json.load(sys.stdin); print(q["time"], q["call"], q["band"])' >> ~/qso.txt
echo "zapsáno"
```
