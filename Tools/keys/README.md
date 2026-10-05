# Mac key table (`Tools/keys/`)

`extract_mac_keytable.sh` turns the native macOS key table of JDK 21 — `keyTable` in
`src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m` of OpenJDK, tag `jdk-21+35` — into
`Tests/MCLCoreTests/Fixtures/awt-mac-keycodes-jdk21.tsv`: per `kVK` (0x00–0x7F) the `VK_*` name and its
value, the values resolved through the committed fixture `awt-vk-codes-jdk21.tsv`.
The source file is read once and not kept in the repository; the header of the fixture records its SHA-256.
Licence note: `THIRD_PARTY_NOTICES.md`.

```bash
curl -sSfLo AWTEvent.m \
  'https://raw.githubusercontent.com/openjdk/jdk/jdk-21%2B35/src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m'
sh Tools/keys/extract_mac_keytable.sh AWTEvent.m   # `git diff` must be empty
```

`AwtKeyCodesMacTests` compares `AwtKeyCodes.fromMac` with the fixture for all 128 values.

## Character branch and modifier keys (`keys/`, P9b)

The JDK maps keys that type a letter or a digit by the typed character before it consults the table
(`NsCharToJavaVirtualKeyCode`), and modifier keys arrive as `flagsChanged` (`NsKeyModifiersToJavaKeyInfo`).
`extract_mac_chars.sh` reads the same `AWTEvent.m` (same SHA-256) into
`Tests/MCLCoreTests/Fixtures/awt-mac-chars-jdk21.tsv`: the `keyTable` locations (`LOCATION`), the dead-key
table (`DEAD`), the modifier-key table (`MODIFIER`) and the constants of the letter/digit rules (`RULE`, read
by hand; the script refuses any file other than the one with the recorded SHA-256). The header records which `NSEvent` fields the JDK uses,
read from `sun.lwawt.macosx.CPlatformResponder.handleKeyEvent` in the JDK 21.0.2 `lib/src.zip`.

```bash
sh Tools/keys/extract_mac_chars.sh AWTEvent.m   # `git diff` must be empty
```

`AwtKeyTranslateTests` checks `AwtKeyCodes.translate` against the fixture and on Czech, German, French and
US layouts; `EntryKeyRouterTests` checks the entry key routing on the translated events.
