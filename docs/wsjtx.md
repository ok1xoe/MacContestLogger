# WSJT-X and JTDX

MacContestLogger works with WSJT-X and JTDX like N1MM Logger+: it receives their UDP messages (decodes,
status, logged QSOs), shows the decodes in its own list, colours the callers in WSJT-X's Band Activity
and can start the program. The UDP setup itself is described in
[Connecting WSJT-X ⇄ RUMlogNG ⇄ MacContestLogger over UDP](interop-udp-setup.md).

## Settings → WSJT/JTDX

- **Příjem z WSJT-X** (receive): the address WSJT-X's *UDP Server* points to (default `0.0.0.0:2237`).
- **Barvit volačky v Band Activity** (on by default): every decoded caller is coloured in WSJT-X's Band
  Activity window by the contest status — a multiplier red background, several multipliers green, a new
  QSO blue text, a dupe grey text (WSJT-X message *HighlightCallsign*, sent back to the instance that sent
  the decode, only when the colour changes).
- **DX Call z WSJT-X do pole volačky** (on by default): the callsign in WSJT-X's *DX Call* field appears in
  the entry window's callsign field, so the dupe and multiplier check works while you call the station in
  WSJT-X. The focus stays where it is.
- **Změna pásma vymaže seznam dekódů** (on by default): when WSJT-X moves to another band the decode list
  is cleared.

## The decode list (Okno → WSJT-X dekódy)

N1MM's *Decode List*: the decodes coloured like the bandmap, newest first.

- filters **Jen CQ**, **Skrýt dupe**, **Jen násobiče** and a **text filter** (any part of the message,
  e.g. `73` or a prefix),
- **sort** by time (default), SNR (strongest first), audio frequency or callsign,
- a **band / mode** column (`20m FT8`; with two instances also the instance),
- a double click calls the station in WSJT-X (Reply).

## Starting WSJT-X / JTDX (Okno → Spustit WSJT-X / JTDX)

Set **Program (.app)** (and optional **Parametry**) in Settings → WSJT/JTDX. The menu item starts a new
instance of the program, opens the decode list (*Po spuštění otevřít seznam dekódů*) and starts the UDP
receiver.

### Two instances for SO2R

**Okno → Spustit WSJT-X / JTDX (rádio 2)** starts a second instance with `--rig-name=<name>`, the name
from **Jméno instance pro rádio 2** (for example `Radio2`; WSJT-X then reports itself as
`WSJT-X - Radio2`). Configure that instance for rig 2 and a different UDP port only if you need one —
both can send to the same receiver, MacContestLogger tells them apart by their Id. The second instance's
DX Call goes into the **VFO B / rig 2** entry window; its decodes carry its frequency and its instance in
the list.

## Rig control

N1MM can act as a rig server for WSJT-X (DXLab Commander emulation). MacContestLogger shares the rig
differently: both programs talk to **one `rigctld`**. In WSJT-X choose *Rig: Hamlib NET rigctl*, *Network
Server* `localhost:4532` (the daemon MacContestLogger uses, see
[Digital modes → Sharing CAT](digital-modes.md#sharing-cat-with-fldigi)), *PTT: CAT* and *Split: Rig* or
*Fake It* as you prefer. Frequency, mode, PTT and split then work from both programs without a
Commander emulation.

## JTDX: logging over TCP

JTDX can send each logged QSO to an *External logbook* over TCP (N1MM uses port 52001). Turn on **JTDX:
logování přes TCP** and set the address (default `127.0.0.1:52001`); in JTDX enable the TCP logbook and
point it there. Every ADIF record (up to `<eor>`) is logged like a QSO from WSJT-X.

## Modes

Q65 and FT2 are logged as their own modes (digital: Cabrillo `DG`, rig data mode `PKTUSB`); typing `Q65` or
`FT2` into the callsign field switches the mode.
