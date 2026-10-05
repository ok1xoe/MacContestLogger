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

An executable file (a script with `#!`, a program) in a subdirectory according to
the event:

| Directory `.../MacContestLogger/plugins/` | When it runs | JSON on stdin |
|---|---|---|
| `qso-logged/` | after a QSO is logged (not an import) | time, callsign, band, frequency, mode, reports, exchanges, operator, contest, uuid |
| `contest-opened/` | after a contest is opened | contest id and name, callsign |
| `spot-received/` | on every spot from the DX cluster | callsign, frequency, spotter, comment |

- The environment variable `MCL_EVENT` carries the event name.
- Whatever the plugin prints to stdout (at most 50 lines) appears in the messages
  window under the plugin name; a non-zero exit code is reported.
- A plugin that runs longer than 10 s is terminated. Several plugins for one event
  run one after another in alphabetical order.

Example — every QSO into your own file:

```sh
#!/bin/sh
# plugins/qso-logged/append.sh
python3 -c 'import json,sys; q=json.load(sys.stdin); print(q["time"], q["call"], q["band"])' >> ~/qso.txt
echo "zapsáno"
```
