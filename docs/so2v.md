# SO2V — two entry windows on one rig

Equivalent of N1MM+ **SO2V** (Single Operator 2 VFO). To turn it on: **"Nastavení →
Hardware → SO2V"** (Settings → Hardware → SO2V; the choice is saved as `radioMode`
in `config.json`).

- Next to the main window (VFO A), an **"Zadávací okno — VFO B"** (Entry window —
  VFO B) opens with the same fields, keys and F-keys.
- **Active window = active VFO**: a click or focus into a window switches the rig
  over CAT (`V VFOA` / `V VFOB`) — that VFO both receives and transmits. The top
  row of the window shows "VFO A — aktivní (vysílá)" (active, transmitting).
- Each window has its own callsign, exchange and frequency; the frequency and mode
  from the rig, a click on a spot and exchange prefill are taken only by the active
  window. The frequency of the inactive VFO stays as it was and is restored on
  return.
- Typical use: Run on VFO A, hunting multipliers on VFO B — switching with one
  click between the windows.

Switching back to SO1V closes the VFO B window. The rig must support VFO selection
through hamlib (most transceivers with CAT).

# SO2R — two rigs

Equivalent of N1MM+ **SO2R** with an **OTRSP** controller (SO2RDuino, YCCC SO2R
Box+, microHAM in OTRSP mode). To turn it on: **"Nastavení → Hardware → SO2R"**
(Settings → Hardware → SO2R).

- **Rig 1** is the main rig from Settings. **Rig 2** connects to a running
  `rigctld` (host and port in the Hardware tab, default `localhost:4534`), e.g.
  `rigctld -m <model> -r /dev/cu.usbserial-… -t 4534`. Each window has its own CAT
  button and LED.
- The window **"Zadávací okno — rig 2"** (Entry window — rig 2) works with rig 2;
  tuning, CW, split, RIT and spots always go to the rig of the **active** window.
- **OTRSP controller** (serial port in Settings): when the window is switched it
  sends `TX1`/`TX2` (transmit) and `RX1`/`RX2` (headphones), stereo `RX1S`/`RX2S`.

| Key | Action |
|---|---|
| **\\** | switch to the other window (rig / VFO) — N1MM "\" |
| **`** | SO2R stereo listening on / off |

Both keys can be remapped in "Nastavení → Klávesy" (Settings → Keys).
