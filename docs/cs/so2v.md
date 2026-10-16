# SO2V — dvě zadávací okna na jednom rádiu

Obdoba **SO2V** (Single Operator 2 VFO) z N1MM+. Zapíná se v **„Nastavení →
Hardware → SO2V“** (volba se ukládá jako `radioMode`
v `config.json`).

- Vedle hlavního okna (VFO A) se otevře **„Zadávací okno — VFO B“** se stejnými
  poli, klávesami a F-klávesami.
- **Aktivní okno = aktivní VFO**: kliknutí nebo fokus do okna přepne rádio
  přes CAT (`V VFOA` / `V VFOB`) — na tomto VFO se přijímá i vysílá. Horní
  řádek okna ukazuje „VFO A — aktivní (vysílá)“.
- Každé okno má vlastní volací značku, výměnu a kmitočet; kmitočet a mód
  z rádia, kliknutí na spot a předvyplnění výměny přebírá jen aktivní
  okno. Kmitočet neaktivního VFO zůstane, jak byl, a při návratu se
  obnoví.
- Typické použití: Run na VFO A, lov násobičů na VFO B — přepínání jedním
  kliknutím mezi okny.

- **Vedlejší přijímač** (rádia se dvěma přijímači a volbou „Vedlejší přijímač stále zapnutý“ v nastavení rádia): **Alt+F12**
  zapíná / vypíná dual watch. **Ctrl+Alt+D** spustí opakování CQ na VFO A se zapnutým vedlejším přijímačem, takže mezi
  výzvami ladíte vedlejší přijímač na rádiu; stanici, která se tam ozve, uděláte z okna VFO B (`\`, Pause). Další
  Ctrl+Alt+D opakování zastaví a vedlejší přijímač zase vypne (pokud není zapnutý stále). MCL nečte přes hamlib knoflík
  vedlejšího přijímače: okno VFO B ukáže jeho kmitočet, jakmile je VFO B vybráno.
- Okno spektra kreslí druhé VFO jako čáru v barvě zvýraznění.

Přepnutí zpět na SO1V zavře okno VFO B. Rádio musí podporovat volbu VFO
přes hamlib (většina transceiverů s CAT).

# SO2R — dvě rádia

Obdoba **SO2R** z N1MM+ s ovladačem **OTRSP** (SO2RDuino, YCCC SO2R
Box+, microHAM v režimu OTRSP). Zapíná se v **„Nastavení → Hardware → SO2R“**.

- **Rádio 1** je hlavní rádio z Nastavení. **Rádio 2** se připojuje k běžícímu
  `rigctld` (host a port na kartě Hardware, výchozí `localhost:4534`), např.
  `rigctld -m <model> -r /dev/cu.usbserial-… -t 4534`. Každé okno má vlastní tlačítko
  CAT a LED.
- Okno **„Zadávací okno — rig 2“** pracuje s rádiem 2;
  ladění, split, RIT a spoty jdou na rádio okna, které má **fokus zadávání**.
- **Dva fokusy, jako v N1MM.** **Fokus zadávání (RX)** — zelená LED v horním řádku okna — je okno, do kterého
  píšete (a s OTRSP boxem rádio ve sluchátkách). **Fokus vysílání** — červená LED, při vysílání oranžová — je rádio,
  které klíčuje klíčovač, hlasový klíčovač, pastička, nožní spínač PTT a klávesa PTT pluginu.
  `\` a kliknutí do okna přesouvají jen fokus zadávání; F-klávesa, ESM Enter, `;`, `'`, psané CW (Ctrl+K) nebo
  Ctrl+T odeslané z okna nejdřív přesunou fokus vysílání tam. Můžete tak psát značku na S&P rádiu, zatímco
  na run rádiu ještě jde CQ, a stisk Enter vysílá na S&P rádiu.
- **Ovladač OTRSP** (sériový port v Nastavení): fokus zadávání posílá `RX1`/`RX2` (stereo `RX1S`/`RX2S`),
  fokus vysílání `TX1`/`TX2`.
- **Časy přepnutí rádia** (Nastavení → SO2R, N1MM Config → SO2R): *čas po vysílání* zdrží přepnutí na druhé rádio
  po vysílání, které jste tam přerušili (přerušené CQ), *předstih* je pauza mezi přepnutím a prvním
  zaklíčováním (příslušenství stanice změnu zaregistruje). Oba jsou výchozí 0 ms a platí pro CW i hlasové zprávy.
- **Druhý výstup Winkeyeru** (Nastavení → SO2R → *Winkeyer: rádio 2 na druhém výstupu*): rádio 1 se klíčuje na
  KEY OUT 1, rádio 2 na KEY OUT 2 (WinKeyer 2 a novější); konfigurace pinů se před každou zprávou řídí fokusem
  vysílání. Bez této volby sdílí obě rádia KEY OUT 1 a klíčovací linku přepíná SO2R box.
- V SO2R se odvysílané CW vždy vypisuje ve stavovém řádku i s rádiem (`CW R2: …`), jako v N1MM.

| Klávesa | Akce |
|---|---|
| **\\** | fokus zadávání (RX) na druhé okno (rádio / VFO) — N1MM „\\“; v SO2R fokus vysílání zůstává |
| **Pause** (**F15** na Macu) | oba fokusy na druhé okno; když jsou rozdělené, fokus vysílání se připojí k fokusu zadávání |
| **Cmd+Alt+← / →** | oba fokusy na VFO A / rádio 1 nebo VFO B / rádio 2 (N1MM Ctrl+←/→); v digitálním módu i s jeho Digitálním rozhraním |
| **Ctrl+F1 … F12** | zpráva F-klávesy druhého okna, odvysílaná na jeho rádiu; fokus zadávání zůstává zde (N1MM Ctrl+Fn) |
| **Ctrl+Enter** | další krok ESM druhého okna na jeho rádiu (se zapnutým ESM; kmitočet v poli volačky dál nastavuje split) |
| **Alt+F5** | prohození kmitočtu, módu a značky mezi rádii (SO2R) nebo VFO (SO2V); fokus zadávání přejde na druhé okno |
| **Alt+F6** | SO2R: totéž prohození, fokus zůstává |
| **`** | SO2R stereo poslech zap / vyp |
| **Cmd+Shift+↓ / ↑** | druhé rádio / VFO na další spot výš / níž (N1MM Ctrl+Shift+↓/↑); na pásmu aktivního rádia se jeho kmitočet přeskočí |
| **Ctrl+Alt+Shift+↓ / ↑** | druhé rádio / VFO na další spot násobiče výš / níž |
| **Ctrl+Shift+PgUp / PgDn** | druhé rádio / VFO o pásmo výš / níž |
| **Alt+Shift+Q** | druhé rádio / VFO na CQ kmitočet jeho pásma |
| **Alt+PgUp / PgDn** | CW: rychlost rádia bez fokusu vysílání (každé rádio si drží vlastní rychlost) |
| **Ctrl+B** | SO2R: Dueling CQ zap / vyp |
| **Ctrl+Shift+K** | SO2R: FocusOther zap / vyp |
| **Ctrl+Shift+L** | makro `{CTRLFx}` zap / vyp |
| **Ctrl+`** | makra stereo / OTRSP RX zap / vyp |

Všechny lze přemapovat v „Nastavení → Klávesy“, kromě Ctrl+F1–F12 a Ctrl+Enter, které
následují F-klávesy a Enter. macOS si některé kombinace Control+F-klávesa drží pro navigaci klávesnicí (Nastavení
systému → Klávesnice → Klávesové zkratky → Klávesnice); vypněte je, chcete-li používat Ctrl+F1–F8. Klávesa Pause
PC klávesnice dorazí do Macu jako F15. V SO2V má jedno rádio jeden vysílač, takže oba fokusy jsou vždy ve stejném
okně: Ctrl+F1–F12 udělají druhé VFO pro zprávu aktivním a po jejím odvysílání se vrátí, pokud je v poli volačky
tohoto okna značka.

- **Druhé rádio z bandmapy a pole volačky:** **Shift+klik** na spot (nebo kmitočet) v bandmapě
  naladí druhé rádio / VFO a vloží značku do jeho okna; `/14030` v poli volačky naladí v SO2R druhé rádio
  (v SO1V / SO2V VFO B rádia). Fokus zůstane, kde je.
- **Rotátor rádia s fokusem:** Alt+J / Alt+L otáčí rotátory používané antény; pokud tu anténu zvolilo
  druhé rádio na jiném pásmu, použije se první anténa pásma rádia s fokusem (Nastavení → Antény) a její
  rotátory.
- **Softwarová blokace pásma:** v SO2R Ctrl+PgUp/PgDn kteréhokoli rádia přeskočí pásmo, na kterém je druhé rádio.
  Hardwarovou blokaci nenahrazuje.
- **Kurzor v neaktivním okně** zůstává vyznačený (tenká čárka), takže po `\` vidíte, kde psaní pokračuje.

## Číslo rádia u QSO

Jako v N1MM si každé QSO pamatuje rádio, na kterém bylo zapsáno (`RadioNr`): v SO2R rádio jeho zadávacího okna, v SO2V
VFO okna (A = 1, B = 2), s jedním rádiem 1. QSO ze starších deníků a z importů bez něj ho nemají. Číslo
odchází s QSO do UDP vysílání N1MM (`radionr` / `run1run2` z `contactinfo`), do exportu ADIF
(`APP_N1MM_RADIO_NR`, `APP_N1MM_RUN1RUN2`), na ostatní stanice multi-op sítě a určuje
číslo vysílače v Cabrillu Multi-Two vedeném na jednom počítači (viz [Import a export](import-export.md#cabrillo)).

## Nastavení → SO2R (N1MM Config → SO2R)

Volby se pamatují mezi spuštěními („sticky“, jako v N1MM).

- **Dueling CQ** (Ctrl+B): klávesa CQ (F1 nebo klávesa CQ v ESM) se vyšle na jednom rádiu, a když je odvysílaná a
  uplyne *Pauza Dueling CQ* (výchozí 100 ms), na druhém — střídavě, počínaje rádiem s fokusem
  zadávání; obě rádia jsou run rádia. Značka napsaná v kterémkoli okně ho pozastaví, její smazání ho obnoví. Končí
  Esc, Ctrl+B, posunem kteréhokoli rádia o víc než 200 Hz, neúspěšným odesláním, síťovou blokací TX, zápisem po závodě
  a nejdelší dobou opakování CQ („Nejdelší opakování CQ (min)“). Nikdy se nespustí samo.
- **FocusOther — fokus na druhé rádio** (Ctrl+Shift+K): zatímco run rádio (to, které vyslalo poslední CQ)
  vysílá, fokus zadávání přejde na druhé rádio, takže můžete psát značku, kterou tam slyšíte; když run rádio
  přestane, fokus se vrátí — pokud ovšem v okně S&P není napsaná dosud neudělaná značka. **FocusOther: vždy přepnout**:
  každé vysílání přesune fokus na druhé rádio a zpět bez ohledu na to, co bylo napsáno.
- **Makro {CTRLFx}** (Ctrl+Shift+L): vypnuto = `{CTRLF1}`…`{CTRLF12}` ve zprávách se ignorují.
- **Makra stereo / OTRSP RX** (Ctrl+`): vypnuto = `{STEREOON}`, `{STEREOOFF}`, `{OTRSP RX}` a `{OTRSPOTHER RX}` se
  ignorují (např. když chvíli používáte jen jedno zadávací okno).
- **Čas po vysílání / Předstih při přepnutí rádia** a **Winkeyer: rádio 2 na druhém výstupu** — viz výše.
- **SO2V: zápis do okna VFO B ukončí opakované CQ** (N1MM „Repeating CQ Ends With VFOB Window Entry“): napsání značky
  v okně VFO B vypne opakování CQ.

V SO2R zůstává opakování CQ (Alt+R) na rádiu, na kterém bylo zapnuto, takže run rádio dál volá CQ, zatímco
píšete na S&P rádiu. Zpráva odvysílaná na druhém rádiu ho ukončí (N1MM: „CQ-repeat is terminated when a message is
sent on the other radio“) — tam jste totiž začali QSO.

## Dvě klávesnice

*Two Keyboards* v N1MM Config → SO2R: **Nastavení → SO2R → Dvě klávesnice** (výchozí vypnuto). Se dvěma zadávacími
okny na obrazovce ovládá každá ze dvou klávesnic své okno — klávesa z klávesnice 1 jde do levého
okna (rádio 1 / VFO A), klávesa z klávesnice 2 do pravého (rádio 2 / VFO B), bez ohledu na to, které okno má fokus.

- **Která klávesnice je která:** jako v N1MM ovládá první klávesnice, na kterou po spuštění napíšete, okno 1 a
  další jiná klávesnice okno 2. Pro pevné přiřazení otevřete **Nastavení → SO2R → Dvě klávesnice: přiřazení…**:
  vypíše připojené klávesnice, nechá vybrat tu pro *Okno 1* a *Okno 2* a ukáže, ze které klávesnice přišla poslední
  klávesa (dokud je otevřené, klávesy se mezi okny nepřesouvají). Dvě klávesnice stejného modelu se
  rozliší podle USB portu, do kterého jsou zapojené.
- `\` napsané na klávesnici jen přesune fokus do okna této klávesnice; klávesa Pause (F15) nedělá nic — se
  dvěma klávesnicemi není k přepínání oken potřeba ani jedna.
- Klávesy zůstávají tam, kde jsou, dokud je otevřený dialog nebo list, a když píšete do textového pole jiného
  okna (příkazový řádek clusteru, dialog).
- **Sledování vstupu v macOS:** k rozlišení klávesnic je nutné. macOS se zeptá při zapnutí volby; pokud
  jste odmítli, povolte MacContestLogger v Nastavení systému → Soukromí a zabezpečení → Sledování vstupu (okno
  nastavení na to má tlačítko) a volbu vypněte a znovu zapněte. Bez oprávnění klávesy prostě zůstávají
  v okně s fokusem. Aplikace čte jen to, ze které klávesnice klávesa přišla; nic se neposílá do žádného zařízení.
- Nástroje na přemapování klávesnice, které posílají vlastní klávesy (Karabiner a podobné), mohou přiřazování
  zmást, jak N1MM varuje u AutoHotKey.

## 2BSIQ — dvě QSO najednou

Dvě prokládaná QSO na dvou pásmech (N1MM 2BSIQ) nepotřebují nic zapínat: se zapnutým ESM vedou obě zadávací okna
každé své QSO vedle sebe.

- Každé okno si drží vlastní posloupnost ESM (co bylo v jeho QSO odvysíláno), stav Run / S&P a poslední odvysílanou
  zprávu (`=` zopakuje poslední zprávu tohoto okna, ne tu, kterou mezitím vyslalo druhé rádio).
- Psaní v jednom okně nikdy nepřeruší vysílání na druhém rádiu. AutoSend (CW) počká, dokud druhé
  rádio vysílá; Enter pak jako obvykle odvysílá celou značku.
- Stisk Enter nebo F-klávesy v okně tam přesune fokus vysílání a zastaví, co druhé rádio vysílalo
  (N1MM „changing transmit focus stops sending“); časy přepnutí rádia, řazení F-kláves a blokace digitálního TX
  (Multi-TX / vyhrává první / vyhrává poslední) rozhodují, co se stane, když chtějí vysílat obě rádia.
- Opakování CQ skončí, když vysílá druhé rádio.
- Odvysílané CW se vypisuje ve stavovém řádku každého okna, takže vidíte, kde které QSO je.

Nastavení doporučené N2IC: [dvě klávesnice](#dvě-klávesnice), ESM zapnuté, makra stereo / OTRSP zapnutá, bez Dueling CQ a bez FocusOther, krátké CQ a
CQ na každém rádiu spouštěné ručně klávesou Enter, jakmile druhé rádio domluví.

V digitálních módech může mít každé zadávací okno vlastní Digitální rozhraní a fldigi — viz
[Digitální módy → SO2V / SO2R](digital-modes.md#so2v--so2r-dvě-digitální-rozhraní).
