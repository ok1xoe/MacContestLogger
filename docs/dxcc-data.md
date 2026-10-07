# DXCC data and Club Log

The logger derives the DXCC entity, continent, CQ zone and country name of every callsign locally. The
result drives the country and zone multipliers, the points of many contests (`dxccIn`, own/other
continent), the `DXCC`, `COUNTRY` and `CONT` fields of the log and its exports, the map, the Info lines
and the spot analysis.

## Sources

| Source | Where | Used when |
|--------|-------|-----------|
| Club Log `cty.xml` | `<data folder>/clublog/` (downloaded by the app) | the switch below is on **and** a copy has been downloaded |
| `cty.dat` (AD1C) | `~/dxcc-json/cty.dat` | otherwise, when the file exists |
| `dxcc.json` | `~/dxcc-json/dxcc.json` | otherwise |

The data folder is `~/Library/Application Support/MacContestLogger` (or the folder in `MCL_DATA_DIR`).
Without any of them the contest engine is not available (see [Getting started](zaciname.md)).

## Club Log `cty.xml`

Club Log publishes its country file with call-specific exceptions (DXpeditions, special stations),
invalid operations and zone exceptions, all with validity dates. MacContestLogger can use it as the
DXCC source:

- **Settings → Score Reporting → DXCC z Club Logu (cty.xml)**: the switch *Používat DXCC z Club Logu*
  (on by default) and the button *Aktualizovat DXCC z Club Logu*. The same update is in the menu
  *Databáze → Aktualizovat DXCC z Club Logu*.
- The download needs the Club Log **API key** entered in the Club Log Live Stream group above
  (`https://cdn.clublog.org/cty.php?api=<key>`). Without a key nothing is downloaded.
- **At start-up** the file is downloaded in the background when the switch is on, a key is set and the
  last download *or attempt* is more than 24 hours old. **On demand** it is downloaded when the last
  successful download is more than 24 hours old; otherwise the status line says when the next one is
  possible.
- Club Log's traffic rules are kept: at most one download of `cty.xml` per day, every lookup is local,
  nothing is ever sent to Club Log per QSO.
- Each download is recorded in `clublog.log` in the data folder (the request with `api=***`, the HTTP
  status, the size and the result); the API key is never written there.
- The folder `clublog/` holds the raw file (`cty.xml`), its parsed compact form (`cty.json`, loaded at
  start-up) and the time of the last download and attempt (`cty-state.json`).
- A failed download (offline, HTTP error, refused key, damaged file) keeps the last copy; with no copy the
  local data stay the source. The result is shown in the status line, in Settings and in the Info
  window's messages.
- After a successful download, and when the switch changes, the contest data are reloaded and the open
  contest is rescored with the new source.

### Lookup order

1. **Exception** — the whole callsign, as logged, with an exception valid at the QSO date.
2. **Invalid operation** — the callsign is listed as invalid at that date: no DXCC entity.
3. `/MM` (maritime mobile) and `/AM` (aeronautical mobile) count for no entity; `/P`, `/M`, `/QRP`, `/A`,
   `/R`, `/LH`, `/B`, `/J` are ignored.
4. **Prefix** — the longest prefix valid at the QSO date, taken from the shorter part of a portable
   call (`DL/OK1XOE`, `OK1XOE/DL` → `DL`); a single-digit suffix moves the call area
   (`UA1ABC/9` → `UA9`).
5. **Zone exception** — a callsign with its own CQ zone at that date overrides the zone.

The DXCC (ADIF) number of the result is Club Log's. `cty.xml` has no ITU zones and spells country names
in capitals, so the name and the ITU zones come from the local data (`~/dxcc-json`) when they know the
same DXCC number.

### Which date is used

- Every QSO is evaluated at **its own time**: filling in its country when it is logged or imported,
  *Přepočítat DXCC v deníku…*, the contest engine's points and multipliers when logging, when an
  open contest is replayed or rescored, the move-multipliers check, and `mcl-scorecheck` (the date and
  time of each Cabrillo `QSO:` line). Rescoring an old log therefore gives the same result as when it
  was logged.
- Live calls that are not QSOs yet — spots, the band map, the Info lines, the map, the entry window
  preview — use the **current date**.
