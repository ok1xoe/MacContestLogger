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

## 222 MHz and 902 MHz

The Region 2 bands 222 MHz (1.25 m, 222–225 MHz) and 902 MHz (33 cm, 902–928 MHz) are bands of their own, in
frequency order between 2 m and 70 cm and between 70 cm and 23 cm (ADIF `1.25m` and `33cm`; Cabrillo `222` and
`902`; EDI `222 MHz` and `902 MHz`; `{OTHERBAND}` and the N1MM UDP band `222`/`902`). Their band buttons (`1.25m`,
`33cm`) appear in contests whose definition lists them, such as the ARRL VHF contests, and the DX cluster spot
filter has them in its VHF and UHF groups. The score check (`mcl-scorecheck`) reads the Cabrillo band designators
from `50` up (`50`, `144`, `222`, `432`, `902`, `1.2G` … `241G`).

## Bands above 10 GHz

Besides 23 cm – 3 cm, MCL knows the millimetre bands up to 241 GHz like N1MM: 24, 47, 76, 122, 134 and 241 GHz
(ADIF `1.25cm`, `6mm`, `4mm`, `2.5mm`, `2mm`, `1mm`; Cabrillo `24G` … `241G`; EDI `24 GHz` … `248 GHz`). Their band
buttons (labelled `24G` … `241G`) appear in contests whose definition lists them — add them to a definition in the
definition editor (`bands: [..., 3cm, 1.25cm, 6mm]`); the shipped definitions are unchanged.

## Right click on a band button

As in N1MM, a right click (or Control+click) on a band/mode button acts at once:

- **without a network log**, or with an empty call field: the rig goes to that band and mode — the last frequency
  used on the band, otherwise the start of the mode segment — and the call of the **last logged station** is stored
  in the band map there (a local spot, nothing is sent to the cluster). Meant for VHF contests, where one station is
  moved through many bands in a row.
- **in a network log with a call typed**: the call is **passed** to the network station working that band (its pass
  frequency from Alt+Z, otherwise its own frequency), like Ctrl+Alt+P. No station on the band: the status line says so.

The right click works even when *Klik na tlačítko pásma mění pásmo* is off (that option only covers the left click).
VoiceOver offers it as the action *Poslední stanici na toto pásmo*.

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

## Announcements for blind operators (VoiceOver)

Equivalent of N1MM's program announcements for blind operators. **Nastavení → Hlášení pro nevidomé (VoiceOver)**
(Settings → Announcements for blind operators, a check item, off by default, saved) makes the logger announce
through VoiceOver, in VoiceOver's own voice and the language of the user interface:

- the typed call becoming a **dupe** („Dupe") or a **new / double multiplier** („Nový násobič", „Dvojitý
  násobič") — once per change, not at every keystroke;
- a QSO that **cannot be logged** yet: an incomplete exchange („Neúplná výměna, QSO nezapsáno") or a missing time
  in post-contest entry („Chybí čas QSO");
- the rig's **split** going on or off („Split zapnut" / „Split vypnut").

The announcements are accessibility notifications: VoiceOver must be running to hear them, and the logger itself
never opens an audio device for them.
