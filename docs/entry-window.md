# Entry window

The entry window is the main window: the frequency strip, the band × mode buttons, the fields of the QSO, the
hints, the F-key messages and the action buttons. Keys are listed in [keyboard shortcuts](keyboard-shortcuts.md).

## Right-click menu

A right click anywhere in the entry window (outside the text fields) opens N1MM's view menu:

- **the parts shown** — band buttons, the hints by the frequency (callbook, call history, worked before…), the
  bearing and distance, the Run/S&P and ESM line, the CW speed, the F1–F12 buttons and the Wipe / Log It / Edit
  buttons. A hidden part makes the window smaller.
- **Klik na tlačítko pásma mění pásmo** (N1MM *Band Button Left Click Enabled*): off = the band buttons only show
  the bands and their colours, a click does nothing.
- **Zobrazená pásma** — which bands have a button.
- **Hodiny UTC** (N1MM *Show GMT Time*) — a UTC clock in the frequency strip.
- **Informace uživatele (call history)** (N1MM *Show User Information*) — the call history line of the typed call
  (also Settings → Contest).

The choices are saved with the settings.

## Colours of the typed call

In a contest the typed call is checked on the current band and on every band button:

| Colour | Meaning |
|---|---|
| green | a double (or better) multiplier |
| red | a multiplier |
| blue | a new QSO without a multiplier |
| grey | a dupe |

The callsign text has the colour of the current band (a dupe keeps the red border and the DUPE chip); the band
buttons get a frame in the colour of the call on that band. Under the frequency the bearing line shows the call's
country and, as N1MM's status line, the short and long path beam headings and the short-path distance to it
(Settings → Station: your latitude and longitude; without them only the country).

## Editing a QSO

- **Ctrl+Y**, the **Edit** button or **Úpravy → Upravit poslední spojení…** (N1MM *Edit Last Contact*) open the
  last logged QSO in the edit dialog: time (UTC, `yyyy-mm-dd hh:mm:ss`), callsign, frequency in kHz (the band
  follows it), mode, reports, serial numbers, exchange, note, operator and X-QSO. **Uložit** (or Enter) saves the
  QSO and the score is recounted; Esc or **Zrušit** closes the dialog without a change. A field that cannot be
  read (an unknown mode, a bad time) is named under the fields and the dialog stays open.
- **Úpravy → Upravit rozpracované spojení…** (N1MM *Edit Current Contact*) opens the QSO you are typing: callsign,
  frequency, mode, sent report, the contest's received fields (or RST and exchange in free logging) and the note.
  **Uložit** puts the values back into the entry window; nothing is logged.
- Older QSOs are edited in the [log window](log-window.md) or with QuickEdit.

## QuickEdit

N1MM's QuickEdit edits logged QSOs right in the entry window, without a dialog:

- **Ctrl+Q** puts the last logged QSO into the fields; every further **Ctrl+Q** goes one QSO back, **Ctrl+A** one
  QSO forward. The fields turn light blue and the hint strip shows *QuickEdit n/m* (n = how many QSOs back).
- Correct the callsign, the frequency, the mode, the reports or the exchange, then press **Enter** (or **Log It**)
  to save the QSO; the score is recounted. Nothing is logged as a new QSO.
- **Esc** (or **Wipe**) leaves the QSO unchanged.
- Either way the entry window gets back what you were typing before Ctrl+Q. While QuickEdit is on, the frequency
  field does not follow the rig and the dupe beep is silent.
- The menu items are **Úpravy → QuickEdit (o QSO zpět / vpřed)**.

## Finding a callsign

**Ctrl+F** opens the log window with the QSOs of the callsign typed in the callsign field. Pressing **Ctrl+F**
again with the same callsign (N1MM *Find Again*) selects the next of those QSOs in the log window, and after the
last one starts again from the first.

## While typing and logging

- **`?` in the callsign** — when the cursor comes back to the callsign field (Space, Tab, Esc…), a `?` is selected so
  the next key replaces it; with two or more `?` the text from the first to the last one is selected (`DL?K?A`).
  Any other field is selected whole when it gets the cursor, so a serial number is simply typed over.
- **Clearing the auto-populated exchange** — with *Settings → Contest → Při změně volačky smazat výměnu doplněnou
  z call history nebo spotu* a change of the callsign clears the exchange values the call history or a spot filled
  in (values you typed stay).
- **Serial number warning** — when a message with the serial number (`#`, `{NR}`, `{EXCH}`) was sent for the QSO
  and the QSO is logged with another number (another station of the network took it meanwhile), the status line
  says *Pozor: odesláno číslo …, zapsáno …*.
- **Tuning away before logging** — a typed callsign is stored in the band map when you tune away
  ([self-spot](dx-cluster.md)), and the status line warns that the QSO was not logged.
- **Sent CW** — with *Settings → CW klíč → Zobrazovat odesílané CW ve stavovém řádku* the status line shows the
  text of every CW message as it is sent (`CW: 5NN 001`).
