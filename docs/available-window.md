# Available window (N1MM Available)

*Okna → Dostupné multiplikátory* lists the spots of the buffer (after the [spot filter](dx-cluster.md#spot-filter-bands-modes-spotter-origin-workable))
as the active contest scores them: new multipliers red (two or more green), plain QSOs blue, dupes grey. Without an
active contest the window only says so.

## Top bar

| Button | What it does |
|---|---|
| **Mults / Mults & Qs** | only the new multipliers, or every workable spot |
| **Pásma a režimy** | the bands and traffic categories shown (the contest's by default; what the contest does not have is greyed out) |
| **Fokus rig** | only the spots on the band of the radio (SO2R) or VFO (SO2V) with the focus; with one radio the band of the tuned frequency |
| **Sloupce a souhrn** | the columns, their order, the summary panel and its bands (below) |

## Summary panel

Under the title the summary shows the new multipliers (*Mults*), the new QSOs (*Qs*) and all spots (*Total*) per band.
The best band — the most new multipliers, then the most new QSOs — is highlighted. **A click on a band** shows only
that band's spots; a second click brings back the bands that were shown before.

In *Sloupce a souhrn* the panel can be hidden (*Zobrazit souhrnný panel*) and its bands chosen — any band including
VHF, UHF and the microwave bands. With nothing ticked the panel shows the active contest's bands (v1.1.1's six HF
bands when the contest has none). The choice is saved.

## Spot list

The columns are *Call*, *Freq*, *Dir* (azimuth from your grid), *Md* (mode), *Mlt* (✓ = new multiplier), *SN* (the
skimmer's SNR), *Time* (the spot's age in minutes), *Spotter* (★ = a preferred spotter), *Pts* (the QSO's points) and
*Sig*. **Every header sorts** (again = the other direction; *Time* ascending is the newest spot first). In
*Sloupce a souhrn* each column can be shown or hidden and moved left or right (*Call* always shows); **drag the divider
right of a header** to change the column's width. *Výchozí sloupce* restores the columns, the order and the widths. All
of it is saved.

Marks after the call, as in the band map: **♥** a special call, **#** a skimmer / RBN spot (**!** your own skimmer),
**¤** the station is at its sunrise or sunset now (gray line). A spot whose comment asks for split (`UP 5`, `QSX 14025`)
shows **QSX 027** after its frequency. VoiceOver says the marks in words.

The ***Sig*** column (off by default) shows **♪** when the spot's signal is seen in the
[waterfall](waterfall.md) now: the spot's frequency is inside the receiver's audio passband and the waterfall's
newest rows have a signal there at least ~14 dB above the noise. It needs the waterfall window open (that window holds
the receiver audio); with it closed the column stays empty.

## Mouse and keys

- **Click** a spot: the radio tunes there and the call goes to the entry window (with the call-frame on, into the
  call-frame). With **two radios (SO2R) or two VFOs (SO2V)** a spot on the band of the other radio first moves the
  focus to that radio's entry window (N1MM *focus follows spot*).
- **Middle click** (the mouse wheel button) deletes the spot under the pointer.
- **Right click**: remove the spot, blacklist the call or the spotter, QRZ.com / HamQTH, **Natočit rotátor** (the
  rotator to the station, short path, like Alt+J; by the spot's grid when known), **QSY druhého rádia / VFO** (SO2V / SO2R: the other VFO or radio
  goes to the spot and the focus stays where it is), delete all spots.
- **Alt+A** / **Shift+Alt+A** in the entry window: the next / previous spot of the list (as sorted and filtered) is
  tuned and taken, the row is highlighted; the list wraps around. Both keys can be remapped in Settings → Keys.

Nothing in this window transmits.
