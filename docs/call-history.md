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

## Exchange prefill

After a callsign is typed (from 3 characters, a short pause), the **empty** fields
of the received exchange are filled from call history:

1. a column with the same name as the field (`name`, `state`, `zone`...),
2. otherwise by field type: CQ zone ← `CQZone`, ITU ← `ITUZone`, state/province ←
   `State`/`Sect`, locator ← `Loc1`, district ← `District`/`Loc2`, text ← `Name`,
3. otherwise `Exch1` (when the contest has a single "free" field).

The report and serial number are not filled in. Values you overwrote by hand are
not changed; when you change the callsign, the prefilled values of the previous
callsign disappear.

## Update from the log

Equivalent of N1MM **Update Call History from log** and DXLog **Update prefill
database from log**. Menu **"Závod → Aktualizovat call history z deníku"**
(Contest → Update call history from log; only in an open contest):

- from each QSO it takes the received exchange fields (without report and serial
  number); when a station is in the log several times, the **newest** QSO counts,
- it writes the value into the column named like the field, otherwise into the
  typical column by type (CQ zone → `CQZone`...); missing columns are added to
  `!!Order!!`,
- it merges with the existing call history (adds new callsigns, overwrites values,
  leaves other columns) and saves it atomically back to the file.

Without a configured file, `CALLHISTORY.txt` is created in the application data
directory and the path is saved in the settings. X-QSOs and deleted QSOs are not used.

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
- The log window's row menu ("Přehled spojení") and the bandmap's spot menu have
  **Dohledat na HamQTH** and **Dohledat na QRZ.com** (Look up on …). They open the call's page
  in the browser (`https://www.hamqth.com/<CALL>`, `https://www.qrz.com/db/<CALL>`); no
  credentials are needed, and nothing is looked up through the API or written to the log.
