# Digital modes

## fldigi as a modem (RTTY, PSK...)

MCL has no built-in audio modem for transmitting — like N1MM with fldigi, it
leaves modulation/demodulation to **fldigi** and controls it through its XML-RPC
interface.

1. Start fldigi (XML-RPC is enabled by default on port **7362**).
2. In MCL: **"Nastavení → Digitální módy → Modem pro RTTY / PSK → fldigi"**
   (Settings → Digital modes → Modem for RTTY / PSK → fldigi), enter the address
   and port and click **"Vyzkoušet"** (Test; it shows the fldigi version and the
   current modem).
3. The F1–F12 messages for digital modes are in **"Nastavení → Function Keys →
   Digi"** (Settings → Function Keys → Digi), separately for Run and S&P (macros
   as for CW: `*`/`{MYCALL}`, `!`, `#`, `{SENTRST}`, `{EXCH}`, `{LOG}`,
   `{WIPE}`...; numbers are not shortened).

In RTTY/PSK/... mode the F-keys then transmit through fldigi (text into the TX
buffer, TX on, and after sending fldigi switches to receive by itself). ESM and CQ
repeat work; **Esc** interrupts transmission (`main.abort`).

## Frequency and mode (fldigi)

- **AutoTRXUpdate** (N1MM; Settings → Digital modes, or the window's **Nastavení** menu; on by default):
  with the rig in a sideband mode (USB/LSB, PKTUSB/PKTLSB, DATA-U/L) the dial shows the suppressed
  carrier, so the QSO is **logged and spotted** on the dial ± fldigi's audio frequency (USB adds,
  LSB subtracts; read with `modem.get_carrier`). In FSK RTTY (rig mode RTTY/RTTYR) the dial already
  is the mark frequency and nothing is added. As in N1MM it applies only while the Digital interface
  window is open (that is when the audio frequency is polled) and only in a digital mode; a
  frequency typed into the field that differs from the dial is logged as typed. The entry window's
  frequency field keeps showing the dial.
- The window's top bar shows the **exact frequency** (dial ± audio) and the audio frequency, e.g.
  `14082.13 kHz · 2125 Hz`.
- **Mód** (N1MM *Op Mode*) lists fldigi's modems (`modem.get_names`; RTTY, BPSK31/63/125, QPSK and CW
  first, the rest under *Další módy*). Choosing one switches fldigi (`modem.set_by_name`); an RTTY or
  PSK modem also puts the entry window into RTTY or PSK.
- Typing **RTTY** or **PSK** (PSK31, PSK63…) into the callsign field switches the logger **and fldigi**:
  to the modems set in **Settings → Digital modes → fldigi mode for RTTY / PSK** (default `RTTY` and
  `BPSK31`).
- Macros `{LDIGFQ}` and `{RDIGFQ}` send the frequency of the left (VFO A / rig 1) and right (VFO B /
  rig 2) side in kHz with one decimal (dial ± audio as above), e.g. `QSY {LDIGFQ}`.

## The Digital interface window

**"Okna → Digitální rozhraní"** (Windows → Digital interface) — the equivalent of
N1MM *Digital Interface*. MCL pulls the decoded text from fldigi and draws it
**in its own window**, so you can work with it directly:

![Digital interface with decoded RTTY; callsigns and exchange words are underlined](img/digital-interface.png)

- **A click on a callsign puts it into the callsign field** (your own callsign is
  not underlined). You do not click in fldigi — XML-RPC has no "user clicked on a
  word" feature, so there is no path back from there. That is why the text must
  be in the logger's window, as in N1MM.
- **A click on an otherwise underlined word puts it into the exchange.** Where it
  belongs is decided by the contest definition: first the `validation` from the
  YAML (range, length, regex), then the shape according to the field type. In CQ
  WW RTTY, `599` goes into the report and `15` into the zone — it cannot land in
  the report because RST has three digits. Of several matching fields, **the first
  empty one** wins, so a partly filled exchange is not overwritten by a click as
  long as there is somewhere else to write. A word that fits nowhere is not underlined.
- **A double exchange is recognized as a whole.** Fields are assigned by the
  callsign **on the same line**, not by the one being typed — the exchange belongs
  to the station that sent it. In CQ WW RTTY, for `W3LPL 599 05 NY` both the zone
  **and** the state are highlighted, whereas for `DL1ABC 599 14` only the zone is,
  because only W/VE stations send a state. You click into both fields separately.
- Above the text is a **callsign list** in the order in which the callsigns
  appeared. The order is never rearranged — otherwise it would change under the
  cursor in a pileup and a click would hit the wrong callsign.
- The top bar shows the **modem and the TX/RX state** and a **"Vymazat"** (Clear)
  button (it clears only the window; the RX buffer in fldigi stays, so the text
  does not start being read again).
- **F1–F12, Enter and Esc work here too.** After clicking a callsign the keyboard
  stays in this window, so otherwise you could not fire F4 (callsign) or F2
  (exchange) right away. The keys are sent to the entry window, where all the
  logic lives: **Shift+F** takes the message from the opposite set (Run ↔ S&P),
  **Enter** performs an ESM step or logs the QSO, and **Esc** stops transmission.
  Focus stays in the window, so from one place you can pick a callsign, send the
  exchange and log the QSO.

## The receive window (N1MM Digital Interface)

**Mouse** (macOS keys for N1MM's — Ctrl+click is the system's secondary click):

| Mouse | Action |
|---|---|
| click on a callsign | into the callsign field (an exchange word into its field, as above) |
| **Option+click** | the callsign onto the [call stack](call-stacking.md) (N1MM Alt+click) |
| **Cmd+click** | the word under the pointer into the entry field that has the typing cursor, whatever it is (N1MM Ctrl+click) |
| **Shift+click** | the word converted Letters ↔ Figures (RTTY: `TOO` → `599`, `UE` → `73`), then into the callsign field (a callsign), its exchange field, or the field with the cursor |
| **right click** (or Ctrl+click) | with *Pravý klik = Enter (ESM)* it is Enter — a whole QSO can be run with the mouse (N1MM "Rt Click = Return NOT menu"); otherwise the text's menu |

Below the text the **Pod myší** (MouseOver) and **Letters/Figs** indicators show the word under the
pointer and its other-shift reading.

**Colours.** Callsigns are coloured like in the bandmap: by dupe and the number of new multipliers at
the active entry window's frequency and mode. *Ověřování volaček* (N1MM Callsign Validity) in the
**Nastavení** menu chooses: *Vše, co vypadá jako volačka* (generic), *Jen volačky ze zdrojů* (only
calls found in the chosen resources are highlighted and clickable) or *Obojí, neověřené žlutě*
(default: generic, and a callsign that none of the resources knows gets a **yellow** background).
The resources are Master.scp, the call history, the spots of the DX cluster and the callsigns in the
log. *Barva volačky jako pozadí* puts the colour behind the callsign (the unverified mark then
becomes yellow text). *Hledat volačky z Master.scp i v šumu* also finds a known callsign inside a
word that is not a callsign itself (`EEEEW1AWEEEE`); of several, the last one wins.

**Your own transmission.** Text that fldigi returns while it transmits (the echo of your message) is
shown dimmed, and its callsigns never go to the callsign list (N1MM: calls are not grabbed during
transmission).

**Pause.** The green bar left of the text pauses the window (it turns yellow): new text is held back
— fldigi is still read and the callsign list still fills — until the bar is clicked again, so you
can scroll back and click calmly. With *Pozastavit příjem nad volačkou* the pointer over a callsign
pauses the window by itself while the callsign field is empty (N1MM pause routines).

**More options** in **Nastavení**: *Hover* (a callsign under the pointer goes into the callsign field
without a click), *Po kliku na volačku kurzor do výměny* (N1MM "Send Space on Callsign Mouse Click"),
*Neposuvné okno příjmu* (N1MM non-scrolling window: the text on screen never moves; when the incoming
line reaches the bottom the window turns a page so the newest line is at the top, and the incoming
line is underlined) and *V titulku frekvence rigu, ne přesná* (the caption and `{LDIGFQ}`/`{RDIGFQ}`
show the dial instead of dial ± audio).

## The Grab window

The row above the text is N1MM's **Grab window**: the last 10 callsigns recognised in the received
text, the one to be grabbed next highlighted. Not added: your own callsign, the callsign already in
the callsign field, text received while you transmit, and (options in **Nastavení → Grab okno**)
dupes (*Dupy do Grab okna nedávat*, on by default) or callsigns missing from Master.scp. A callsign
taken from the text by a click leaves the list. Only callsigns new since the last read and already
followed by more text are added, so a cleared list does not fill again from old text.

| Key / control | Action |
|---|---|
| **Grab** button, **Alt+G**, `{GRAB}` | the highlighted callsign into a wiped entry window (it leaves the list). In CW/SSB, or with an empty list, Alt+G takes the next callsign of the [call stack](call-stacking.md) instead |
| a click on a callsign in the row | that callsign into the callsign field |
| **CLR** | clears the list |
| right click on a callsign | select it, delete it, clear the list, sort order **LIFO** (newest first, default) or **FIFO** |
| **Insert** (the Help key on a Mac keyboard; also remappable) | with an empty callsign field grabs the highlighted callsign, then sends his call + exchange (F5+F2); with ESM in S&P first F4 until the exchange is entered; a dupe sends F6 in Run (or F5+F2 with *Work dupes*) and nothing without ESM — N1MM's Insert table; the cursor goes to the exchange |
| `{LOGTHENGRAB}` (Run only) | as [`{LOGTHENPOP}`](call-stacking.md#logthenpop-log-and-go-on), with the next callsign taken from the Grab window: `! {LOGTHENGRAB} TU {F5}{F2}`. With an empty list the QSO is logged and the TU message is sent. ESM never chooses this key by itself — use it on its own key (N1MM: do not put it into the TU or Next Call key) |
| `{DELALL}` / `{DELTOP}` / `{DELSEL}` | delete the whole list / its top / the highlighted callsign |
| `{SCQ}` | resume CQ: turns the CQ repeat on (Run) — place it at the end of the TU message |

More options in **Nastavení → Grab okno**: *QSY vymaže Grab okno* (a frequency change of more than
500 Hz clears the list), *CQ vymaže Grab okno* (sending F1 clears it), *Po grabu kurzor do výměny*
(N1MM "Send Space on Using Grab") and *Při grabu dát volačku z pole do bandmapy* (the callsign that a
grab replaces is stored in the bandmap first, as Alt+O).

With Digital Call Stacking on (Run), Alt+G also puts the callsign that was in the field onto the call
stack, and **Ctrl+Alt+G** moves the highlighted Grab callsign onto the stack without touching the
field.

## Call stacking

**Option+click** (N1MM Alt+click) on a callsign, in the text or in the callsign list, puts it on the
[call stack](call-stacking.md) without touching the callsign field. The window's **Nastavení**
(Setup) menu has N1MM's **Digital Call Stacking**: *Vypnuto* (off), *FIFO*, *LIFO* or *FIFO, násobiče
napřed* (mults first). When it is on and you are in **Run** with a callsign already in the field, a
plain click on another callsign stacks one of them instead of replacing the field: FIFO stacks the
clicked callsign, LIFO stacks the callsign from the field and puts the clicked one in. A
`{LOGTHENPOP}` key (for example `! {LOGTHENPOP} TU {F5}{F2}`, also as the ESM Next Call key) then
works the stacked stations one after the other.

Reading is **incremental**: MCL asks for the length of the RX buffer
(`text.get_rx_length`) and fetches only what it does not have yet (`text.get_rx`).
If you clear the buffer in fldigi, this is detected by the shortening and reading
starts from the beginning, but the history in the window stays. The polling
interval is 300 ms — compared with MMTTY embedded directly in N1MM, the text lags
by that fraction of a second.

Who decodes does not change: the modem is still fldigi. MCL has its own RTTY
decoder only in the separate proof of concept `digimode-poc`.

## Sharing CAT with fldigi

When MCL controls the rig, its `rigctld` holds the serial port and fldigi **will
not open it**. In fldigi, therefore, set **Configure → Rig Control → Hamlib**, rig
**Hamlib NET rigctl** and device `localhost:4532` — both programs then talk to one
daemon. Leave PTT on "PTT via Hamlib command"; RTS/DTR cannot be used on that
port, and for rigs with hardware handshake (e.g. TS-590SG over USB) hamlib rejects
them.

In the **"Spustit rigctld"** (Start rigctld) mode, however, the daemon is a
subprocess of MCL, so when the application quits it ends too and fldigi loses the
connection (only "Initialize" in its rig control settings helps). Anyone who runs
digital modes regularly should **start the daemon themselves** and choose
**"Připojit k běžícímu"** (Connect to running) in **"Nastavení → Hardware →
Připojení"** (Settings → Hardware → Connection):

```bash
rigctld -m <model> -r <zařízení> -s <rychlost> -t 4532
```

Restarting MCL then does not upset fldigi. On macOS this can be hung on a launchd
agent (`~/Library/LaunchAgents`) so that the daemon starts by itself after login.
