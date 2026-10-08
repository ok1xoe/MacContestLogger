# Voice keyer (DVK) for SSB

In phone modes (SSB, AM, FM) the function keys F1–F12 transmit recorded voice
messages: the keyer keys the transmitter, plays wav files into its input and
unkeys. The behavior follows N1MM+
([Function Keys – SSB](https://n1mmwp.hamdocs.com/setup/function-keys/#Recording_on_the_Fly))
and DXLog
([Digital Voice Keyer](https://dxlog.net/docs/index.php?title=Menu_Options#Digital_Voice_Keyer)).

## Settings

**"Nastavení → Audio"** (Settings → Audio)
- **Output (transmitter):** the audio device that leads to the transmitter input,
  typically the "USB Audio CODEC" of the rig or interface.
- **Input (recording):** the microphone used to record messages.
- **PTT via CAT:** keying is done with the rigctld command `T 1` / `T 0`; the
  transceiver must be connected. Without CAT, or with the option turned off, the
  transmitter's VOX does the keying.
- **PTT delay:** how many milliseconds after keying the audio starts, so the relay
  has time to switch. The default is 150 ms.
- **Max. recording length:** a safeguard that ends a forgotten recording by itself.
- **Wav directory:** an empty field means `~/Library/Application Support/MacContestLogger/wav`.
- **Letters and digits:** subdirectory for announcing the callsign and numbers,
  the default is `LettersFiles/{OPERATOR}`.

**"Nastavení → Function Keys"** (Settings → Function Keys): messages F1–F12, a
separate set for **Run** and for **S&P**. Which set is used is determined by the
Run/S&P switch in the entry window. The button "Výchozí zprávy" (Default messages)
restores the set according to the N1MM "SSB Default Messages".

## Message format

A message is a comma-separated list of items (just like in N1MM `.mc` files):

| Item | Meaning |
|---|---|
| `{OPERATOR}/CQ.wav` | wav file relative to the wav directory. `{OPERATOR}` (also `{WAVDIR}`) is replaced by the callsign of the operator at the keyer, so after `OPON` recordings in his or her voice are played |
| `a.wav,b.wav` | several files in a row |
| `!` | the other station's callsign from the callsign field |
| `#` | sent serial number |
| `*` or `{MYCALL}` | my callsign |
| `@` | frequency in kHz |
| empty message / `empty.wav` | transmits nothing |

Example exchange for CQ WPX: `{OPERATOR}/59.wav,#`, that is, the recorded "five
nine" followed by the announced serial number.

For the macros `!`, `#`, `*` and `@`, the callsign and numbers are assembled from
recordings in the letters directory:
- `A.wav`...`Z.wav` and `0.wav`...`9.wav` for individual letters and digits;
- `stroke.wav` for "/", `query.wav` for "?", `point.wav` for the decimal point;
- `strokep.wav` for "/P" (optional).

A recorded snippet takes precedence over individual letters, for example
`DL1.wav` + A + B + C for the callsign DL1ABC. Therefore do not name message wav
files in a way that could appear inside a callsign. Something like `CQ_RUN.wav`
instead of `CQ.wav` works well.

If a message has a missing file, the keyer still transmits it without the missing
parts. The missing files are listed in the status line.

## Recording and choosing messages in Settings

In **"Nastavení → Function Keys"** with the **SSB** set shown, every key whose message is exactly one wav file
(for example `cq.wav` or `{OPERATOR}/CQ.wav`) has a line with the file it plays (name and length, or "file
missing") and these buttons:

- **Nahrát** (Record): records from the input device set in Settings → Audio, the same one Ctrl+Shift+F uses; the
  button turns into **● Stop** with the elapsed seconds. The recording ends by itself after the "Max. recording
  length" of the Audio tab, at most 60 s. It is saved as 16-bit mono 22,050 Hz and replaces the file only when it
  ends successfully. The first time, macOS asks for microphone access; if it is denied, allow it in System
  Settings → Privacy & Security → Microphone.
- **Přehrát** (Play): plays the file on the computer's default output so you can check it. It never keys the rig
  and never uses the keyer's output device.
- **Vybrat WAV…** (Choose WAV): copies an audio file from disk to the key's file (the original is not referenced,
  so moving or backing up the wav folder keeps working). A wav the keyer can play (PCM, float, A-law or μ-law,
  mono or stereo, 4–192 kHz) is copied unchanged; AIFF, CAF, MP3, M4A and other wav files are converted to
  16-bit mono 22,050 Hz wav. Files over 64 MB, longer than 5 minutes, silent or in an unknown format are refused
  with a message.
- **Smazat** (Delete): deletes the file after confirmation.

Recording over, or copying over, an existing file asks for confirmation first. All buttons are refused while
the voice keyer plays or records or a CW or digital message is being sent, and the keyer's F-keys are refused while
a message is recorded in Settings.

**Where the files go:** exactly where the voice keyer looks for them. The path is the message text resolved
against the wav directory (`{OPERATOR}` replaced by the operator's callsign, a relative path under the wav
directory, a missing folder created), using the same rule as Ctrl+Shift+F. It is taken from the texts and the
"Wav directory" shown in the dialog, so a file recorded before pressing "Použít" already lies where the keyer will
look after it. **Otevřít složku ve Finderu** opens the wav directory.

A key is not offered for recording when its message is empty, has several items (`a.wav,b.wav`), is speech
(`[text]`), or is a macro (`!`, `#`, `*`, `@`, `{MYCALL}`, control macros such as `{WIPE}`, `{LOG}`, `{RUN}`); the
line says why. `{OPERATOR}` needs an operator callsign (command `OPON`).

## Controls

| Key | Action |
|---|---|
| **F1–F12** or click on the button | sends the message. A new press interrupts the running message |
| **Esc** | stops transmission. Only the next Esc clears the fields (like N1MM) |
| **Ctrl+Shift+F1...F12** | starts recording the key's message into its wav file; another press or Esc saves the recording |

Only a message with a single wav file can be recorded ("Recording on the Fly" in
N1MM). The recording is saved as 16-bit mono 22,050 Hz and overwrites the original
file only after it completes successfully.

The button of the message currently being transmitted lights up in the grid, and a
message being recorded shows ●. In CW the F-keys transmit with the CW keyer (see
[cw-keyer.md](cw-keyer.md)); in digital modes they are disabled for now.

**macOS:** when the F-keys control brightness or volume, hold **fn**, or turn on
System Settings → Keyboard → "Use F1, F2, etc. keys as standard function keys".

## Not available yet

- automatic CQ repeat (N1MM Alt+R),
- a voice keyer built into the rig or into microHAM,
- recording the entire contest,
- text-to-speech.

## Speech synthesis (TTS)

Equivalent of N1MM **Text-to-speech** (Piper / SAPI) — on the Mac through the
built-in `say`. An item in **square brackets** in an F-key message is spoken:

```
[CQ contest *], cq-end.wav
[! five nine #]
```

- `*` my callsign, `!` callsign from the field, `#` serial number, `@` frequency —
  callsigns and numbers are spelled with the NATO alphabet (Oscar Kilo One...),
- the voice is chosen in **"Nastavení → Audio → Syntéza řeči"** (Settings → Audio →
  Speech synthesis), e.g. `Daniel`, `Samantha`, Czech `Zuzana`; list them with
  `say -v ?` in Terminal,
- spoken messages are stored in `.tts-cache` in the wav directory — the first
  playback takes about a second, later ones come from the cache,
- do not use a comma inside `[...]` (it separates message items); TTS can be
  combined with recorded wav files.
