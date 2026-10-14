# ESM – Enter Sends Message

With ESM, the whole contact can be sent with the **Enter** key: based on the contents
of the entry window the program recognizes which phase of the QSO you are in, sends the
right F-key message and logs the QSO at the right moment. The behavior follows the
table from the N1MM+ manual exactly
([ESM Overview](https://n1mmwp.hamdocs.com/setup/function-keys/#ESM_Overview));
DXLog has the same ([ESM](https://dxlog.net/docs/index.php?title=Getting_started#ESM)).

It works in CW (CW keyer, see [cw-keyer.md](cw-keyer.md)) and in phone (voice keyer,
see [voice-keyer.md](voice-keyer.md)).

## Turning it on

- the **ESM** checkbox next to Run / S&P in the entry window,
- the text command `ESM` / `NOESM` (also `ESMON` / `ESMOFF`),
- or Settings → Function Keys → ESM.

The keys that the next Enter will send have a **prominent frame** in the F-key grid.
When Enter also logs the QSO, the **Log It** button has a frame too.

## What Enter sends

The usual message layout is assumed (the default sets have it): F1 CQ, F2 exchange,
F3 TU, F4 my callsign, F5 his callsign, F6 QSO B4, F8 again? Another layout is set in
**Přiřazení F-kláves pro ESM** (N1MM "Function Key Assignments for ESM", Settings → Function
Keys → ESM): a key for each of CQ, Exchange, End of QSO, My call, His call, QSO B4 and
Again. The table below then means the assigned keys; the CQ key is the special one, and the
CQ repeat (Alt+R) and the send shortcuts use the assignments too.

| Callsign | Exchange | Run | S&P |
|---|---|---|---|
| empty | – | F1 (CQ) | F4 (my callsign) |
| new, first time | empty / invalid | F5 + F2, cursor into the exchange | F4 |
| new, again | empty / invalid | F8 (again?) | F4 |
| new | valid, exchange not yet sent | F5 + F2 | F2 + log |
| new | valid, exchange already sent | F3 + log | log |
| dupe | empty / invalid | F6 (QSO B4) | nothing |
| dupe | valid | as new | as new |

- **Valid exchange** = the QSO can be logged (in a contest a complete and valid exchange
  according to the definition, outside a contest the callsign is enough).
- In Run, a **corrected callsign** (changed after F5 was sent) is sent again before TU
  (N1MM "Send corrected call").
- **F1 switches to Run** (N1MM: the CQ key is special), even when pressed manually.
- Clearing the callsign or **Wipe** starts the QSO again from the beginning.

## Options (Settings → Function Keys → ESM)

- **S&P: send the callsign only once** ("Big Gun"): the first Enter sends F4 and the cursor
  jumps to the exchange, the next Enter without an exchange sends F8.
- **Run: treat a dupe as a new QSO** (Work dupes, on by default): a dupe is worked
  as a new QSO instead of F6.
- **Send partial calls**: the corrected callsign is sent again only in the part that
  changed — the suffix when the prefix (up to its digit) is the same (`OK1XOF` → `OK1XOE`
  sends `XOE`), the prefix when the suffix is the same; otherwise, or with a `/`, the whole call.
- **Between his call and the exchange (CW)** (N1MM "String between his call and exchange"):
  the text that joins F5 and F2 sent together; a space by default.
- **F-key stacking**: a key pressed while a message is sent (CW, SSB) is queued and sent in
  full after it, as in N1MM; its button lights when its turn comes. Esc stops everything,
  queue included. Off = the new key interrupts the message (the earlier behaviour).

## Call stacking

With a [call stack](call-stacking.md) and a **Next Call key** (Settings → Function Keys → Call
stacking), the end of a Run QSO continues with the next stacked call: where the table says
"F3 + log", Enter sends the Next Call key instead (a corrected call is still sent first), and its
`{LOGTHENPOP}` logs the QSO, takes the next call into the field and sends it the exchange. The
F-key grid frames the Next Call key. With an empty stack Enter sends TU and logs as usual.

## Keys

| Key | Action |
|---|---|
| **Enter** | ESM step according to the table |
| **space bar** in the callsign | jumps to the exchange (the first field that is not a report) |
| **=** | repeats the last transmitted messages |
| **Esc** | stops transmitting, another Esc clears the fields |

**Phone trick (N2IC):** in Run you say the callsign and exchange live, then press the
**space bar** instead of Enter. The program takes the exchange as sent, so after the received
exchange is entered, Enter sends TU (F3) straight away and logs the QSO.

## CQ repeat limit

Settings → Function Keys → Run / S&P → **Nejdelší opakování CQ (min)** (N1MM "Max Repeat /
Dueling CQ duration"): the CQ repeat (Alt+R) switches itself off after this many minutes of
repeating; 0 = no limit (the default).
