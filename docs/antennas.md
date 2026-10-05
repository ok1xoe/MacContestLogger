# Antennas and band decoder

Equivalent of N1MM+ **Configurer → Antennas** and the band decoder.

## Antenna table

**"Nastavení → Antennas"** (Settings → Antennas): each antenna has

| Column | Meaning |
|---|---|
| **Code** | value for the antenna switch / band decoder (0–15) |
| **Antenna** | name (shown in the entry window as `ANT ...`) |
| **Bands** | `20m,15m` or in MHz `14, 21` |
| **Sector** | where the antenna points, `270-360`, across north `300-60`; empty = omnidirectional |

## Switching

- After a **band change** the antenna for that band is selected; if the band has
  several antennas, the **azimuth** to the callsign being typed decides (the
  antenna whose sector it points into), otherwise the first in the table.
- **Ctrl+Alt+A** switches to the next antenna of the band (remappable).
- Outputs:
  - **OTRSP controller** (SO2R box) — `AUX<rig><code>`, BCD for the band decoder,
  - optionally the **rig connector** through hamlib (`Y`), codes 1–4 = ANT1–ANT4
    (checkbox below the table).

## Rotator

Equivalent of the N1MM **Rotor** program, through hamlib **rotctld**:

1. start `rotctld -m <model> -r /dev/cu.usbserial-… -t 4533` (model from `rotctl -l`),
2. **"Nastavení → Antennas → Rotátor"** (Settings → Antennas → Rotator): host and
   port (empty host = no rotator),
3. **"Okno → Rotátor"** (Window → Rotator) shows the current azimuth (a needle,
   read every 2 s) and the azimuth to the callsign from the field (a second needle).

| Control | Action |
|---|---|
| **Alt+J** / button **"Na volačku"** (To callsign) | turn to the callsign from the field (otherwise the last QSO) |
| **Ctrl+Alt+J** / **"Dlouhá cesta"** (Long path) | the opposite direction |
| azimuth + **"Natočit"** (Turn) | to the entered azimuth |
| **Alt+L** / **"Stop"** | stop |

The azimuth to the callsign is calculated from the station locator ("Nastavení →
Stanice", Settings → Station) and the country position according to DXCC.

## Transverters

Equivalent of the N1MM **transverter offset**. **"Nastavení → Hardware →
Transvertory"** (Settings → Hardware → Transverters): name, IF range of the rig
(kHz) and offset (kHz); the checkbox turns it on.

- Example: 2 m through a 10 m rig: IF 28000–30000, offset 116000 → the rig on
  28,300 kHz = 144,300 kHz in the log, bandmap, Cabrillo and in spots.
- Tuning (click on a spot, QSY, band, split, VFO B) to 144,300 sends 28,300 to the rig.
- Frequencies outside the IF range of enabled transverters pass unchanged; a
  disabled transverter = the rig behaves normally (10 m is 10 m again).

## Footswitch

Equivalent of the N1MM **Footswitch**. The switch is connected to a USB-RS232
converter between an output and an input control line: **RTS→CTS** (or DTR→DSR,
DCD). **"Nastavení → Hardware → Nožní spínač"** (Settings → Hardware → Footswitch):
port, line and action:

| Action | What it does |
|---|---|
| **PTT** | holds the transmitter (CAT PTT) while pressed — phone without VOX |
| **ENTER** | like Enter in the active entry window (with ESM it sends a message according to the state) |
| **F1** | sends CQ (F1) |

The input is read every 20 ms with debouncing.

### Rotator over UDP

For rotator programs with the **N1MM Rotor** protocol (PstRotator, ARSVCOM, N1MM
Rotor) — **"Nastavení → Antennas → Rotátor přes UDP"** (Settings → Antennas →
Rotator over UDP): host, port (default 12040) and rotator name. Alt+J / Ctrl+Alt+J /
Alt+L and the buttons of the Rotator window then send

```
<N1MMRotor><rotor>Yagi 20</rotor><goazi>330.0</goazi><offset>0</offset><bidirectional>0</bidirectional><freqband>14</freqband></N1MMRotor>
<N1MMRotor><stop>Yagi 20</stop></N1MMRotor>
```

UDP can run alongside rotctld; without rotctld the current position is not read
(the window shows only the direction to the callsign).
