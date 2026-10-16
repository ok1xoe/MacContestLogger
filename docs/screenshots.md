# Screenshots of the user guide (for maintainers)

The guide exists in Czech and English, each with screenshots of the user interface in its own language:

- `docs/img/<name>.png`: the Czech screenshot (the Czech guide; also the English guide's fallback),
- `docs/img/en/<name>.png`: the English screenshot. When it is missing, the English guide uses the Czech one, says
  so in the caption ("Czech interface") and adds a note to its introduction.

The pages always reference `img/<name>.png` (`../img/<name>.png` from `docs/cs/`); `mcl-manual` picks the file of the
language.

## Rendering them offscreen

The screenshots are rendered from the application's own SwiftUI and AppKit views, **without a screen**: nothing is
shown, so the screen saver, a locked session or a headless machine do not matter, and the application is never
started. A test of the `MacContestLoggerTests` target (it imports the app target, like the layout tests) builds a demo
station and draws each window into a PNG:

    scripts/shots.sh --lang cs                         # every rendered screenshot, Czech UI → build/shots/cs/
    scripts/shots.sh --lang en --only bandmap,statistics --out build/shots-en

- **Demo data** (`Tests/MacContestLoggerTests/Screenshots/ShotDemo.swift`): a temporary data folder (never the user's),
  the repository's `contest-data/` and DXCC snapshot, station OK1XOE in JO70FD, a CQ WW CW log of 40 QSOs on 40, 20 and
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

Rendered so far: `bandmap`, `log-window`, `score-window`, `statistics`. The others are the older captures
(partly from the Java version) until the renderer learns their windows: add a case to `ShotRenderer.scene` that
prepares the state (opening the window's model, the demo data it needs) and returns the view, then set `rendered` in the
manifest.

## Differences from a real capture

- The window is not key: the title bar's buttons are grey and there is no focus ring.
- No window shadow or rounded corners; translucent materials are drawn flat. Tables are shown from their first row
  (a row scrolled under the floating table header would show through it offscreen).
- The menu bar, sheets, popovers and open menus are not part of a window's view and are not rendered.

## Updating the guide

Rendering writes only to the output folder. Copy the images into the guide only when it is decided to replace them:

    scripts/shots.sh --lang cs --out docs/img
    scripts/shots.sh --lang en --out docs/img/en

Check them (`git diff --stat docs/img`, open a few) and rebuild the guide (`swift run mcl-manual --lang en --out-dir
build/manual`, `--lang cs`).
