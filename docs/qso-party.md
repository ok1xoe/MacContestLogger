# TOUR, QSO parties (rover, county line, bonus stations) and spots

Text commands from N1MM+
([Callsign Box Text Commands](https://n1mmwp.hamdocs.com/manual-windows/entry-window/),
[Rover, Mobile and County Line Support](https://n1mmwp.hamdocs.com/manual-supported/contests-setup/setup-qsop-contests/#Rover_Mobile_and_County_Line_Support))
and DXLog (`SPOTME`). The general list of commands is in [text-commands.md](text-commands.md).

## TOUR – contests with sessions

Some contests (mainly Russian and Ukrainian) are run in sessions, and the same
station can be worked again in every session.

| Command | Action |
|---|---|
| `TOUR 1200/30` | sessions start at 12:00 UTC and last 30 minutes. Dupes are checked only within a session |
| `TOUR` | parameters from the **Snt** field (like N1MM, e.g. `1200/30`). When they are not there, it shows the current setting and the start of the running session |
| `NOTOUR` / `TOUROFF` | no sessions, dupes for the whole contest (also turns off sessions from the contest definition) |

- The format is `hhmm/mm`; the length can also be given as `hhmm` (`2100/0100`).
  The shortest session is 5 minutes.
- Sessions follow one another continuously, also across midnight.
- The setting is **saved with the contest** (N1MM forgets it after a restart) and
  the score is recalculated immediately.
- The entry window shows `TOUR 1200/30 do 1230Z` (the end of the running session).
- On the transition to the next session a message arrives, "Nové sezení závodu
  1230Z–1300Z" (New contest session 1230Z–1300Z; status bar + messages) — the
  equivalent of DXLog **Period autoswitch**.

### Periods in the contest definition

A contest with sessions does not need to have them set by hand — it is enough to
list them in the YAML definition (Tools → Definition editor, "Nástroje → Editor
definic"):

```yaml
period:
  durationHours: 4
  sessions: { start: "1200", minutes: 60 }   # sezení po hodině od 12:00 UTC
```

After the contest is opened, the sessions turn on by themselves. The command
`TOUR hhmm/mm` overrides them (saved with the contest), `NOTOUR` turns them off.

## Rover – ROVERQTH

| Command | Action |
|---|---|
| `ROVERQTH HAM` | my current county. Saved into the station data (Rover QTH), so it survives a restart |
| `ROVERQTH` | a dialog with the current value |

- The county is sent in the exchange (a field with source `ROVER_QTH`, see below)
  and by the CW macro `{ROVERQTH}`.
- It is stored with every QSO, so Cabrillo has on every line the county from where
  you really transmitted.
- **From a new county the same station can be worked again:** the dupe is counted
  separately for each of my counties.
- The entry window shows `Rover HAM`.

## County line – COUNTYLINE

| Command | Action |
|---|---|
| `COUNTYLINE DAD,JEF,WAL` | I am transmitting from a county line |
| `COUNTYLINE` | a dialog (empty = end of county line) |
| `NOCOUNTYLINE` | end of county line |

- Each QSO is logged **once for each county** (N1MM: 3 counties = 3 QSOs in the
  log), with that county in the sent exchange.
- All copies have the transmitted serial number. The other station logs one
  number, and the next QSO then has a number higher by the number of copies.
- The CW macro `{COUNTYLINE}` sends `DAD/JEF/WAL`. In county-line mode `{ROVERQTH}`
  is ignored and vice versa, so one set of messages serves both modes (N1MM).
- County line is not saved (like N1MM); after a restart it must be entered again.
- **The other station on a county line:** type its counties into the received field as `ORDES/JEF` (shorthand for
  `ORDES/ORJEF`, counties of one state) or `IDFRA/UTCAC` (two states). One QSO per county is logged (N1MM 7QP).
  This needs `split: true` on the received county field (add it to a definition made from the "Nová QSO party…"
  template: `- { id: qth, type: DISTRICT, required: true, split: true }`). Enter the
  compound value when logging the QSO; editing a logged single-county QSO into a compound one does not add QSOs.
- The entry window shows `County line DAD/JEF/WAL`.

## Bonus stations – BONUS

| Command | Action |
|---|---|
| `BONUS W1AW, K1BON` | list of bonus stations (separated by comma or space) |
| `BONUS` | a dialog with the current list (empty = delete) |

- The base of the callsign is enough: `W1AW` also applies to `W1AW/M` or
  `W1AW/ESX`. In N1MM every variant must be listed.
- The list is **saved with the contest** and the score is recalculated immediately.
- How many points a bonus gives and how often is determined by the contest
  definition (see below).
- The entry window shows `Bonus 2` (the number of stations).

## Spots to the DX cluster

| Command / key | Action |
|---|---|
| **Spot It** (button), **Alt+P** | spot the callsign from the field on the current frequency. When the field is empty, it spots the last logged QSO (N1MM) |
| `SPOTME` / `SPOTME CQ TEST` | spot your own station with a comment (default "CQ"), DXLog |

- `DX <kHz> <callsign> <comment>` is sent. The DX cluster must be connected.
- **Self-spotting is forbidden in many contests**, and the status line warns about
  it. Check the contest rules.

## Contest definition (YAML)

For rover, county line and bonus stations to do anything, the QSO party definition
must describe them:

```yaml
exchange:
  sent:
    - { id: rst, type: RST,  source: AUTO_RST }
    - { id: qth, type: TEXT, source: ROVER_QTH }    # můj okres (ROVERQTH / COUNTYLINE)
  received:
    - { id: rst,  type: RST,  required: true }
    - { id: cnty, type: TEXT, required: true }

scoring:
  qsoPoints: { mode: FIRST_MATCH, default: 1 }
  bonuses:
    # 100 bodů za bonusovou stanici, jednou na pásmo a mód
    - { id: bonus, when: { bonusStation: true }, value: { fixed: 100 }, scope: PER_BAND_MODE }
  total: "qsoPoints * multTotal + bonusPoints"
```

- `source: ROVER_QTH`: the field value is the rover's county, in county line the
  county of the given QSO copy. Only a contest with such a field counts the dupe
  separately for each of my counties and logs a QSO for each county of the county line.
- Predicate `bonusStation: true`: the other station is on the `BONUS` list.
- `scoring.bonuses` is now actually evaluated. Each bonus with a `when` condition
  is awarded once per `scope` (`ONCE`, `PER_BAND`, `PER_MODE`, `PER_BAND_MODE`); a
  dupe does not get a bonus. It enters the score as the variable `bonusPoints` in
  the `total` formula.

## County lists

The counties of a QSO party (or the counties / sections of another contest) are a
**multiplier set** in the contest data. The list is loaded into the application in
**"Nástroje → Editor definic → Importovat okresy…"** (Tools → Definition editor →
Import counties...):

1. choose a file with the list — lines `CODE,Name` (also `;`, tab or space as a
   separator, `#` comment, a header line `Code,County` is skipped),
2. enter the set id (`ohqp_counties`) — `multipliers/<id>.yaml` + `.csv` is created,
3. **"Nová QSO party…"** (New QSO party...) creates a definition from a template: I
   send my county (`ROVERQTH`), I receive a county (stations from the state) or a
   state, multipliers counties (`<id>_counties`) and states/provinces (`na_areas`),
   CW 2 points, phone 1 point — adjust the points and rules according to the rules
   of the given party.

With a loaded set, counties are checked: `ROVERQTH` and `COUNTYLINE` warn about a
county that is not in the list, the **"Okresy"** (Counties) window shows worked /
missing counties, and a received county outside the list is a warning in the log
table.

## Built-in QSO parties

The California (CQP), Florida (FQP), New England (NEQP), 7th Call Area (7QP), Indiana (INQP) and Delaware (DEQP)
QSO parties are built in, with their county lists.

- **In-state or out-of-state** follows the **ARRL section** in the station data (like N1MM): a section of the
  party's state makes you an in-state station (for CQP the California sections EB, LAX, ORG, SB, SCV, SDG, SF, SJV,
  SV; for 7QP AZ, EWA, ID, MT, NV, OR, UT, WWA, WY). When the log is created, the status line says which one you
  are; a station outside the USA and Canada should have the section `DX`, otherwise it is warned to correct it.
- In-state stations work everyone and count states / provinces (a county of the party's state counts as that
  state) and, where the rules say so, DXCC countries; out-of-state stations may only work the party's state and count
  its counties. A QSO with an out-of-state station from outside is logged with a warning and scores nothing.
- Set **ROVERQTH** to your county (in-state) or your state / province (out-of-state): that is what is sent.
- A mobile in another county is a new station (`dupe.byField`); a station on a county line is logged as `ALC/BAK`.

| Party | Counties (received code) | Points | Multipliers |
|---|---|---|---|
| 7QP | 259, state + county (`ORDES`, `AZYVP`) | phone 2, CW 3, digital 4 | outside: counties once; inside: 50 states, 13 provinces and at most 10 DXCC countries once |
| Indiana | 92, `IN` + county (`INMRN`) | 2 per CW or phone QSO | everyone: counties once per mode; inside also the other 49 states and 13 provinces (no DX) |
| New England | 68, state + county (`MAMID`) | phone 1, CW and digital 2 | outside: counties once; inside: states, provinces and DXCC countries once |
| Delaware | 3: `NDE` New Castle, `KDE` Kent, `SDE` Sussex | inside: phone 1, CW and digital 2; outside: 10 and 20 | per band: outside counties; inside states, provinces and DXCC countries; × power (QRP 3, LOW 2, HIGH 1) |

In-state stations of 7QP, Indiana and Delaware also get the counties of the other parties of that weekend right: a
county such as `ORDES`, `INMRN`, `MAMID` or `NDE` counts as its state (the set `qp_weekend_qth`). The Delaware
definition leaves out the 50-point electronic log bonus, the in-state 6 m-and-up contacts and the FT8/FT4 log,
which the rules want as a separate file with the Field Day exchange.

## Same-weekend combined log (IN7QPNE)

On the first weekend of May the 7QP, Indiana, New England and Delaware QSO parties run at the same time, and their
sponsors accept one log for all of them (N1MM **IN7QPNE**). A station **outside all four areas** chooses the contest
**"7QP + Indiana + New England + Delaware QSO Parties (combined, IN7QPNE)"**:

- Send RS(T) and your state / province or `DX` (set **ROVERQTH**).
- Log the received county exactly as sent. The code decides the party, its QSO points and its multiplier:
  `ORDES` is 7QP, `INMRN` Indiana, `MAMID` New England, `NDE` Delaware. Anything else is not a station of the four
  parties: it is logged with a warning and scores nothing.
- A county line is entered as `ORDES/JEF` (shorthand for `ORDES/ORJEF`, counties of one state), `IDFRA/UTCAC` (two
  states) or `INMRN/HAM`; one QSO per county is logged.
- Each party is scored by its own rules and the score is their sum. The Score window shows every party:
  `7QP: points 5 × multipliers 1 = 5  ·  Indiana: … =  score 76`. The Delaware power factor applies to the
  Delaware part only (the power category of the contest setup).
- A station may be worked once per band and mode, a mobile again from every county. Indiana has no digital QSOs and
  New England no 160 m; such QSOs score nothing for that party.
- Submit the same Cabrillo file (`CONTEST: IN7QPNE`) to all four sponsors; each one scores its own QSOs.

A station inside one of the areas uses that party's own definition; the in-state definitions already count the
other parties' counties as their states.

The definition uses `scoring.parts` (see [definition-editor.md](definition-editor.md)); versions that do not know it
show a single total of all points times all counties.

Sources: [7QP rules](https://www.7qp.org/) and its county list (States & Counties), [Indiana QSO Party
rules](https://www.hdxcc.org/inqp/rules.html) and [counties](https://www.hdxcc.org/inqp/counties.html),
[New England QSO Party rules](https://www.neqp.org/rules), [Delaware QSO Party
rules](https://www.fsarc.org/qsoparty/rules-2024.html), [N1MM+ QSO party setup](https://n1mmwp.hamdocs.com/manual-supported/contests-setup/setup-qsop-contests/).

## Section lists in the contest dialog

Like N1MM's **Edit Section List** and **Import Section List**, the contest dialog (File → New contest, File →
Contest setup) lists the county / section lists of the chosen contest:

- **Upravit seznam…** (Edit list...) opens the list as `CODE,Name` lines; **Uložit** writes it and reloads the
  contest data. The first save keeps the list shipped with the contest data.
- **Obnovit původní** (Restore original) puts the shipped list back.

An edited list is not overwritten by a definition update ("Nástroje → Aktualizovat definice").
