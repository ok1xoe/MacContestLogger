# Run / S&P

Režim říká, zda voláte CQ (**Run**), nebo hledáte stanice (**S&P**).
Vybírá sadu zpráv F1–F12 (Run i S&P mají každý vlastní), mění chování
ESM ([esm.md](esm.md)) a u každého QSO zaznamená režim, ve kterém bylo navázáno
(vysílání RadioInfo `IsRunning`). Chování odpovídá N1MM+
([Run mode and S+P mode](https://n1mmwp.hamdocs.com/manual-windows/entry-window/#Run_mode_and_S_P_mode)).

## CQ frekvence

- **F1 (CQ)** nebo přepnutí do Run si zapamatuje **CQ frekvenci** pásma. Každé
  pásmo má vlastní.
- Vstupní okno ji ukazuje vedle přepínače Run/S&P (např. `CQ 14025.0`)
  a bandmapa ji zobrazuje jako čárkovanou čáru se značkou **CQ**.
- **QSY pryč** od CQ frekvence (o více než 300 Hz v CW a digitálních módech, o 1 kHz ve fonii)
  přepne do **S&P**.
- **Návrat na CQ frekvenci** pásma přepne zpět do **Run**.
- Klepnutí na značku **CQ** v bandmapě vrátí rádio na CQ frekvenci a přepne do Run.

## Klávesy

| Klávesa | Akce |
|---|---|
| **Alt+U** | přepíná Run / S&P. Přepnutí do Run nastaví CQ frekvenci na aktuální |
| **Alt+Q** | zpět na CQ frekvenci pásma, Run, vymaže pole |
| **Alt+F11** | vypne / zapne automatické přepínání (DXpedice, několik Run stanic na pásmu) |
| **F1** | CQ: v S&P přepne do Run |
| **Shift+F1…F12** | odešle zprávu z opačné sady (v Run zprávu S&P a naopak) |
| podržený **Shift** | mřížka F-kláves ukazuje popisky opačné sady |

Na Macu je Alt klávesa **Option**.

## Volby (Nastavení → Function Keys → Run / S&P)

- **Automaticky přepínat** (ve výchozím stavu zapnuto). Totéž dělá Alt+F11 nebo textové
  příkazy DXLogu `AUTORSP` / `NOAUTRSP`. Když je vypnuto, okno ukazuje „ruční
  Run/S&P“.
- **Návrat na CQ frekvenci přepne do Run** (ve výchozím stavu zapnuto). Vypnutí se hodí
  ve sprintech: QSY pryč stále přepne do S&P, ale do Run se vrátíte jen pomocí F1 nebo
  Alt+Q (N1MM „Do not automatically switch to Run on CQ-frequency“).

## Dvě vstupní okna (SO2V / SO2R)

Stejně jako v N1MM má každé vstupní okno **vlastní** Run / S&P — Run na jednom rádiu a S&P na druhém, S&P na obou, nebo
Run na obou (Dueling CQs). F1 nebo Alt+U v okně změní jen toto okno; F-klávesy okna, ESM a
zprávy z něj odeslané na druhé rádio (Ctrl+F1–F12) používají jeho vlastní sadu. Horní řádek každého okna ukazuje jeho
stav (**Run** / **S&P**) vedle LED fokusu; nastavují ho přepínací tlačítka v okně.
