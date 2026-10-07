# Plugin windows

A **window plugin** is a program that runs while one of its windows is open and shows its own content in
MacContestLogger windows: a table of QSOs by band, a goal tracker, a list of needed multipliers, anything you can
compute from the log. It talks to the app over its standard input and output, one JSON message per line, and it
can ask the app read-only questions about the log, the contest, the rig and the spots.

The event plugins of [Scripts and plugins](scripting.md) (`plugins/<event>/`) keep working unchanged; window plugins
live next to them.

This page describes **protocol 1**. Later versions add more (see [Roadmap](#roadmap)); a
plugin written for protocol 1 keeps working.

## Quick start

1. Copy [`docs/plugins/examples/qso-by-band/`](plugins/examples/qso-by-band/) to
   `~/Library/Application Support/MacContestLogger/plugins/qso-by-band/` and put
   [`docs/plugins/mcl.py`](plugins/mcl.py) next to its `run.py`.
2. Make `run.py` executable (`chmod +x run.py`).
3. Choose **Window → Custom → QSOs by band**.

The window opens, the plugin starts, and its table follows every QSO you log.

## Layout

```
plugins/
  qso-by-band/            ← the plugin id (letters, digits, -, _ and .)
    plugin.json           ← the manifest
    run.py                ← the executable (any language; a script needs #! and chmod +x)
    mcl.py                ← the Python helper (optional)
  qso-logged/             ← an event plugin directory, see scripting.md
    append.sh
```

- A directory **with** `plugin.json` is a window plugin. A directory without it is ignored by the window plugins.
- The 16 event names (`qso-logged`, `contest-opened`, …) are reserved for the event plugins: a `plugin.json` in such a
  directory is reported in the messages window and ignored.
- The plugins directory is read when the app starts and every time the Window menu opens, so a new plugin appears
  in **Window → Custom** without a restart.

## The manifest

```json
{
  "protocol": 1,
  "name": "QSOs by band",
  "version": "1.0",
  "permissions": ["read", "ui"],
  "events": ["qso-logged", "contest-opened"],
  "run": "run.py",
  "windows": [{ "id": "main", "title": "QSOs by band", "size": [420, 360] }]
}
```

| Field | Meaning |
|---|---|
| `protocol` | Required, `1`. Another number is refused with a message. |
| `name` | Shown name (default: the directory name). |
| `version` | Free text. |
| `permissions` | What the plugin may do. Protocol 1 knows `read` (the requests) and `ui` (its windows). **Any other permission → the plugin is not started** and the messages window says it needs a permission this version does not support. |
| `events` | The events the plugin receives (the directory names of [the event table](scripting.md#plugins)). Nothing else is sent. |
| `run` | The executable, relative to the plugin directory (default `run`; no `..`). It may be a symbolic link, also to a program elsewhere — the plugin directory is yours, the app runs what you put there. |
| `windows` | 1–8 windows: `id` (letters, digits, `-`, `_`, `.`), `title` (default: `name`), `size` `[width, height]` for the first opening (later the window keeps the size you give it). |

Problems in `plugin.json` (bad JSON, a missing field, an unknown event) appear in the messages window as
`[<directory>] …`, each once.

## Lifecycle

- **Start:** when one of the plugin's windows opens — from **Window → Custom**, or at start-up when the window was
  open at the last quit (plugin windows are kept in `openWindows` as `plugin:<id>/<window>` like the other windows).
  Each plugin runs once, however many of its windows are open. The working directory is the plugin directory; the
  environment has `MCL_PLUGIN_PROTOCOL=1`, `MCL_PLUGIN_NAME=<id>` and `PYTHONUNBUFFERED=1`.
- **Hello:** the app sends `hello` first. The plugin must answer within **10 s** with any message (the helper sends
  `{"type":"ready"}`), or it is stopped as hung.
- **Contest switch:** the plugin keeps running; subscribe to `contest-closed` and `contest-opened` to hear of it.
- **Stop:** when you close its last window, the app closes the plugin's stdin, sends `SIGTERM` and, 1 s later,
  `SIGKILL`. Read until the end of stdin and exit.
- **Quit:** subscribers get `app-quitting`, then the input ends; at the end of the quit a plugin still running gets
  `SIGTERM` and, 1 s later, `SIGKILL`. A plugin never delays the quit by more than that.
- **Crash:** the window keeps its last content under a banner *Plugin skončil (kód N)* with **Restart**.
- **Hung:** no answer to `hello` in 10 s, or the plugin does not read its input (more than 1 MiB waits unread): it is
  stopped, the banner says so, **Restart** starts it again.
- **Closed input:** a plugin may close its own stdin; the app then stops sending it events and window interactions
  (it is not treated as hung) and keeps showing what it sets.
- **Fast output:** the app reads at its own pace. `set` messages of one window are coalesced (the latest wins);
  other messages queue, and while 32 wait the app stops reading, so a plugin that writes faster than the app
  handles blocks on its own output.
- **Off:** with `MCL_INERT_HARDWARE` or `MCL_INERT_NETWORK` set, no plugin starts (the window says so).

## Messages

Every message is one line of UTF-8 JSON ending with `\n`, at most **1 MiB**. A line that is longer, not JSON, or not a
known message is ignored and reported in the messages window (each kind of problem once per run). Unknown fields are
ignored, so new fields can be added later without breaking anyone.

### From the app

```json
{"type":"hello","protocol":1,"app":{"version":"0.9.0"},"contest":{"id":"cq-ww-cw-2026","name":"CQ WW DX CW"},
 "band":"20m","mode":"CW","windows":["main"],"permissions":["read","ui"]}
```
`contest` is `null` without an active contest; `band` and `mode` are those of the active entry window (`null` when
unknown).

```json
{"type":"event","event":"qso-logged","data":{"time":"2026-10-07T12:00:00Z","call":"OK1ABC","band":"20m", …}}
```
`data` is exactly the JSON an event plugin gets on stdin for that event (see [the event table](scripting.md#plugins)),
with the same throttling (`frequency-changed` after 1 s, `score-changed` coalesced).

```json
{"type":"ui","window":"main","action":"click","target":"bands","row":2,"rowId":"40m"}
{"type":"ui","window":"main","action":"double-click","target":"bands","row":2,"rowId":"40m"}
{"type":"ui","window":"main","action":"click","target":"refresh"}
{"type":"ui","window":"main","action":"change","target":"by-mode","value":false}
{"type":"ui","window":"main","action":"select","target":"pages","value":"stats"}
```
`row` is the 0-based index, `rowId` the row's (or list item's) `id` or `null`.

```json
{"type":"response","id":7,"result":{"count":1234}}
{"type":"response","id":8,"error":{"code":"unknown_method","message":"unknown method cat.send"}}
```

### From the plugin

```json
{"type":"ready"}
{"type":"set","window":"main","content":{"elements":[ … ]}}
{"type":"request","id":7,"method":"log.count","params":{"band":"20m"}}
{"type":"log","text":"something worth seeing"}
```
- `set` replaces the whole content of one of the plugin's windows and needs the `ui` permission (without it the
  message is ignored and reported). A window renders at most **5 times a second**: a burst of `set`s shows the latest
  one.
- `request` — `id` is a number or a text, echoed in the response; requests may overlap, answers may come in any order.
  At most **4** requests of a plugin are answered at a time; a further one gets the `busy` error at once (send it
  again after an answer came).
- `log` puts `[<name>] text` into the messages window (cut at 500 characters). **Stderr** lines go there too. At most
  500 such lines per run are shown, then one notice.

## Window content

`content.elements` is a vertical list of elements. The app draws them in its own fonts and colours; you choose a
**style** (a meaning), never a colour: `normal`, `title`, `muted`, `warn`, `new`, `dupe`, `mult`. All text follows
the window's font stepper (top right, as in every window), and every element is read by VoiceOver.

| Element | Fields |
|---|---|
| `text` | `text`, `style` |
| `table` | `columns` (texts, or `{"title","align":"right"}`), `rows` (lists of cells, or `{"id","cells","style"}`), `id` (with an id, a click or double click on a row sends a `ui` event) — a cell is a text, a number or `{"text","style"}`; a row's `style` applies to its cells without their own |
| `list` | `items` (texts or `{"id","text","style"}`), `id` (clicks as for a table) |
| `button` | `id`, `label`, `enabled` (default `true`) → `click` |
| `toggle` | `id`, `label`, `value` → `change` with the new `value` (shown at once) |
| `progress` | `value`, `max`, `label` |
| `tabs` | `id`, `tabs`: `[{"id","title","elements":[…]}]` → `select`; tabs nest at most 3 deep |

Limits: 2 000 rows per table or items per list (the rest is cut with a notice), 2 000 elements per content, the 1 MiB
line limit for the whole `set`. An element type this version does not know is left out with a notice, the rest is
shown.

## Requests (read only)

| Method | Params | Result |
|---|---|---|
| `log.query` | `contest` (`active` default, `none` = free logging, `all`), `band` (`20m`), `mode` (`CW`), `call` (prefix), `callContains`, `since`, `until` (ISO 8601 UTC), `limit` (default 500, max 10 000), `offset`, `order` (`asc` default, `desc`) | `{"qsos":[…],"total":n}` — each QSO in the `qso-logged` form; `total` counts every match |
| `log.count` | as `log.query` | `{"count":n}` |
| `log.get` | `uuid` | the QSO or `null` |
| `contest.active` | — | `{"id","name"}` or `null` |
| `contest.score` | — | `{"contestId","qsos","dupes","qsoPoints","mults","bonusPoints","qtcPoints","total","bands":[{"band","qsos","dupes","points","mults"}],"modes":[…]}` — the Score window's breakdown; `null` without a contest |
| `rig.state` | — | `{"radio","freqHz","band","mode","catConnected"}` of the active entry window, or `null` |
| `spots.list` | `band` | `{"spots":[{"dxCall","freqHz","band","spotter","comment"}]}` newest first, at most 2 000 |

`contest.multipliers` answers `not_implemented` in protocol 1. Error codes: `unknown_method`, `permission`,
`invalid_params`, `unavailable` (no logbook open), `busy` (more than 4 requests at once), `not_implemented`, `failed`. The database is read off the app's main
thread; a request never changes anything.

## The Python helper

[`docs/plugins/mcl.py`](plugins/mcl.py) is one file, standard library only. Copy it next to your plugin:

```python
#!/usr/bin/env python3
import mcl

plugin = mcl.Plugin()

def show(_=None):
    count = plugin.request("log.count")["count"]
    plugin.set_window("main", [mcl.text(f"{count} QSOs", style="title"), mcl.button("refresh", "Refresh")])

plugin.on_start(show)
plugin.on("qso-logged")(show)
plugin.on_click("refresh")(show)
plugin.run()
```

Handlers run one at a time in the order the app sent the messages; `request` blocks until the answer comes (the
answers are read on a background thread; `_timeout=` sets the wait in seconds, 30 by default). `mcl.text`, `table`, `row`, `cell`, `column`, `list_`, `item`, `button`,
`toggle`, `progress`, `tabs` and `tab` build the elements.

## Roadmap

- **Stage 2:** `entry` (fill the call and exchange), `rig` (tune, change band and mode), `spots` (add a spot) and
  `app.command` (run a callsign-field text command); scripts bound to keys; a `canvas` element; docking a plugin
  window into the main window.
- **Stage 3:** `cat` and `transmit` — raw rig commands and keying — behind an explicit grant of each permission by the
  operator, and a web-view window.

A plugin asking for one of these permissions today is not started; the same `plugin.json` starts once a version that
grants it is installed and the operator allows it.
