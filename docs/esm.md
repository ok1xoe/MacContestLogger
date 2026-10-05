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
F3 TU, F4 my callsign, F5 his callsign, F6 QSO B4, F8 again?

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

## Still missing

- automatic CQ repeat,
- a custom ESM key assignment table (N1MM "ESM key mappings").
