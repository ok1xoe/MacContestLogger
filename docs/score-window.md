# Score window

![Score window](img/score-window.png)

An equivalent of N1MM+ **Score Summary**
([Score Window](https://n1mmwp.hamdocs.com/manual-windows/score-window/)) and DXLog
**Summary**. Open it with **Okno → Skóre** (Window → Score), or by clicking the score bar below the entry window.

- A **band × mode** table (the "Jen pásma" (Bands only) switch merges modes): QSOs, dupes, points and
  **new multipliers by type** (zones, countries, prefixes... according to the contest
  definition).
- A multiplier is credited to the band and mode where it was made **first** — so for multipliers
  counted once per contest (scope `ONCE`) only to one band.
- A **Celkem** (Total) row, and for multi-mode contests also totals **by mode**.
- At the bottom the result: `Points × multipliers (+ bonus) = score`.
- It is computed by replaying the whole log (like Rescore), so it is correct after editing QSOs
  or importing; X-QSOs and deleted QSOs are not counted. It refreshes itself after every
  change to the log.

In free logging (without a contest) the window only states that the breakdown is not available.
