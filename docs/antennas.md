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
| **Rotátory** (Rotors) | N1MM *Rotor Description*: the rotor(s) turning the antenna, by name; several separated by commas turn a **stack** together; empty = the default rotator |
| **Offset** | degrees the main lobe points away from the rotor heading (the rotor turns to bearing − offset) |
| **Obousm.** (Bidirectional) | a SteppIR or a dipole: the rotor uses whichever end of the beam is nearer, so it turns at most 180° |

A rotor name the setup does not know (see [Several rotors](#several-rotors-presets-and-limits)) is a rotor of the
rotor program: Alt+J sends it the N1MM Rotor UDP message with that name, the offset and the bidirectional flag.

## Switching

- After a **band change** the antenna for that band is selected; if the band has
  several antennas, the **azimuth** to the callsign being typed decides (the
  antenna whose sector it points into), otherwise the first in the table.
- A **bidirectional** antenna's sector also covers its back end (a fixed dipole broadside `30-90` serves 210–270 too).
- **Automatic choice by bearing** (N1MM *Auto-select antenna based on azimuth*, off by default): with
  **"Vybírat anténu podle směru ke stanici i po zadání volačky"** checked below the table, Space in the call field
  chooses the band's antenna again by the bearing to the typed station — handy with fixed directional antennas.
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
| **Alt+L** / **"Dlouhá cesta"** (Long path) | the opposite direction |
| azimuth + **"Natočit"** (Turn) | to the entered azimuth |
| **Ctrl+Alt+J** / **"Stop"** | stop |

The azimuth to the callsign is calculated from the station locator ("Nastavení →
Stanice", Settings → Station) and the country position according to DXCC. When the
station's **grid** is known — the contest's grid field (VHF) or the call history — the
bearing goes from your grid to that grid instead.

- **A heading in the call field**: type a number 0–360 in the call field and press
  **Alt+J** — the rotor turns to that heading (the long-path key adds 180°).
- **Band map and Available**: right click on a spot → **"Natočit rotátor na …"**
  (N1MM *Turn Rotor*); the spot's grid is used when known (spot comment, grid
  database, callbook).
- With an antenna chosen, a turn applies its rotor(s), offset and bidirectional flag
  (see the antenna table above).

### Several rotors, presets and limits

Equivalent of the **N1MM Rotor** program's setup: **"Nastavení rotátoru…"** (Rotor setup) in the
Rotator window's top bar.

| Part | Meaning |
|---|---|
| **Rotátory** (Rotors) | up to 16 named rotors: name, rotctld host and port (empty host = only the UDP message with this name), **calibration** (degrees added to the position read; taken off what is sent) and the controller's **limits** (Min/Max: `0–360`; `0–450` for an overlap rotor, which then takes the shorter turn; `-180–180` for a south stop; a limited range turns to the nearer limit and says so) |
| **Předvolby F1–F10** (Presets) | bearings of the ten preset buttons; with the Rotator window active, **F1–F10** press them |
| **Rotátory ze sítě** (Network rotors) | off by default; shows the headings broadcast by N1MM Rotor on the network (UDP port 13010, lines `<rotor> @ <tenths of a degree>`); only receives |

With named rotors the Rotator window gets a **rotor picker**: the compass, the field, the
presets and Stop work on the picked rotor. Stop also stops the current antenna's rotors.

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
| **F2**, **F3**, **F4**, **F11**, **F12** | sends that function key's message |
| **ESC** | stops sending, like Esc (the CQ repeat goes off too) |
| **SWITCH_RADIOS** | SO2V / SO2R: moves the entry (RX) focus to the other entry window, like `\` (N1MM "Typing Focus"; in SO2R the transmit focus follows with the next message sent from that window) |

The input is read every 20 ms with debouncing. In a multi-op network the footswitch PTT obeys
the [interlock](multi-op.md) like every other transmission, which covers N1MM's "First One Wins"
(the default) and "Band lockout" (interlock scope "same band"); a hardware lockout line wired to
the footswitch input is not supported.

### Rotator over UDP

For rotator programs with the **N1MM Rotor** protocol (PstRotator, ARSVCOM, N1MM
Rotor) — **"Nastavení → Antennas → Rotátor přes UDP"** (Settings → Antennas →
Rotator over UDP): host, port (default 12040) and rotator name. Alt+J / Alt+L /
Ctrl+Alt+J and the buttons of the Rotator window then send

```
<N1MMRotor><rotor>Yagi 20</rotor><goazi>330.0</goazi><offset>0</offset><bidirectional>0</bidirectional><freqband>14</freqband></N1MMRotor>
<N1MMRotor><stop>Yagi 20</stop></N1MMRotor>
```

UDP can run alongside rotctld; without rotctld the current position is not read
(the window shows only the direction to the callsign).
