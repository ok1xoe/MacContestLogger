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
  tuning, split, RIT and spots go to the rig of the window with the **entry focus**.
- **Two foci, as in N1MM.** The **entry (RX) focus** — the green LED in the window's top row — is the window you
  type in (and, with an OTRSP box, the radio in your headphones). The **transmit focus** — the red LED, orange while
  transmitting — is the radio the keyer, the voice keyer, the paddle, the footswitch PTT and a plugin's PTT key.
  `\` and a click into a window move only the entry focus; an F-key, ESM Enter, `;`, `'`, typed CW (Ctrl+K) or
  Ctrl+T sent from a window first move the transmit focus there. So you can type a call on the S&P radio while the
  CQ still goes out on the run radio, and pressing Enter sends on the S&P radio.
- **OTRSP controller** (serial port in Settings): the entry focus sends `RX1`/`RX2` (stereo `RX1S`/`RX2S`), the
  transmit focus `TX1`/`TX2`.
- **Radio swap times** (Nastavení → SO2R, N1MM Config → SO2R): the *tail time* delays the switch to the other radio
  after a transmission you interrupted there (an aborted CQ), the *lead time* is the pause between the switch and the
  first keying (station accessories see the change). Both default to 0 ms and apply to CW and voice messages.
- **Winkeyer second output** (Nastavení → SO2R → *Winkeyer: rádio 2 na druhém výstupu*): radio 1 is keyed on
  KEY OUT 1, radio 2 on KEY OUT 2 (WinKeyer 2 and later); the pin configuration follows the transmit focus before
  each message. Without it both radios share KEY OUT 1 and the SO2R box switches the key line.
- In SO2R the sent CW is always echoed in the status line with its radio (`CW R2: …`), as N1MM does.

| Key | Action |
|---|---|
| **\\** | the entry (RX) focus to the other window (rig / VFO) — N1MM "\\"; in SO2R the transmit focus stays |
| **Pause** (**F15** on a Mac) | both foci to the other window; when they are split, the transmit focus joins the entry focus |
| **Cmd+Alt+← / →** | both foci to VFO A / rig 1 or VFO B / rig 2 (N1MM Ctrl+←/→); in a digital mode with its Digital Interface |
| **Ctrl+F1 … F12** | the other window's F-key message, sent on its radio; the entry focus stays here (N1MM Ctrl+Fn) |
| **Ctrl+Enter** | the other window's next ESM step on its radio (with ESM on; a frequency in the call field still sets split) |
| **Alt+F5** | frequency, mode and call swapped between the radios (SO2R) or VFOs (SO2V); the entry focus moves to the other window |
| **Alt+F6** | SO2R: the same swap, the focus stays |
| **`** | SO2R stereo listening on / off |
| **Ctrl+B** | SO2R: Dueling CQs on / off |
| **Ctrl+Shift+K** | SO2R: FocusOther on / off |
| **Ctrl+Shift+L** | the `{CTRLFx}` macro on / off |
| **Ctrl+`** | the stereo / OTRSP RX macros on / off |

All of them can be remapped in "Nastavení → Klávesy" (Settings → Keys), except Ctrl+F1–F12 and Ctrl+Enter, which
follow the F-keys and Enter. macOS keeps some Control+F-key combinations for keyboard navigation (System Settings →
Keyboard → Keyboard Shortcuts → Keyboard); turn those off to use Ctrl+F1–F8. A PC keyboard's Pause key reaches a Mac
as F15. In SO2V one rig has one transmitter, so both foci always sit in the same window: Ctrl+F1–F12 make the other
VFO active for the message and come back once it has been sent when this window's call field holds a call.

## Nastavení → SO2R (N1MM Config → SO2R)

The options are remembered between runs ("sticky", as in N1MM).

- **Dueling CQ** (Ctrl+B): the CQ key (F1, or the ESM CQ key) goes out on one radio, and when it has been sent and
  the *Pauza Dueling CQ* (default 100 ms) is over, on the other one — alternately, starting on the radio with the entry
  focus; both radios are run radios. A call typed in either window pauses it, clearing it resumes it. It ends with
  Esc, Ctrl+B, either radio moving more than 200 Hz, a failed send, the network TX lockout, post-contest entry and
  the CQ repeat's maximum duration ("Max Repeat / Dueling CQ duration"). It never starts by itself.
- **FocusOther — fokus na druhé rádio** (Ctrl+Shift+K): while the run radio (the one that sent the last CQ)
  transmits, the entry focus moves to the other radio, so you can type the call heard there; when the run radio
  stops, the focus returns — unless an unworked call has been typed in the S&P window. **FocusOther: vždy přepnout**
  (Always Swap): every transmission moves the focus to the other radio and back, whatever was typed.
- **Makro {CTRLFx}** (Ctrl+Shift+L): off = `{CTRLF1}`…`{CTRLF12}` in the messages are ignored.
- **Makra stereo / OTRSP RX** (Ctrl+`): off = `{STEREOON}`, `{STEREOOFF}`, `{OTRSP RX}` and `{OTRSPOTHER RX}` are
  ignored (e.g. while you use only one entry window for a while).
- **Čas po vysílání / Předstih při přepnutí rádia** and **Winkeyer: rádio 2 na druhém výstupu** — see above.
- **SO2V: zápis do okna VFO B ukončí opakované CQ** (N1MM "Repeating CQ Ends With VFOB Window Entry"): typing a call
  in the VFO B window switches the CQ repeat off.

In SO2R the CQ repeat (Alt+R) stays on the radio it was switched on in, so the run radio keeps calling CQ while you
type on the S&P radio.

In digital modes each entry window can have its own Digital Interface and fldigi — see
[Digital modes → SO2V / SO2R](digital-modes.md#so2v--so2r-two-digital-interfaces).
