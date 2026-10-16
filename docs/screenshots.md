# Screenshots of the user guide (for maintainers)

The guide exists in Czech and English, each with screenshots of the user interface in its own language:

- `docs/img/<name>.png`: the Czech screenshot (the Czech guide; also the English guide's fallback),
- `docs/img/en/<name>.png`: the English screenshot. When it is missing, the English guide uses the Czech one, says
  so in the caption ("Czech interface") and adds a note to its introduction.

The pages always reference `img/<name>.png` (`../img/<name>.png` from `docs/cs/`); `mcl-manual` picks the file of the
language.

## Capturing them from the running app (the images in the guide)

The images in `docs/img` and `docs/img/en` are captures of the real application with a demo contest running:

    scripts/bundle.sh --config release                               # build/app/MacContestLogger.app
    scripts/native-shots/shoot.py --lang cs --out docs/img           # Czech UI
    scripts/native-shots/shoot.py --lang en --out docs/img/en        # English UI
    scripts/native-shots/shoot.py --lang en --only rtty,multi-op     # some scenarios → build/native-shots/en

It needs an unlocked screen (windows are shown and captured with `screencapture -l <window id>`, so other windows
may overlap them without harm); it sends no input events. Each scenario in `scripts/native-shots/scenarios/*.json`
(the CQ WW CW station with most tool windows, RTTY, multi-op, WAE QTC, Settings + definition editor + merge,
the start-up dialog) does this:

- **Data** (never the user's): a data folder under `$MCL_SHOTS_WORK` (default `/tmp/mcl-demo`; the definition editor
  shows that path), the repository's `contest-data/`, a synthetic log written by `mcl-synthlog` (`--contest`,
  `--mode CW|SSB|RTTY`, `--gap`; its QSOs end at the time of the run, so the rate and the grey line look live) and a
  `config.json` with the fictitious station OK1DEMO in JO70FC, the windows that are open and their frames.
- **The app** runs through `scripts/smoke-run.py` (throwaway bundle id, `MCL_INERT_HARDWARE=1`, `MCL_INERT_NETWORK=1`)
  with `MCL_DEMO_DIR` pointing at a `demo.json`. The demo mode (`Sources/MCLAppModel/Demo/DemoMode.swift`) is honoured
  **only** together with both inert switches and replaces some inert ports:
  - demo rigs: an in-memory CAT session per radio at the frequency and mode of `demo.json` (no `rigctld`, no serial
    port, no socket); tuning and mode changes stay in memory;
  - demo receiver audio: a 12 kHz stereo WAV (left = RX1, right = RX2) played in a loop into the receiver input (no
    audio device): `rtty_wav.py` (AFSK RTTY stations, 45.45 Bd / 170 Hz) and `cw_wav.py` (CW stations);
  - the DX cluster telnet goes to `127.0.0.1:<clusterPort>` (`fake_cluster.py`: synthetic spots, a quarter of them
    calls of the log), the multi-op sync to a throwaway `mosquitto` on `127.0.0.1:<brokerPort>` with fictitious peer
    stations (`peers.py`: status heartbeats, a few shared QSOs, chat lines). Without these ports nothing connects; every
    other service (HTTP, UDP, plugins, downloads) stays inert.
  - scripted steps as the operator would do them: connecting the rigs and the cluster, text in the entry windows,
    Run/S&P, the active radio, menu items, a Settings tab, a definition in the editor, a merge, skeds, the CW keyboard
    text, the partner's runner, a QTC series being received, the built-in modem's XY scope and channels, the key
    window (`DemoMode.Action`).
- **Capture** at the scheduled seconds, by window title, without the shadow (`screencapture -o`), optionally cropped;
  the app is then quit (SIGTERM through `smoke-run.py`). The PNGs are recompressed losslessly (`pngopt.py`).

Check every image after a run (open it; the windows must show what the page describes) before committing.

## Rendering them offscreen

The screenshots are rendered from the application's own SwiftUI and AppKit views, **without a screen**: nothing is
shown, so the screen saver, a locked session or a headless machine do not matter, and the application is never
started. A test of the `MacContestLoggerTests` target (it imports the app target, like the layout tests) builds a demo
station and draws each window into a PNG:

    scripts/shots.sh --lang cs                         # every rendered screenshot, Czech UI → build/shots/cs/
    scripts/shots.sh --lang en --only bandmap,statistics --out build/shots-en

- **Demo data** (`Tests/MacContestLoggerTests/Screenshots/ShotDemo.swift`): a temporary data folder (never the user's),
  the repository's `contest-data/` and DXCC snapshot, station OK1DEMO (a fictitious call) in JO70FC, a CQ WW CW log of 40 QSOs on 40, 20 and
  15 m entered through the entry window, the rig tuned to 14025.00 kHz and a dozen cluster spots. The hardware and
  network ports are inert (no rig, serial port, audio device or socket is opened), the clock is fixed, periodic ticks
  never fire. The same input gives byte-identical images on the same macOS version.
- **Rendering** (`ShotRenderer.swift`): the window's view in an `NSHostingView` inside an `NSWindow` that is never
  ordered onto the screen, light appearance, the window size from the manifest, drawn with `cacheDisplay` at 2x
  (the guide shows the images at half their pixel size) including the window's title bar.
- **Manifest** (`docs/screenshots.json`): every image of `docs/img` with the window (`window`) and state it shows,
  the window size in points, the languages and whether the renderer can produce it already (`rendered`).
  `ScreenshotTests.theManifestCoversEveryImageOfTheGuide` (runs in CI) fails when an image or a page's image
  reference has no entry, or when a `rendered` entry names a window the renderer does not know.

Rendered so far: `bandmap`, `log-window`, `score-window`, `statistics`. The guide uses the native captures above;
the offscreen renderer is the deterministic alternative for windows it knows: add a case to `ShotRenderer.scene` that
prepares the state (opening the window's model, the demo data it needs) and returns the view, then set `rendered` in the
manifest.

## Differences from a real capture

- The window is not key: the title bar's buttons are grey and there is no focus ring.
- No window shadow or rounded corners; translucent materials are drawn flat. Tables are shown from their first row
  (a row scrolled under the floating table header would show through it offscreen).
- The menu bar, sheets, popovers and open menus are not part of a window's view and are not rendered.

## Updating the guide

The guide's images come from `scripts/native-shots/shoot.py` (above; `--out docs/img` and `--out docs/img/en`).
The offscreen renderer writes only to its output folder; copy its images into the guide only when it is decided to
replace the native captures of those windows:

    scripts/shots.sh --lang cs --out docs/img
    scripts/shots.sh --lang en --out docs/img/en

Check them (`git diff --stat docs/img`, open a few) and rebuild the guide (`swift run mcl-manual --lang en --out-dir
build/manual`, `--lang cs`).
