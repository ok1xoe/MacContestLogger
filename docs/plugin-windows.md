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
| `permissions` | What the plugin may do — see [Permissions](#permissions). A permission this version does not know (`cat`, `transmit`, …) → **the plugin is not started** and the messages window says it needs a permission this version does not support. |
| `events` | The events the plugin receives (the directory names of [the event table](scripting.md#plugins)). Nothing else is sent. |
| `run` | The executable, relative to the plugin directory (default `run`; no `..`). It may be a symbolic link, also to a program elsewhere — the plugin directory is yours, the app runs what you put there. |
| `windows` | 1–8 windows: `id` (letters, digits, `-`, `_`, `.`), `title` (default: `name`), `size` `[width, height]` for the first opening (later the window keeps the size you give it), `kind` (`declarative` default, or `web` with `page`: an `.html` file in the plugin directory — see [Web windows](#web-windows)). May be left out when the plugin has `actions`. |
| `webHosts` | Host names a web window may load from over `https` (also their subdomains); default none. |
| `process` | `false`: no executable at all — only web windows, which talk to the app themselves (no `actions` then). |
| `webInlineScripts` | `true`: web pages may run inline scripts (never when the manifest asks for `transmit` or `cat`). |
| `actions` | Up to 32 key actions: `{"id","title"}`. The operator binds keys to them in Settings → Keys; the plugin gets a `key` message. A plugin with actions and no windows starts at the first key press and runs until the quit. |

Problems in `plugin.json` (bad JSON, a missing field, an unknown event) appear in the messages window as
`[<directory>] …`, each once.

## Permissions

| Permission | Grants | |
|---|---|---|
| `read` | the read requests (log, contest, rig state, spots) | always |
| `ui` | `set` for the plugin's windows | always |
| `entry` | `entry.*`: the active entry window's call and exchange, wipe, logging, the status line | operator's grant |
| `rig` | `rig.*`: QSY, mode, split, RIT, VFO swap, the active radio — **never transmitting**, always through the entry window as the operator's own actions | operator's grant |
| `spots` | `spots.add`, `spots.remove`, `spots.mark`, `spots.blacklist` (local only) | operator's grant |
| `spots.send` | `spots.send`: a spot to the **public** DX cluster network (needs `spots` too) | operator's grant, off by default |
| `app.command` | `app.command`: call-field text commands — never one that can transmit, reach a network, run scripts or destroy data | operator's grant |
| `cat` | `cat.send`: raw `rigctld` commands to the active rig — reading and setting frequency, mode, VFO, split, RIT/XIT, levels, antenna; **never** keying | operator's grant, off by default |
| `transmit` | `tx.*`: CW, F-key and voice messages and the PTT — **the station transmits** | operator's grant, off by default, with a warning |

A plugin that asks for a permission needing a grant waits until the operator decides: its window shows a banner with
**Rozhodnout o oprávněních…** (and the messages window says so once). The sheet opens only on that click or from
Settings → **Pluginy** — never by itself, so it never takes the keyboard in the middle of a QSO. It lists the
undecided permissions (checked, except `spots.send`, `cat` and `transmit`): **Povolit vybrané** grants the checked
ones, **Odmítnout vše** none — the plugin then starts with `read` and `ui` and gets the `permission` error for the
rest. Settings → Pluginy grants or revokes at any time; a revoke applies to every request answered from then on, also
one already queued. The `hello` message lists the permissions granted now.

- Decisions are kept per permission in `plugin-settings.json` in the data directory, keyed by the plugin's directory
  **and** its manifest `name`: another plugin put into the same directory inherits nothing, and a plugin whose
  manifest asks for a new permission waits again — the sheet asks only for the new one.
- The consent is the operator's protection against a plugin acting beyond what they expect, not a security boundary:
  a plugin is a program running as you and could edit `plugin-settings.json` itself. The app notices a change of
  that file while it runs, says so in the messages window and writes its own decisions back.

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
| `canvas` | `width`, `height` (points, at most 4 000), `shapes`, `id` (a click sends `click` with `value` `{"x","y"}` in canvas coordinates), `label` (read by VoiceOver) |

Canvas shapes (origin top left, y down; at most 5 000 per canvas, 2 000 points per path; `style` as above, `fill`,
`lineWidth` 0.5–20): `{"shape":"line","x1","y1","x2","y2"}`, `{"shape":"rect","x","y","w","h"}`,
`{"shape":"circle","cx","cy","r"}`, `{"shape":"path","points":[[x,y],…],"closed"}`,
`{"shape":"text","x","y","text","size"}` (size 6–72). The drawing scales with the window's font stepper.

**Docking:** the button left of the font stepper docks a plugin window into the main window, under the entry panel
(the plugin keeps running); the panel has buttons back into a window of its own and to close it. Docked windows are
kept in `plugin-settings.json` and come back at start.

Limits: 2 000 rows per table or items per list (the rest is cut with a notice), 2 000 elements per content, the 1 MiB
line limit for the whole `set`. An element type this version does not know is left out with a notice, the rest is
shown.

## Requests

### Reading (`read`)

| Method | Params | Result |
|---|---|---|
| `log.query` | `contest` (`active` default, `none` = free logging, `all`), `band` (`20m`), `mode` (`CW`), `call` (prefix), `callContains`, `since`, `until` (ISO 8601 UTC), `limit` (default 500, max 10 000), `offset`, `order` (`asc` default, `desc`) | `{"qsos":[…],"total":n}` — each QSO in the `qso-logged` form; `total` counts every match |
| `log.count` | as `log.query` | `{"count":n}` |
| `log.get` | `uuid` | the QSO or `null` |
| `contest.active` | — | `{"id","name"}` or `null` |
| `contest.score` | — | `{"contestId","qsos","dupes","qsoPoints","mults","bonusPoints","qtcPoints","total","bands":[{"band","qsos","dupes","points","mults"}],"modes":[…]}` — the Score window's breakdown; `null` without a contest |
| `rig.state` | — | `{"radio","freqHz","band","mode","catConnected"}` of the active entry window, or `null` |
| `spots.list` | `band` | `{"spots":[{"dxCall","freqHz","band","spotter","comment"}]}` newest first, at most 2 000 |

| `contest.multipliers` | — | `{"contestId","multipliers":[{"id","label","worked","keys":[…],"needed":null}]}` — the worked multipliers per binding (a replay of the log, as the score); `needed` is not computed yet; `null` without a contest |

The database is read off the app's main thread.

### Acting

Each needs its permission ([Permissions](#permissions)); the answer is `{"ok":true}` or the error `refused` with the
reason (no active entry window, the call field holds a command, not connected, …).

| Method | Params | Does |
|---|---|---|
| `entry.getCall` | — | `{"call","exchange":{id: value},"freqHz","mode","radio"}` of the active entry window |
| `entry.setCall` | `call` | types the call (as typing does): letters, digits and `/` only; a text Enter would run as a command (`ESM`, `CW`, a frequency…) is refused |
| `entry.setExchange` | `fields`: `{id: value}` | fills exchange fields; answers `unknown` with the ids the contest does not have |
| `entry.wipe` | — | wipes the entry (as Esc) |
| `entry.log` | — | logs the QSO as Enter without ESM — never transmits; refused when the call field holds a command |
| `entry.status` | `text` | shows a text in the status line |
| `rig.qsy` | `freqHz` (inside an amateur band), `mode` (optional) | QSY of the active entry window (its rig follows through CAT); the focus stays where it is |
| `rig.setMode` | `mode` | mode of the active entry window |
| `rig.split` | `txFreqHz`, or `off: true` | split as the `SPLIT` command |
| `rig.rit` | `offsetHz` (±99 999) | RIT as the `RIT` command |
| `rig.swap` | — | swaps the VFOs |
| `rig.focusedRadio` | `radio` (0 or 1) | makes that radio / VFO the active one |
| `spots.add` | `call`, `freqHz`, `comment` | a local spot of your station (band map, available multipliers) |
| `spots.remove` | `call`, `blacklist` | removes every spot of the call (optionally onto the blacklist); `{"removed": bool}` |
| `spots.mark` | `freqHz` | a `MARK` spot |
| `spots.blacklist` | `call` | puts the call on the blacklist |
| `spots.send` | `call`, `freqHz`, `comment` | sends a spot to the DX cluster (as Spot It with a comment) — public. The call must be a callsign, the comment plain text (no control characters, at most 60) |
| `app.command` | `text` | runs a call-field text command. Allowed only: a QSY or frequency, the other VFO, `SPLIT`/`NOSPLIT`, `RIT`, `SWAP`, a mode, `NOESM`, `NORPT`, `WORKDUPE`/`NOWORKDUPE`, `VERSION`, `RESCORE`, `REOPEN`, `DEBUGCAT`; everything else (anything that can transmit, reach a network, run scripts, change the configuration, the operator, the contest or the log, or open a dialog) is refused |

Error codes: `unknown_method`, `permission`, `invalid_params`, `refused`, `unavailable` (no logbook open), `busy`
(more than 4 requests at once), `failed`.

### Rig and transmitting (`cat`, `transmit`)

| Method | Params | Does |
|---|---|---|
| `cat.send` | `command` | sends one `rigctld` command to the active rig in the extended form; `{"lines":[…],"code":n}` (`code` 0 = OK). An exact grammar — the command and the number and form of its arguments: reading `f m v s i x j z t y`, `l <level>`, `\get_freq|mode|vfo|split_vfo|split_freq|split_mode|rit|xit|ptt|ant`, `\get_level <level>`; setting `F <Hz>`/`I <Hz>` (inside an amateur band; refused with a transverter configured), `M`/`X <mode> <passband>`, `V <vfo>`, `S <0/1> <vfo>`, `J`/`Z <Hz ±99999>`, `L <AF/RF/SQL/NR 0–1, KEYSPD 10–60, CWPITCH 300–1000>` (never `RFPOWER`), `Y <antenna> <option>` (not while transmitting). Everything else is refused: keying, raw bytes, tuner, power, the daemon's own commands, dumps, `;` `|` `\` separators, extra or missing words, leading, trailing or doubled spaces, control characters. At most **10 a second** per plugin and 15 for all plugins (`rate_limited`). A reply over 16 KiB, or any read error or timeout, closes the rig connection (a reply is never left half-read). Plugin CAT commands still queued when the operator stops a transmission or a plugin PTT is released are dropped, so the safety `T 0` goes out at once. Each command and its reply appear in the CAT log window. |
| `tx.sendCw` | `text` (macros of the F-key messages allowed) | sends CW through the app's keyer (CW mode only) |
| `tx.fkey` | `key` 1–12, `opposite` | presses that F-key in the active entry window (CW, voice or digital by the mode, ESM rules) |
| `tx.voice` | `key` 1–12 | the voice message of that F-key (phone modes only) |
| `tx.stop` | — | Esc: stops every transmission (also a plugin's PTT); `{"stopped": bool}` |
| `tx.ptt` | `on` | keys or releases the active rig's PTT |

Everything goes through exactly the paths of the F-keys, Esc and the footswitch PTT: the pileup simulator's lock
refuses, Esc stops it (and everything else that transmits), the quit and a rig's disconnect release it, and a plugin
that stops, crashes or loses its `transmit` grant never leaves the PTT keyed or its message on the air. A refused
`T 1` is followed by `T 0` at once and reported (`refused`); without a connected rig the PTT is refused. A plugin's PTT
is released after **30 s** at the latest (Settings → Pluginy, 5–300 s), counted from the moment the rig was keyed:
while one plugin holds the PTT no other plugin can key it, keying again does not extend the limit, and after that
forced release the plugin may not key for 10 s. Only the plugin holding the PTT releases it (another plugin's `off`
changes nothing, the operator's own transmissions are never cut by a plugin). While a plugin transmits, the main
window shows **Plugin X vysílá** with a stop button.

- **Esc and Stop stick:** when the operator presses Esc (or the indicator's Stop) while a plugin transmits, plugin
  transmissions stay blocked — the main window shows *Vysílání pluginů zastaveno* with **Povolit** — until the
  operator allows them again.
- **On-air budget** (conservative defaults, Settings → Pluginy): a message (CW, voice, F-key) a plugin started is cut
  after **60 s** (5–300 s); all plugins together may be on the air at most **50 %** of any 5 minutes (10–100 %); a
  plugin may have at most two CW texts on the air in one transmission (`busy`), each at most 200 characters.

### Keys

```json
{"type":"key","action":"last-call","phase":"press"}
```
Settings → Keys lists every plugin action: **Změnit** captures a key, **Žádná** removes it, and *Ponechat i původní
funkci klávesy* lets the key keep its own entry-window function too (otherwise the plugin's key replaces it; the
list shows a conflict with the app's own shortcut). Esc, Enter, Tab, the space bar and plain F1–F12 are never a
plugin's — the stop and transmit keys always stay the app's; a key is never bound to two plugin actions. Keys act
while an entry field has the focus. A plugin that keeps crashing is restarted by its keys at most 3 times a minute;
after that only Restart starts it.

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
`toggle`, `progress`, `tabs`, `tab` and `canvas` (with `line`, `rect`, `circle`, `path`, `label`) build the elements;
`@plugin.on_key("action")` handles a key action. The example
[`band-activity`](plugins/examples/band-activity/) uses `entry`, `rig`, a canvas and a key action.

## Web windows

A window with `"kind": "web"` shows the plugin's own HTML page (`page`, inside the plugin directory) in a web view.
The page talks to the app through `window.mcl`:

```js
const score = await window.mcl.request("contest.score");   // a promise; rejected with {code, message}
window.mcl.on("qso-logged", (qso) => { … });                // the plugin's subscribed events
```

- The same methods, permissions, limits and transmit rules as a process's requests; a plugin may have a process and
  web windows, or (`"process": false`) web windows only — see the example
  [`web-score`](plugins/examples/web-score/).
- The app serves the plugin's files itself (`mcl-plugin://local/…`, only from the plugin directory) with a strict
  **Content-Security-Policy**: scripts only from the plugin's own files (put them in `.js` files — inline scripts
  are blocked unless the manifest says `"webInlineScripts": true`, and never for a plugin whose manifest asks for
  `transmit` or `cat`), no plugins, `connect`/`img`/`frame` only to the plugin itself and `https` to the manifest's
  `webHosts`.
- The page never navigates away from the plugin's files (no remote page, no `data:`, `blob:`, `javascript:` or
  `file:` navigation, no popups or new windows); subframes and subresources may load `https` from `webHosts`.
  Only the main frame of a plugin page can send requests to the app. No cookies or storage are kept between runs.
- **Escape untrusted data.** QSO fields, spots and cluster comments come from other people: put them into the page
  with `textContent` (or escape them), never with `innerHTML`.
- The window's font stepper zooms the page.

## The Node.js helper

[`docs/plugins/mcl.js`](plugins/mcl.js) is the same helper for Node.js (one file, no packages):
`new mcl.Plugin()`, `onStart`, `on(event)`, `onClick`, `onChange`, `onKey`, `request` (a promise), `setWindow`,
`log`, `run`, and the same element and canvas builders as `mcl.py`.

## Roadmap

Later versions may add `needed` counts to `contest.multipliers`, more element types and more requests; new
permissions are added the same way — a plugin asking for one this version does not know is not started, and the same
`plugin.json` starts once a version that knows it is installed and the operator allows it.
