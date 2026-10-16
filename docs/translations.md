# Translations of the user interface (for maintainers)

The texts of the user interface are written in Czech in the code and translated when they are shown: the key is the
Czech text, the translation is in `Sources/MCLCore/Resources/i18n/lang_en.json` and `lang_de.json`. A text without a
translation stays Czech, so every text the user can see has to reach the screen through the translator:

- in a view `language.tr("…")` (or `app.language.tr`), with values `language.tr("%s QSO", .int(n))`;
- in the core and the models `ContestMessage("…")`, `EntryStatus.tr("…")`, `status.show("…")` or
  `translator.translate("…")`, translated where the text is shown;
- never `Text(verbatim: "…")`, `Button("…")`, `.help("…")` and the like with a Czech literal, and never
  `.verbatim("…")` / `showVerbatim("…")` with Czech text (they are for exception messages, codes and data);
- never string interpolation inside the key (`tr("Nalezeno: \(n)")` is never found); use `%s` and a value.

A new key goes into both `lang_en.json` and `lang_de.json` (appended at the end), and the pins of the shipped files
change with it: the entry count in `TranslatorTests.bundledEnglishIsComplete` and the size, hash, count and digest in
`I18nMeasuredTests.shippedFileCells`. The failing tests print the new values.

## The audit

`SourceTranslationAuditTests` (MCLCoreTests, runs in CI) reads `Sources/MCLCore`, `Sources/MCLAppModel` and
`Sources/MacContestLogger` and fails when

- a literal key handed to the translator is missing in the English or German file, or is built with interpolation;
- a view shows a Czech literal without `tr` (`Text`, `Button`, `Label`, `Toggle`, `Picker`, `Menu`, `TextField`,
  `.help`, the accessibility labels, alerts, menu items, tooltips and the Settings form parts);
- a Czech literal is shown as is (`.verbatim`, `showVerbatim`).

A literal counts as Czech when it has Czech diacritics or when it is a key of `lang_en.json` whose English text is
different ("Smazat", "Celkem"), so English captions, codes and numbers are left alone. Exceptions (the alerts shown
before the language files can be loaded) are listed with their reason in the test.

The same rules, and a longer list for review, are in a script that needs nothing but Python 3:

    scripts/i18n-audit.py          # the findings of the test, exit status 1 when there are any
    scripts/i18n-audit.py --all    # plus every other Czech literal that is not a key (REVIEW)

The REVIEW lines are mostly error and log texts, file contents and data, but a text can also reach the screen
through a constant or a helper function (`numberField("…")`, a label in a table of options) that the rules cannot
see. Check where such a text is shown before translating it.

The rules do not see a Czech word without diacritics that is not a key yet ("Duplikovat…" in a button): look at the
windows in English too. `scripts/shots.sh --lang en` renders the guide's windows offscreen (see `screenshots.md`).
