# Entry window

The entry window is the main window: the frequency strip, the band × mode buttons, the fields of the QSO, the
hints, the F-key messages and the action buttons. Keys are listed in [keyboard shortcuts](keyboard-shortcuts.md).

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
