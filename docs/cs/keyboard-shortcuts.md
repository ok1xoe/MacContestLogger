# Klávesové zkratky zadávacího okna

Zkratky odpovídají N1MM+
([Keyboard Shortcuts](https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/#Key_Assignments_Short_List)).
Na Macu je **Alt** klávesa **Option (⌥)**. Níže jsou **výchozí** klávesy — většinu
z nich lze přemapovat (viz [Přemapování kláves](#přemapování-kláves)).

## Proč Ctrl a ne Cmd

Na Macu byste čekali **⌘**, ale výchozí jsou tu **Ctrl** a **Alt** — a
to záměrně. Závodník obvykle zná N1MM, vysílá na cizích
počítačích a má v hlavě `Ctrl+W`, `Alt+Q`, `Ctrl+D`. Kdyby se to převedlo na
⌘, rady k N1MM od ostatních by přestaly platit a přechod na jiný počítač
by mátl. V závodě vyhrává svalová paměť nad zvyky platformy.

V praxi to nevadí: **systémové zkratky macOS používají ⌘**, takže
`Ctrl+písmeno` je volné. Aplikace je navíc zachytí dřív, než se dostanou do pole.
Výjimkou jsou **Ctrl+šipky**, které si bere Mission Control — proto
jsou skoky mezi spoty ve výchozím stavu na **Cmd+↓/↑** (viz níže).

**Cmd je plnohodnotná volba.** V **Nastavení → Klávesy** lze každou
akci přemapovat a `Cmd+…` je platná kombinace (ukládá se jako `"Cmd+DOWN"`).
Kdo chce deník nativní pro Mac, může si přemapovat všechno; nikoho jiného se to nedotkne.

## Pohyb mezi poli

| Klávesa | Akce |
|---|---|
| **mezerník** | další pole, **reporty přeskočí** (599/59 jsou předvyplněné). Z volací značky jde do výměny, z posledního pole zpět na značku |
| **Tab** / **Shift+Tab** | další / předchozí pole včetně reportů |
| **Enter** | zapíše QSO (s ESM viz [esm.md](esm.md)); v poli značky spustí příkaz ([text-commands.md](text-commands.md)) |
| **Esc** | zastaví vysílání, ladění a opakování CQ; když nic neběží, vymaže pole |

## Zápis

| Klávesa | Akce |
|---|---|
| **Alt+Enter** | odvysílá TU (F3) a zapíše. S ESM jen zapíše, nic nevysílá |
| **Ctrl+Alt+Enter** | zapíše i s **neplatnou výměnou**; zeptá se na poznámku (prázdná = „Forced QSO“) |
| **;** | odvysílá jeho značku + výměnu (F5 + F2), jako Insert v N1MM |
| **'** (apostrof) | odvysílá TU (F3) a zapíše |
| **Ctrl+W** | vymaže pole (nevratně) |
| **Alt+W** | vymaže pole; další Alt+W s prázdnými poli je **vrátí** |
| **Ctrl+Shift+W** | SO2V / SO2R: vymaže pole **druhého** zadávacího okna (fokus zůstane tady) |
| **Ctrl+D** | smaže poslední QSO (s potvrzením) |
| **Ctrl+N** | poznámka: s vyplněnou značkou k rozpracovanému QSO, jinak k naposledy zapsanému |
| **Ctrl+F** | najde značku z pole v deníku (otevře Přehled spojení s hledáním `call:`); znovu se stejnou značkou vybere její další QSO (Find Again) |
| **Ctrl+Y** | upraví naposledy zapsané QSO v dialogu (také tlačítko **Edit**), viz [Zadávací okno](entry-window.md#úprava-qso) |
| **Ctrl+Q** / **Ctrl+A** | QuickEdit: zapsaná QSO o jedno zpět / vpřed v polích zápisu; Enter uloží, Esc zruší, viz [Zadávací okno](entry-window.md#quickedit) |
| **Ctrl+Z** | WAE: režim QTC zap / vyp — otevře okno QTC pro příjem (Evropa) nebo odeslání, viz [QTC](qtc.md#režim-qtc-ctrlz) |
| **Ctrl+U** | pořadové číslo ve výměně +1; číslo Sweepstakes s precedencí ji zachová (`23B` → `24B`, i uvnitř `23B 72 CT`) |
| **Alt+Y** | další značka z panelů okna Check do pole značky (znovu = další; v poli výměny první hodnota z panelu výměny), viz [okno Check](call-check.md#alt-y) |
| **↑ / ↓** | s návrhy SCP se pohybuje v návrzích, jinak ladí rig |
| **Ctrl+O** | přihlášení operátora |

`SH/DX` (také `SH/DX/30`) napsané do pole značky a Enter jde do připojeného DX clusteru, jako v N1MM; nikdy se nezapíše.

## Zprávy a klíčování

| Klávesa | Akce |
|---|---|
| **F1–F12** | zpráva (hlasový klíč ve fonii, CW klíč) — [voice-keyer.md](voice-keyer.md), [cw-keyer.md](cw-keyer.md) |
| **Shift+F1…F12** | zpráva z opačné sady (Run ↔ S&P); podržený Shift ukáže popisky |
| **Ctrl+Shift+F1…F12** | nahraje zprávu (fonie) |
| **=** | v ESM zopakuje poslední zprávu |
| **PgUp / PgDn** | rychlost CW ± krok rychlosti CW (výchozí 2 WPM) |
| **Shift+PgUp / PgDn** | rychlost CW ± druhý krok (výchozí 1 WPM; Nastavení → Other) |
| **Ctrl+G** | zkrácená čísla zap / vyp |
| **Ctrl+M** | ESM zap / vyp |
| **Alt+R** / **Ctrl+R** | opakování CQ zap / vyp; pauza mezi CQ |
| **Ctrl+T** | **ladění**: trvalá nosná (Winkeyer key-down, v CW přes CAT PTT). Ukončí ho Ctrl+T nebo Esc, **bezpečnostní vypnutí po 30 s** |
| **Alt+K** | Nastavení → Function Keys |
| **Ctrl+K** | okno **CW z klávesnice** — psaný text se vysílá po slovech nebo po Enteru, Esc zastaví; v digitálním módu okno TX Digitálního rozhraní (vysílání) |
| **Ctrl+Alt+P** | **pass** — předá značku z pole jiné stanici síťového deníku (přímo jediné stanici online, jinak výběr v okně Stav sítě) |
| **Ctrl+Alt+M** | multi-op: typ této stanice **Run ↔ Mult** (ukládá se, ostatní stanice ho vidí; Nastavení → Cluster) |
| **Alt+Z** | multi-op: nastaví **pass frekvenci** této stanice (kHz, nabídne aktuální; prázdné = zrušit) a oznámí ji všem stanicím; značka předaná této stanici pak přistane v její bandmapě na této frekvenci |
| **Alt+=** | VKV a výš: napsaná značka a lokátor se hledají v call history a v deníku — otevře se [okno Check](call-check.md) se zapnutým zpětným hledáním (N1MM *Search entered info from both the Callsign field and the Gridsquare field*) |
| **Alt+-** | VKV a výš: pole lokátoru přepíná mezi lokátory napsané značky z call history (Loc1, Loc2) a lokátorem, který jste napsali — nejvýš tři |
| **Alt+A** / **Shift+Alt+A** | naladí a převezme další / předchozí spot ze seznamu [okna Available](available-window.md) (seznam se točí dokola) |
| **Ctrl+Alt+G** | značka z pole do [zásobníku volaček](call-stacking.md); pole se vymažou pro další značku |
| **Alt+G** / **Ctrl+Alt+K** | další značka ze [zásobníku volaček](call-stacking.md) (vlastního i partnerova) do vymazaného zadávacího okna; Alt+G v digitálním módu vezme nejdřív značku z [okna Grab](digital-modes.md#okno-grab) Digitálního rozhraní |
| **Cmd+Alt+← / →** | SO2V/SO2R: oba fokusy (RX i TX) na VFO A / rig 1 nebo VFO B / rig 2; v digitálním módu s Digitálním rozhraním 1 / 2 (N1MM Ctrl+←/→) |
| **Pause** (**F15**) | SO2V/SO2R: oba fokusy do druhého okna, nebo vysílací fokus k fokusu zápisu, když jsou rozdělené (N1MM Pause) |
| **Alt+F5** / **Alt+F6** | SO2V/SO2R: prohodí frekvenci, mód a značku mezi rádii / VFO, s přesunem / bez přesunu fokusu |
| **Cmd+Shift+↓/↑**, **Ctrl+Alt+Shift+↓/↑** | SO2V/SO2R: druhé rádio na další spot / spot násobiče (N1MM Ctrl+Shift+↓/↑, Shift+Ctrl+Alt+↓/↑) |
| **Ctrl+Shift+PgUp/PgDn**, **Alt+Shift+Q** | SO2V/SO2R: druhé rádio o pásmo výš / níž, na jeho CQ frekvenci |
| **Alt+PgUp/PgDn** | CW, SO2V/SO2R: rychlost rádia bez vysílacího fokusu |
| **Ctrl+B** | SO2R: Dueling CQ zap / vyp |
| **Ctrl+Shift+K** / **Ctrl+Shift+L** / **Ctrl+`** | SO2R: FocusOther / makro `{CTRLFx}` / makra stereo a OTRSP RX zap / vyp |
| **Ctrl+F1 … F12**, **Ctrl+Enter** | SO2V/SO2R: F-klávesa druhého okna / další krok ESM na jeho rádiu — viz [SO2R](so2v.md#so2r--dvě-rádia) |
| **Alt+T** | digitální módy: vysílání zap / zpět na příjem; psaní převezme okno TX Digitálního rozhraní |
| **Insert** (Help) | digitální módy: značka z okna Grab do prázdného pole, pak F5+F2 (tabulka Insert z N1MM) |

## Rig

| Klávesa | Akce |
|---|---|
| **↑ / ↓** (bez návrhů SCP) | ladění o krok: **↑ dolů, ↓ nahoru**; 20 Hz v CW a digitálních módech, 100 Hz ve fonii |
| **kolečko myši** nad zadávacím oknem | ladění o krok; s **Alt** na další celý 1 kHz, s **Ctrl** 10 kHz, s **Ctrl+Alt** 100 kHz |
| **Ctrl+PgUp / PgDn** | o pásmo výš / níž. Vrátí se na poslední frekvenci na pásmu, jinak na začátek segmentu módu. V závodě jen jeho pásma, WARC se přeskočí |
| **Alt+F8** | zpět na předchozí frekvenci (po skoku na spot, Alt+Q...) |
| **Alt+U / Alt+Q / Alt+F11** | Run/S&P, zpět na CQ frekvenci, automatika Run/S&P — [run-sp.md](run-sp.md) |
| **Ctrl+Alt+Q** | na poslední CQ frekvenci na kterémkoli pásmu (Run); bandmapa sleduje rig |
| **Ctrl+S** | zapne split (vysílání na VFO B); se zapnutým splitem poslouchá na vysílací frekvenci, znovu zpět na přijímací |
| **Alt+S** | ve splitu vrátí přijímač na vysílací frekvenci (volitelně po každém QSO v režimu Run: Nastavení → Other) |
| **Ctrl+Alt+S** | přepíná split zap / vyp |
| **Alt+F7** | split na zadanou frekvenci nebo posun (`+2`); prázdné = vypnout split |
| **Ctrl+Enter** | frekvence v poli značky = vysílací (split) frekvence |
| **Alt+F10** | prohodí VFO A ↔ B |
| **Alt+F12** | frekvence VFO A do VFO B; na rigu s volbou „Vedlejší přijímač stále zapnutý“ (Nastavení → TCVR) druhý přijímač (dual watch) zap / vyp |
| **Ctrl+Alt+D** | SO2V: opakování CQ na VFO A se zapnutým druhým přijímačem (mezi CQ laďte druhým přijímačem); znovu = vyp |
| **Alt+'** | filtr rigu na druhou šířku jeho módu, široký ↔ úzký (tlačítko Wide/Narrow v bandmapě; šířky v Nastavení → DX Cluster) |
| **Ctrl+Alt+R** | CW reverse zap / vyp (mód rigu CW ↔ CWR, šířka filtru zůstane) |

## Bandmapa a spoty

| Klávesa | Akce |
|---|---|
| **Cmd+↓ / Cmd+↑** | další spot **výš / níž** na pásmu (dupe se přeskakují) |
| **Ctrl+Alt+↓ / ↑** | další spot, který je **novým násobičem** |
| **Shift+Alt+↓ / ↑** | další **vlastní** spot (Store / self-spot) |
| **Shift+↓ / Shift+↑** (pevné) | s otevřeným oknem vodopádu / spektra: další **signál** ve spektru výš / níž (dupe a označené frekvence se přeskakují; se zobrazenými značkami CQ další CQ frekvence); jinak ladí jako ↓ / ↑ — viz [Vodopád](waterfall.md#signály-spoty-a-hledání-cq) |
| **Alt+D** | odstraní spot značky v poli (nebo spot na frekvenci); v okně Bandmapa spot pod myší. S prázdným polem značky a neprázdným zásobníkem volaček smaže další značku v zásobníku |
| **Alt+Shift+D** | totéž a dá značku na **blacklist** (také v okně Bandmapa) |
| **Alt+P** / tlačítko **Spot It** | spot do DX clusteru (potřebuje frekvenci, viz výše) |
| **Ctrl+P** | spot s komentářem (potřebuje frekvenci, viz výše) |
| **Alt+O** / tlačítko **Store** | uloží značku z pole do bandmapy na aktuální frekvenci (potřebuje frekvenci: připojte rádio nebo ji napište do pole frekvence) |
| **Alt+M** / tlačítko **Mark** | označí frekvenci v bandmapě jako obsazenou (potřebuje frekvenci, viz výše; také když má fokus okno Bandmapa) |
| **Ctrl+Tab** | zobrazí / skryje okno DX clusteru |

Alt+M, Alt+D a Alt+Shift+D fungují i tehdy, když je aktivním oknem okno Bandmapa, s vašimi vlastními přiřazeními kláves. V okně Bandmapa odstraní Alt+D spot pod ukazatelem myši; s ukazatelem jinde působí jako v zadávacím okně.

V okně Bandmapa **Cmd+=** / **Cmd+-** (nebo **+** / **−** na numerické klávesnici) bandmapu přibližují a oddalují.

V okně Bandmapa **⌘⌥⇧0 … ⌘⌥⇧9, ⌘⌥⇧A … ⌘⌥⇧Z** stisknou uživatelská tlačítka bandmapy 1–36 (N1MM
Ctrl+Alt+Shift+0…Z), viz [DX cluster → Horní lišta bandmapy a uživatelská tlačítka](dx-cluster.md#horní-lišta-bandmapy-a-uživatelská-tlačítka).

## Rotátor a antény

| Klávesa | Akce |
|---|---|
| **Alt+J** | rotátor na značku v poli (jinak na poslední QSO), krátkou cestou; číslo 0–360 v poli značky natočí na tento azimut |
| **Alt+L** | totéž dlouhou cestou |
| **Ctrl+Alt+J** | zastavení rotátoru |
| **Ctrl+Alt+A** | další anténa pro pásmo |
| **F1–F10** (aktivní okno Rotátor) | přednastavené azimuty z nastavení rotátoru |

Klávesy rotátoru jsou podle N1MM. Do verze 1.1.1 měl MacContestLogger dlouhou cestu a zastavení obráceně
(dlouhá cesta **Ctrl+Alt+J**, zastavení **Alt+L**). Změnily se jen výchozí hodnoty: pokud jste kteroukoli akci
přemapovali v „Nastavení → Klávesy“, vaše klávesy zůstanou, jak jste je nastavili. **Výchozí** nebo **Vše na výchozí
(N1MM)** přepne na klávesy N1MM.

## Ostatní

| Klávesa | Akce |
|---|---|
| **Alt+H** | nápověda (dokumentace projektu; také Nápověda → Dokumentace) |

## Přemapování kláves

![Nastavení → Klávesy: přehled akcí a jejich kláves](../img/settings-keys.png)

Obdoba **Key Mapperu** z N1MM: **Nastavení → Klávesy**
vypíše všechny akce zadávacího okna s jejich klávesami.

- **Změnit** — stiskněte novou kombinaci (Esc zruší). Kombinace musí obsahovat Ctrl, Alt
  nebo Cmd; bez modifikátoru jsou povolené jen F-klávesy, **;** a **'** (jinak by zkratka
  přebila psaní do polí).
- **Výchozí** obnoví klávesu N1MM, **Žádná** odebere akci klávesu,
  **Vše na výchozí (N1MM)** zruší veškeré přemapování.
- Přemapované klávesy jsou **tučně**, kolize dvou akcí **červeně**. Při kolizi
  vyhrává přemapovaná akce.
- Ukládá se do `config.json` (`keyBindings`: id akce → např. `"Cmd+DOWN"`) a platí hned po OK.

Základy zápisu přemapovat nelze: F1–F12 (zprávy a jejich varianty se Shift/Ctrl+Shift),
Enter, Esc, Tab, mezerník, šipky (ladění / návrhy SCP), PgUp/PgDn (rychlost CW) a „=“.

Typické použití na Macu: **Ctrl+↓/↑** (klávesa N1MM pro skoky mezi spoty) si bere
Mission Control, takže skoky jsou ve výchozím stavu na **Cmd+↓/↑** a nemusíte měnit systémové
zkratky. Dříve uložené přemapování funguje dál; přemapujte na **Ctrl+↓/↑**, pokud
jste zkratky Mission Control vypnuli.

## macOS: konflikty se systémem

- **Ctrl+↑/↓/←/→** používá macOS ve výchozím stavu pro Mission Control a Spaces, proto
  jsou tu skoky mezi spoty na **Cmd+↓/↑**. Chcete-li místo nich klávesy N1MM **Ctrl+↓/↑**,
  vypněte systémové zkratky v Nastavení systému → Klávesnice → Klávesové zkratky →
  Mission Control a přemapujte akci v Nastavení → Klávesy.
- **F-klávesy:** když mění jas nebo hlasitost, držte **fn**, nebo zapněte „Používat
  klávesy F1, F2 atd. jako standardní funkční klávesy“.
- **Option+F11** může zachytit systém. Automatiku Run/S&P lze přepínat i příkazem
  `AUTORSP` / `NOAUTRSP`.
- Klávesy **;** a **'** se berou podle fyzické polohy na americké klávesnici
  (vedle L). Na české klávesnici jsou to klávesy **ů** a **§**.

## Nepodporované zkratky N1MM

Filtry **Alt+'**, zásobník volaček
**Alt+G / Ctrl+Alt+G**, multi-op **Ctrl+Alt+M / Alt+Z**, autosend **Ctrl+Shift+M** (samotný práh AutoSend se
nastavuje v Nastavení → Práh AutoSend (CW)…, viz [ESM](esm.md#autosend-cw)).

## RIT

| Klávesa / příkaz | Akce |
|---|---|
| **Ctrl+Alt+→ / ←** | RIT o krok nahoru / dolů (20 Hz CW a digitální módy, 100 Hz fonie) |
| **Ctrl+Alt+Shift+R** | RIT vypnout (Ctrl+Alt+R je CW reverse, jako v N1MM) |
| `RIT 120`, `RIT -50` | RIT na zadaný posun v Hz |
| `NORIT`, `RITCLEAR` | RIT vypnout |

RIT se nastavuje přes CAT (hamlib `J` + funkce `RIT`). Zadávací okno ukazuje
`RIT +120`; po zápisu QSO se RIT sám vynuluje (N1MM „Clear RIT after logging“,
`ritClearAfterLog` v `config.json`). Klávesy lze přemapovat v Nastavení → Klávesy.
