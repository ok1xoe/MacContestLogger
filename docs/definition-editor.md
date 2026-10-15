# Contest definition editor

![Definition editor — contest YAML, check and preview](img/definition-editor.png)

Equivalent of the N1MM+ **UDC Editor**
([The UDC Editor](https://n1mmwp.hamdocs.com/appendices/udc-editor/#The_UDC_Editor)).
Contests are declarative YAML in the contest data directory ("Nastavení → Závod →
Nastavení dat závodů…", Settings → Contest → Contest data settings...); the editor
edits them directly in the application.

To open it: **"Nástroje → Editor definic…"** (Tools → Definition editor...)

## The window

| Part | What it does |
|---|---|
| **Contests** (left) | definitions from `<data>/contests/*.yaml`; a click opens the file |
| **"Nový ze šablony…"** (New from template...) | asks for an id (= file name, lowercase letters, digits, `-`, `_`) and inserts a valid template: RST + serial number, 1 point per QSO, DXCC multipliers per band |
| **"Duplikovat…"** (Duplicate...) | a copy of the open definition under a new id — the quickest way to a variant of an existing contest |
| **text** (middle) | the YAML definition, monospaced font |
| **Check** (right) | live while typing: YAML syntax (with line and column), unknown keys, the definition validator, **references to nonexistent multiplier sets**, mismatch of `id` with the file name. ✖ error, ⚠ warning |
| **Preview** | name, bands, modes, duration, exchange fields, multipliers, score formula, dupe, Cabrillo name |
| **"Uložit"** (Save) | writes the file atomically (first to a temporary one, then a move) |
| **"Uložit a přenačíst závody"** (Save and reload contests) | additionally reloads the definitions so the contest can be selected right away in New contest |
| **"Zahodit změny"** (Discard changes) | returns the text to the saved state |

A definition with errors can be saved (work in progress), but the application
skips it when loading — it does not appear in the contest list until you fix the
errors. You can switch to another file only without unsaved changes.

## The definition language in brief

```yaml
schemaVersion: 1
id: my-contest                 # = název souboru
metadata: { name: "Můj závod", organizer: "", officialUrl: "" }
period: { durationHours: 24 }  # bez period = bez konce; sezení: sessions: { start: "1200", minutes: 30 }
bands: [80m, 40m, 20m]
modes: [CW, SSB]
exchange:
  sent:     [ { id: rst, type: RST, source: AUTO_RST }, { id: nr, type: SERIAL, source: AUTO_SERIAL } ]
  received: [ { id: rst, type: RST, required: true },   { id: nr, type: SERIAL, required: true } ]
scoring:
  qsoPoints: { mode: FIRST_MATCH, default: 1 }   # pravidla `rules:` s podmínkami when
  total: "qsoPoints * multTotal"
multipliers:
  - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND }
dupe: { scope: PER_BAND_MODE, dupeWorthZero: true }
cabrillo: { contestName: MY-CONTEST, sentOrder: [rst, nr], receivedOrder: [rst, nr] }
ui: { entryOrder: [call, rst, nr], logColumns: [time, call, band, mode, rst, nr] }
```

- field **type**: `RST RS SERIAL INTEGER TEXT LOCATOR CQ_ZONE ITU_ZONE DXCC PREFIX HQ
  NATIONAL STATE PROVINCE DISTRICT IOTA QTC`.
- **source** of a sent field: `MANUAL AUTO_RST AUTO_SERIAL FROM_STATION DERIVED ROVER_QTH`.
- **scope** of multipliers and dupe: `PER_BAND PER_BAND_MODE PER_MODE ONCE`.
- the multiplier **set** = the id of a set in `<data>/multipliers/` (the list is
  at the bottom of the right panel).

### Further rules (N1MM UDC equivalents)

| Key | What it does | N1MM UDC |
|---|---|---|
| `when: { timeBetween: "2200-0559" }` | a condition that holds for QSOs in this UTC window (both minutes included, it may wrap midnight) | `PointsMultAtTimeGMT` |
| `qsoPoints.factors: [ { when: …, factor: 2 } ]` | the points of a QSO are multiplied by the factor of every entry whose condition holds (time, band, mode, continent, country…) | `PointsMultAtTime…`, `PointsMultByBand/Mode/Continent/Country` |
| `scoring.powerFactor: { HIGH: 1, LOW: 2, QRP: 4 }` | the final score is multiplied by the factor of the power category chosen in the contest setup (`HP`/`LP` work as keys too); a category not listed = ×1 | `PowerMult` |
| a multiplier's `when: { not: { ownDxcc: true } }` | the multiplier counts only for QSOs meeting the condition — e.g. not for my own country, only for some countries (`dxccIn`) or continents | `DoNotCountMeAsMult`, `CountMultOnlyFor`, `DoNotCountMultOnlyFor` |
| `dupe: { none: true }` | no dupe check, a station may be worked any number of times | `DupeType 4` |
| `dupe: { reworkMinutes: 30 }` | the same station (within `scope`) may be worked again 30 minutes after the last QSO that counted | `DupeQSOMinutesAgo` |
| `dupe: { byField: qth }` | the received field is part of the dupe: a mobile or rover in another county / grid is a new station | `DupeSqlString` |
| `period.sessions: { start: "1200", minutes: 60, resetMultipliers: true }` | in every session the multipliers count anew | `ResetMultsEverySession` |
| `numbering: { perBand: true }` | the serial number runs on each band separately; with `multiOpOnly: true` only in a multi-transmitter category (`MULTI-OP` with `UNLIMITED` / `DISTRIBUTED`) | `QsoNumbersByBand 1` / `2` |
| `workable: { continentIs: EU }` | who may be worked (any condition); a QSO outside it is logged with a warning and scores no points and no multipliers | `IsWorkable` |
| received field `prefill: [ { when: { entityIn: [223] }, value: "400" }, { value: "100" } ]` | the space bar leaving the call field puts the value of the first rule whose condition holds for the worked station (a rule without `when` always does) into the field while it is empty; a typed value is never replaced. The ARRL DX (W/VE and DX) definitions use it for the DX station's default power (100 W; 200 W UA/UA2/UA9/UK/UN/UR; 400 W G/GM/GI/GD/GW; 500 W I/IS) | ARRL DX default power |
| sent field `source: DERIVED` with `derive: lastCall2L` / `lastCallSuffix` | the last two letters / the suffix of the previous QSO's call (anything after `/` is ignored) is sent | `Last2L`, `LastCallSuff` |
| `exchange: { freeForm: true, … }` | the entry window has one exchange box instead of a box per field; the words are assigned to the fields by their shape in any order (see below) | Sweepstakes exchange |
| `inState: { sections: [EB, LAX, SCV] }` + condition `inState: true` | a QSO party's in-state stations: my ARRL section (station data) is in the list; a new log says whether you count as in-state or out-of-state | in-state / out-of-state of QSO parties |
| condition `fieldMatches: { field: qth, regex: "^[A-Z]{4}$" }` | the received field matches the regex (e.g. a county code rather than a state) | `IsWorkable`, section tests |
| a value of a `FIXED` set with `attributes: { countsAs: CA }` | another spelling of that multiplier, not a value of its own (a California county counts as CA) | state multipliers of QSO parties |
| `adif: { SAT_NAME: sat, PROP_MODE: "=SAT" }` | extra ADIF fields of the ADIF export: a received field's value or a fixed `=text` | DXSATELLIT ADIF fields |
| `export: { text: "{date:10} {time:4} {call:13} {nr:-4}" }` | the layout of File → Export → Text ve formátu závodu (see [import-export.md](import-export.md)) | `CabrilloString`, generic output |
| received field `split: true` | a value `A/B/C` (a station on a county line) logs one QSO per part; a shorter part takes the first part's leading characters (`ORDES/JEF` = `ORDES` + `ORJEF`) | 7QP county line |
| `period: { startWeekday: SAT, startTime: "1200" }` | the New contest dialog proposes the next such date as the start (unless the saved start is still running) | `StartOfContest` |

**Free-form exchange** (`freeForm: true`, ARRL Sweepstakes): type the exchange into the one box as it is heard, e.g.
`123 A 72 OH`, `A 123 OH 72` or `123A 72OH`. Each word goes to the first field it fits that is still empty: fields
with a shape of their own (a number, a report, a zone, a locator or a `validation`) first, free text fields last;
a word mixing digits and letters is split (`123A` = `123` + `A`). A word typed again corrects the earlier value
(`123 A 72 OH 73` → check 73), and a callsign in the box (`K1ABC`) is logged instead of the call field's. The
interpretation is shown above the box (`nr 123 · prec A · ck 72 · sec OH`, `?` = a word that fits nowhere). Give
the serial before the check when both are numbers.

A received or sent field of type `IOTA` is written to Cabrillo with the dash (`EU123` → `EU-123`).

Points taken from an exchange value (`Exchange, *`) are `value: { expr: "nr" }`; points for a filled field
(`IsMisc`) are a rule with `when: { fieldPresent: misc }`.

Full examples are in the built-in definitions (`contest-data/contests/` — CQ WW,
WPX, IARU, OK-OM DX...); it is best to **duplicate** one and edit it.

## Built-in definitions

The published `contest-data/` holds 159 definitions (each file's `metadata.description` says
what is simplified against the official rules; `dx`, `dx-serial`, `dxpedition`, `dx-satellite`, `vhf-dx` and `vhf-serial` are the generic logs of N1MM DX, DXSERIAL, DXPEDITION, DXSATELLIT, VHFDX and VHFSERIAL): 10-10 International QSO Party — Phone, 10-10 International Sprint (10 October), 9A DX Contest (Croatian DX Contest), AGCW Happy New Year Contest, AGCW QRP Contest, All Asian DX Contest — CW, All Asian DX Contest — Phone, ARI International DX Contest, ARRL 10 GHz and Up Contest, ARRL 10-Meter Contest, ARRL 160-Meter Contest, ARRL Field Day, ARRL International DX Contest — CW, ARRL International DX Contest — CW (W/VE and DX), ARRL International DX Contest — SSB, ARRL International DX Contest — SSB (W/VE and DX), ARRL International EME Contest, ARRL January VHF Contest, ARRL June VHF Contest, ARRL November Sweepstakes — CW, ARRL November Sweepstakes — SSB, ARRL Rookie Roundup — CW, ARRL Rookie Roundup — RTTY, ARRL Rookie Roundup — SSB, ARRL RTTY Roundup, ARRL September VHF Contest, Baltic Contest, BARTG HF RTTY Contest, BARTG RTTY Sprint (January), California QSO Party (CQP), Commonwealth Contest (BERU), CQ 160-Meter Contest — CW, CQ 160-Meter Contest — SSB, CQ World Wide VHF Contest — Digital, CQ World Wide VHF Contest — SSB/CW/FM, CQ WPX Contest — CW, CQ WPX Contest — SSB, CQ WW DX Contest — CW, CQ WW DX Contest — SSB, CQ WW RTTY DX Contest, CQ WW RTTY WPX Contest, CQ-M International DX Contest, CWops CW Open, CWops CWT (mini-CWT), DARC 10m Contest, DARC Christmas Contest (XMAS), DX — volné logování, DXPEDITION — DXpedition log, DXSATELLIT — satellite log, EA PSK63 Contest, EA RTTY Contest (EARTTY), EA-QRP CW Contest, EU PSK DX Contest, EU Sprint — CW, EU Sprint — SSB, European HF Championship, Florida QSO Party (FQP), FOC Old School Classic 1960s QSO Party, GACW WWSA CW DX Contest, HA-DX Contest, His Majesty The King of Spain Contest — CW, His Majesty The King of Spain Contest — SSB, HSC CW Contest, IARU HF Championship, IARU Region 1 50 MHz Contest (CW/SSB), IARU Region 1 Field Day — CW, IARU Region 1 Field Day — SSB, IARU Region 1 UHF Contest (432 MHz), IARU Region 1 UHF/Microwave Contest (1.3-10 GHz), IARU Region 1 VHF Contest (144 MHz), International FT Challenge, International Naval Contest (INC), Japan International DX Contest — CW, Japan International DX Contest — Phone, JARL / JARTS WW RTTY Contest, KV Provozní aktiv (KVPA), LZ 2 Meters FM Open Contest, LZ DX Contest, LZ International Six Meters Contest, Makrothen RTTY Contest, Marconi Memorial Contest (144 MHz CW), Memoriál OK1WC (MWC), Mexico RTTY International Contest, Michigan QRP Labor Day CW Sprint, Nordic Activity Contest (NAC) — 1296 MHz, Nordic Activity Contest (NAC) — 144 MHz, Nordic Activity Contest (NAC) — 432 MHz, Nordic Activity Contest (NAC) — 50 MHz, New England QSO Party (NEQP), North American QSO Party — CW, North American QSO Party — RTTY, North American QSO Party — SSB, North American Sprint — CW, North American Sprint — SSB, NRAU-Baltic Contest — CW, NRAU-Baltic Contest — SSB, Oceania DX Contest — CW, Oceania DX Contest — Phone, OK DX RTTY Contest, OK-OM DX Contest — CW, OK-OM DX Contest — SSB, PA-Beker Contest, PACC Contest, Polní den na VKV (III. subregionální závod), Portugal Day Contest, QRP ARCI Holiday Spirits Homebrew Sprint, RDA Contest (Russian Districts Award), REF Contest (Coupe du REF) — CW, REF Contest (Coupe du REF) — SSB, REF DDFM 50 MHz Contest, RSGB 1.8 MHz Contest, RSGB 80m Autumn Series — CW, RSGB 80m Autumn Series — Data, RSGB 80m Autumn Series — SSB, RSGB 80m Club Championship — CW, RSGB 80m Club Championship — Data, RSGB 80m Club Championship — SSB, RSGB AFS Contest — CW, RSGB AFS Contest — Data, RSGB AFS Contest — SSB, RSGB Club Calls (AFS 160), RSGB International Low Power Contest, RSGB IOTA Contest, Russian 160m DX Contest - RU3AX Memorial, Russian DX Contest, Russian WW RTTY Contest, Russian YL/OM Contest, Scandinavian Activity Contest — CW, Scandinavian Activity Contest — SSB, SCC RTTY Championship, School Club Roundup, SP DX Contest, SP DX RTTY Contest, Spanish Municipalities Contest (CME), Stew Perry Topband Challenge, UBA DX Contest — CW, UBA DX Contest — SSB, UBA ON Contest — HF, UBA ON Contest — VHF, UBA PSK63 Prefix Contest, UBA Spring Contest, UK/EI DX Contest, Ukrainian DX Contest, UKSMG Summer Es Contest, UN DX Contest, USKA Helvetia Contest, VKV Provozní aktiv (OK Activity Contest VHF-UHF-SHF), WAE DX Contest — CW, WAE DX Contest — RTTY, WAE DX Contest — SSB, Winter Field Day, Worked All Germany (WAG) Contest, World Wide Digi DX Contest, World Wide Holyland Contest, YO DX HF Contest, YU DX HF Contest.

Two algorithm sets key on the worked call itself: `worked_calls` (every station is a multiplier, e.g. the OK/OL
stations in OK DX RTTY) and `last_letters` (the last character of the call, the OK1WC memorial).

## Importing an N1MM UDC file

**"Importovat UDC…"** (Import UDC...) converts an N1MM+ user defined contest (`.udc`) into a definition and opens
it as a new, unsaved file. The names, mode, bands, dupe rule (`DupeType`, `DupeQSOMinutesAgo`, `DupeSqlString`),
the exchange from `CabrilloString` (also `Last2L` / `LastCallSuff`), up to three multipliers with their scope and
country restrictions, `PointsPerContact` (fixed, band, mode, continent, country, own country, filled fields,
`Exchange, *`), the point multipliers by time, band, mode, continent and country, `PowerMult`, bonus calls, sessions,
per-band numbering, `IsWorkable`, the usual start and the minimum off time are mapped. Everything that has no
equivalent is listed in `# UDC:` comments at the top — review them, adjust the definition and save it. A
multiplier over a section list the app does not know gets an open set (`<id>_<list>`) in `multipliers/`; replace
it with the real list (Import counties) when you have one. The DXLog converter of the Java version 1.1.1 was not
carried over.

## Updating definitions from the internet

Equivalent of N1MM **Check for updated contest definitions**. Menu **"Nástroje →
Aktualizovat definice z internetu"** (Tools → Update definitions from the
internet):

- downloads `index.txt` and the files listed in it from the published
  [`contest-data`](https://github.com/ok1xoe/MacContestLogger/tree/main/contest-data)
  directory (contest definitions, multiplier sets, band plan, digital
  frequencies) into the contest data directory from Settings,
- adds new files and updates changed ones — it **does not overwrite locally
  modified files** (it recognizes them by the hash from the last download in
  `.update-manifest.properties`),
- it does not write a definition that fails the editor's check,
- after downloading it reloads the definitions; the status line shows a summary,
  the messages window the details.

To return a modified file to the published version, simply delete it and run the
update again.
