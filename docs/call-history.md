# Call history

Equivalent of N1MM+ **Call History**
([Call History Lookup](https://n1mmwp.hamdocs.com/setup/call-history/#Call_History_Lookup))
and DXLog **Prefill database**.

## Settings

**"Nastavení → Závod → Call history"** (Settings → Contest → Call history): a file
in N1MM format (text CSV). Below the field the number of loaded callsigns is
shown. Files for particular contests can be downloaded, for example, from
[n1mm.hamdocs.com](https://n1mmwp.hamdocs.com/setup/call-history/) or from the
organizers.

```
# komentář
!!Order!!,Call,Name,State,CQZone,Exch1
W1AW,Hiram,CT,5,
OK1XOE,Tomas,,15,JN79
```

The `!!Order!!` line defines the columns; without it the N1MM order
`Call,Name,Loc1,Loc2,Sect,State,CK,BirthDate,Exch1,Misc,UserText` applies.
A file may also use `;` as the delimiter: when the first separator after `!!Order!!` is a
semicolon (`!!Order!!;Call;Name;State`), the data lines are split on `;`.

The same group has:

- **Další soubory call history (sloučené)** (Additional call history files, merged) —
  **Přidat soubory…** (Add files…) picks one or more files, **Odebrat** (Remove) takes one
  off the list (see [Several files in one table](#several-files-in-one-table)),
- the active contest's own file with **Přiřadit závodu…** / **Zrušit přiřazení**
  (Assign to the contest / Remove the assignment), applied to the open contest at once
  (see [A contest's own file](#a-contests-own-file)),
- **Načteno celkem: N volaček** (Loaded in total) — the callsigns of all loaded files together,
- **Zapnout dohledávání v call history** (Enable call history lookup), the same switch as the menu item below,
- **Zobrazovat informace uživatele (UserText)** (Show user information) — the call history
  and UserText lines in the entry window.

## Enabling the lookup

Equivalent of N1MM **Config → Enable Call History Lookup**: menu **"Nastavení →
Zapnout dohledávání v call history"** (Settings → Enable call history lookup) is a check
item (on by default; config key `callHistoryLookupEnabled`). When it is off, nothing is
prefilled from the call history (the callbook prefill stays); the reverse lookup and the
UserText line still work, as in N1MM.

### Associating a file with contests (`#CONTEST` lines)

As in N1MM, a comment line can name the contest a file is meant for — the `#` first on the
line, one contest per line, upper/lower case does not matter:

```
#CQWWCW
# cq-ww-ssb
# QSO Party PA
```

When a contest is opened, the names are compared with the contests the logger knows (the
definitions in the contest data directory) by their id and their name, with case, spaces,
dashes and other punctuation ignored (`#CQWWCW`, `# CQ WW CW` and `#cq-ww-cw` all name
`cq-ww-cw`):

- if the file names known contests and **one of them is the opened contest**, the lookup is
  switched **on**,
- if it names known contests but **not this one**, the lookup is switched **off**,
- if no comment names a known contest (ordinary comments, or only N1MM short names the
  logger has no definition for), the switch is left as it is.

This happens once when the contest is opened (and when its file changes); switching the menu
item afterwards stands. The comments and directives of the file are kept when the logger
saves it (update from the log, clearing).

## A contest's own file

Equivalent of N1MM **Contest Setup → Associated Files**. The **Nový závod** (New contest)
window has a **Call history závodu** (Contest call history) field with **Vybrat soubor…**
(Choose file…); empty means the main file from Settings. While that contest is open, its
file is used instead of the main one (the additional files are still merged in), and the
logger switches back when another contest is opened. The file is remembered with the
contest's setup and offered again the next time the same contest is created. For a contest
that is already open, use **Přiřadit závodu…** in Settings → Contest → Call history.

## Several files in one table

Equivalent of N1MM's **File → Import → Import Call History** with several files selected:
menu **"Soubor → Import → Importovat call history…"** (File → Import → Import call history…)
lets you choose one or more files (Cmd+click); they are added to the additional files of
Settings → Contest → Call history and loaded at once. The additional files are merged after
the main one into one table, in their order:

- a callsign that is not in the table yet is added,
- for a callsign already there, the later file's **non-empty** fields overwrite the earlier
  ones; empty fields leave them as they are,
- **UserText** is appended (`!!AppendUserText!!`, the default) unless the later file says
  `!!NoAppendUserText!!` (then it replaces it),
- a different **Loc1** moves the previous one to **Loc2** (an alternate grid) unless the later
  file says `!!NoLoc2AltGrid!!`.

The files themselves are not changed: **Update from the log** and **Clear call history** write
only the main file (or the contest's own file). Export writes the merged table.

## Import directives

N1MM's directive lines start with `!!` and may be anywhere in the file; several may share a
line, separated by `,` or `;` (`!!MapStateToSect!!;!!FourCharGridSq!!`):

| Directive | Effect |
|---|---|
| `!!MapStateToSect!!` | an empty `Sect` takes the `State` value |
| `!!FourCharGridSq!!` | 6-character grids (`Loc1`, `Loc2`) are cut to 4 characters |
| `!!AppendUserText!!` | a repeated callsign appends its UserText (the default) |
| `!!NoAppendUserText!!` | a repeated callsign replaces its UserText |
| `!!Validate50State!!` | a `State` that is not one of the 50 US states is dropped (DC is not a state, so it is dropped too) |
| `!!NoLoc2AltGrid!!` | a different Loc1 overwrites the previous one instead of moving it to Loc2 |
| `!!MapOnSection!!` | the Ontario sections GTE (GTA), ONN, ONE and ONS become ON |
| `!!ValidateArrlSection!!` | a `Sect` that is not an ARRL/RAC section is dropped (PR and VI are sections, ON is not) |

A file **with** directives follows N1MM's import rules also for a callsign repeated inside the
file (the fields are merged as above). A file **without** any directive reads exactly as before
(a later line of the same callsign replaces the whole record), so existing files behave the same.

## Exchange prefill

After a callsign is typed (from 3 characters, a short pause), the **empty** fields
of the received exchange are filled from call history:

1. a column with the same name as the field (`name`, `state`, `zone`...),
2. otherwise by field type: CQ zone ← `CQZone`, ITU ← `ITUZone`, state/province ←
   `State`/`Sect`, locator ← `Loc1`, district ← `District`/`Loc2`, text ← `Name`,
3. otherwise `Exch1` (when the contest has a single "free" field).

A locator field takes the locator of an earlier QSO with the same station in the open log first (N1MM; the same
base call counts, so `OK1ABC/P` gets the grid logged for `OK1ABC`), then the call history's.

The report and serial number are not filled in. Values you overwrote by hand are
not changed; when you change the callsign, the prefilled values of the previous
callsign disappear.

## Update from the log

Equivalent of N1MM **Update Call History from log** and DXLog **Update prefill
database from log**. Menu **"Nástroje → Aktualizovat call history z deníku"**
(Tools → Update call history from log; only in an open contest):

- from each QSO it takes the received exchange fields (without report and serial
  number); when a station is in the log several times, the **newest** QSO counts,
- it writes the value into the column named like the field, otherwise into the
  typical column by type (CQ zone → `CQZone`...); missing columns are added to
  `!!Order!!`,
- it merges with the existing call history (adds new callsigns, overwrites values,
  leaves other columns) and saves it atomically back to the file,
- a locator follows N1MM's rule for **Loc1/Loc2**: a grid different from the stored Loc1
  becomes Loc1 and the previous Loc1 moves to Loc2 (the older Loc2 is dropped); a 4-character
  grid is overwritten by a 6-character grid of the same square (no move), and a 4-character
  grid never replaces a 6-character one of its square. `!!NoLoc2AltGrid!!` in the file turns
  the move off.

It writes the **main** file — the open contest's own file when it has one — never the
additional merged files. Without a configured file, `CALLHISTORY.txt` is created in the
application data directory and the path is saved in the settings. X-QSOs and deleted QSOs
are not used.

## Clearing the call history

**"Nástroje → Vymazat call history…"** (Tools → Clear call history...), after a confirmation, empties the loaded call
history: the file keeps its columns (the `!!Order!!` header) and no callsign, and the history in the logger is empty at
once. The file is **never lost**: its previous content is copied beside it first as `<file>.bak-<UTC time>`
(for example `CALLHISTORY.txt.bak-20261128-143000`). N1MM's **Clear Call History then Update** is these two menu items
in a row: clear, then **Aktualizovat call history z deníku** (Update call history from log). To keep a copy elsewhere,
use **Soubor → Export → Call history** first (see [Import and export](import-export.md)).

## Call history and UserText lines

Equivalent of N1MM's **Show User Information**. With **Zobrazovat informace uživatele
(UserText)** on (Settings → Contest → Call history; on by default, config key
`callHistoryShowUserInfo`), the strip below the frequency of the entry window (the VFO B
window too), next to the callbook line, shows for the typed callsign:

- `Call history: Name: Hiram, State: CT, Loc1: FN31, CQZone: 5` — the record's columns except
  the callsign and UserText, while the lookup is enabled,
- the record's **UserText** in blue on its own — also when the lookup is disabled, as in N1MM.

Nothing is shown for a callsign without a record.

## Reverse lookup

Equivalent of N1MM **Reverse Call History Lookup**
([doc](https://n1mmwp.hamdocs.com/setup/call-history/#Reverse_Call_History_Lookup)).
When you miss the callsign but catch the exchange (typically name and state in a
QSO party):

1. leave the callsign field **empty** and fill what you know into the exchange fields,
2. below the callsign field `Call history: W1AW K1ABC ...` appears — callsigns
   whose call history record matches **all** filled fields (case-insensitive;
   report and serial number are not counted),
3. a click puts the callsign into the field.

Fields are compared with the same columns from which they would be prefilled.

The **Check window** (Okno → Check) has a fuller reverse lookup: it also searches the QSOs of the log, accepts a
partial value (from a threshold of characters, matching from the start of the value or anywhere) and lists up to 100
calls; see [Callsign check](call-check.md#reverse-lookup).

## Callbook (HamQTH / QRZ.com)

Equivalent of N1MM **Callbook lookup**. With a HamQTH or QRZ.com account ("Nastavení
→ Online callbooks", Settings → Online callbooks, enabled), after a short pause in
typing the callsign the following is looked up:

- below the callsign field a line `Callbook: name · locator · CQ 15 · ITU 28`,
- empty exchange fields such as locator, CQ zone, ITU zone and the `name` field are
  prefilled (call history takes precedence; manually entered values are not
  changed, and the prefill disappears when the callsign changes).

Results are stored in a cache shared with the spot lookup, and the program does
not ask twice for the same callsign.

### Manual lookups

The automatic lookup waits for a pause in typing and respects the "Volat … pro módy"
(Call … for modes) settings. A lookup can also be asked for by hand; it ignores the
mode restriction and the pause, but still needs the service's user name and password:

- **Settings → Online callbooks → "Preferovaný online callbook"** (Preferred online
  callbook) chooses HamQTH (default) or QRZ.com (config key `preferredCallbook`).
- The last button of the entry window's action bar is labelled with that service. It
  asks the service for the call in the call field at once. The result goes to the
  `Callbook:` line and fills the empty exchange fields it can (locator, CQ zone, ITU zone,
  name) by the same rules as the automatic lookup: a field you have typed into is never
  overwritten, and the fill disappears when the callsign changes. When nothing is found, the
  line says why (not found, login failed, network error). The button is greyed, with a
  tooltip, when the service has no credentials or the call field is empty. It works in the
  VFO B window too.
- The log window's row menu ("Přehled spojení") and the bandmap's spot menu both have
  **Dohledat na HamQTH** and **Dohledat na QRZ.com** (Look up on …). They open the call's page
  in the browser (`https://www.hamqth.com/<CALL>`, `https://www.qrz.com/db/<CALL>`); no
  credentials are needed, and nothing is looked up through the API or written to the log.
