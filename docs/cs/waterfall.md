# Vodopád a audio přijímače

![Vodopád z audia přijímače](../img/waterfall.png)

## Vodopád a zobrazení spektra

Obdoba spektra / panadapteru v N1MM+ (Spectrum Display) a DXLogu — bez SDR, z **audia přijímače**.
Otevírá se přes **Okno → Vodopád**.

- **Nastavení → Audio → Příjem**: vstup zvukové karty, na který jde audio z rigu (USB audio CODEC),
  a **CW tón** přijímače (výchozí 600 Hz).
- **Okno → Vodopád 2 (rádio 2)** (okno spektra s přiřazeným rádiem v N1MM): svázané s rádiem 2 / VFO B — jeho
  frekvence; kliknutí, kolečko a Shift+↑/↓ v okně VFO B ladí rádio 2 (fokus zůstává). V SO2R ukazuje vlastní
  zvukový vstup rádia 2, zvolený v horní části okna; externí (UDP) zdroj zůstává u prvního okna.
- Okno kreslí FFT audia v rozsahu 0–3 kHz: nahoře **panel spektra**, pod ním **vodopád** (nejnovější řádek
  nahoře; šum tmavě modře, silné signály až do žluté). Jas vodopádu se přizpůsobuje úrovni šumu.
- Při najetí myší se ukazuje frekvence na pásmu podle módu rigu (CW, CW-R, USB, LSB, data).

### Panel spektra

- **Bílé** sloupce jsou okamžité úrovně, **modrá** čára doznívající úrovně (se signálem vyskočí nahoru a klesá
  rychlostí doznívání), **modrá přerušovaná** čára práh signálu nad úrovní šumu.
- **Žlutá** čára je frekvence příjmu (v CW CW tón), **červená** čára frekvence vysílání, když rig hlásí split.
  V SO2V se druhé VFO kreslí barvou zvýraznění, pokud leží v zobrazeném rozsahu.
- Rámeček nad panely ukazuje úroveň šumu, práh, počet nalezených signálů a rozlišení (Hz na bin).

### Myš

| Kde | Akce | Účinek |
|---|---|---|
| Spektrum | kliknutí | naladí rig na dané místo; s volbou **Klik přichytí na signál (±2 kHz)** (výchozí zapnuto) na střed nejbližšího signálu v rozmezí ±2 kHz |
| Spektrum nebo vodopád | **Cmd+kliknutí** (N1MM Ctrl+kliknutí) | nastaví tam frekvenci vysílání pro split (VFO B, bez přichycení); frekvence příjmu zůstává |
| Vodopád | kliknutí | naladí rig přesně na dané místo (bez přichycení, jako v N1MM): v CW tak, aby stanice zněla na CW tónu; v SSB klikněte na spodní okraj signálu (USB) |
| Spektrum | kolečko | posouvá práh signálu (modrou přerušovanou čáru) |
| Spektrum | **Cmd+kolečko** (N1MM Ctrl) | posouvá referenční úroveň (celou křivku nahoru / dolů) |
| Spektrum | **Cmd+Shift+kolečko** | mění zobrazený rozsah v dB |
| Vodopád | kolečko | ladí rig o krok ladění daného módu (Nastavení → Ostatní); se Shift nebo Cmd po deseti krocích |

Práh, reference i rozsah se pamatují.

### Signály, spoty a hledání CQ

- **Detekce signálů**: každý souvislý úsek binů nad čárou prahu je signál; označí ho **červená tečka** dole ve
  spektru a rámeček ukazuje, kolik jich je. Kolečkem myši posuňte práh tak, aby tečky seděly na skutečných
  signálech.
- **Potlačení statiky** (**Citlivost na statiku**, 0 = vypnuto … 100): řádek, v němž celá úroveň šumu najednou
  vyskočí, se zobrazí, ale nezapočítá se do doznívající čáry, detekce signálů ani průměru pro CQ — po tu dobu
  v okně svítí **Statika**.
- **Shift+↓ / Shift+↑** (v okně zápisu) naladí další detekovaný signál výš / níž a přeskočí signály v toleranci
  ladění od spotu dupu nebo od označené frekvence (Alt+M). Na okraji spektra se zastaví. Při zavřeném okně ladí
  o krok jako ↓ / ↑.
- **Spoty nad spektrem**: telnetové a lokální spoty v zobrazeném rozsahu se kreslí na své frekvenci (šedá =
  dupe, červená = nový násobič); spot, na který jste naladěni, je v rámečku; kliknutí na značku přeladí na spot
  (i s jeho splitem). Volby: spoty skrýt, nebo zobrazit **Jen spoty, které je slyšet** (signál v toleranci ladění).
- **Filtr značek**: značit všechny signály, všechny **Kromě dupů a neplatných**, **Jen neznámé (bez spotu)**
  (žádný spot v toleranci ladění — slyšíte je dřív, než je spotne RBN), nebo **Jen násobiče**. Shift+šipky se
  řídí stejným filtrem.
- **Neznámé signály jako spoty @frekvence** (výchozí vypnuto): každé 2 s jdou neznámé signály do bandmapy
  a okna Dostupné jako lokální spoty se značkou `@14025.3` (kHz); vyprší po 90 s bez signálu a zmizí po vypnutí
  volby nebo zavření okna. Nikam se neodesílají.
- **CQ** najde až pět frekvencí, na nichž v poslední minutě nebyl žádný signál nad prahem (60sekundový průměr
  zobrazeného rozsahu; šířka 500 Hz v CW, 3 kHz ve fonii, 1 kHz v digitálních módech), očíslovaných 1–5 podle
  toho, jak jsou tiché. Dokud jsou zobrazené, Shift+šipky mezi nimi skáčou; dalším stiskem tlačítka (**Zrušit**)
  je odstraníte.

### Spektrum ze SDR nebo z jiné stanice (UDP)

Okno umí zobrazit i široké spektrum, které posílá jiný program ve formátu spektra N1MM (UDP, port 13064) —
CW Skimmer („Send Spectrum via UDP“), Waterfall Bandmap, KE9NS PowerSDR, N1MM SDR Server nebo jiný logger,
který své spektrum přeposílá. Ve **volbách → Zdroj a síť**:

- **Zdroj spektra**: *Audio přijímače* (vodopád 0–3 kHz popsaný výše) nebo *Externí přes UDP*.
- **Jméno zdroje**: jméno, které program posílá (např. `CW Skimmer`); prázdné = první slyšený zdroj. Dosud
  slyšené zdroje se nabízejí v **Slyšené zdroje**.
- **Přijímat spektrum přes UDP (N1MM, port 13064)** (výchozí vypnuto) a **Adresa příjmu** (`0.0.0.0:13064`; port
  může tento Mac sdílet s dalšími programy). Změněnou adresu použijete klávesou Return.
- Vše výše uvedené funguje stejně i nad externím spektrem: značky signálů, Shift+šipky, přichycení, hledání CQ,
  spoty, zoom i vodopád; žlutá čára je pak ve všech módech frekvence příjmu rigu.
- **Přeposílat zobrazené spektrum přes UDP** (výchozí vypnuto): pět řádků za sekundu z toho, co okno ukazuje
  (audio přijímače nebo externí zdroj), jde na **cíle** (`host:port`, oddělené čárkou — jiné MCL nebo N1MM+
  poslouchá na 13064) pod **Jméno tohoto zdroje**. Přijatý zdroj se stejným jménem se zpět neposílá.

Socket je otevřený a přeposílání vysílá jen tehdy, když je okno otevřené. Datagramy se přijímají jen ze
zadaných adres a posílají jen na ně; do éteru se nic nevysílá.

Nepodporováno (vyžaduje přístup k hardwaru, který MCL nemá): scope Icom CI-V (rig se ovládá přes `rigctld`,
který drží CAT port; hamlib nabízí data scope jen ve svých volitelných UDP multicast snímcích, ne přes příkazy
rigctld, které MCL používá), protokol panadapteru Flex SmartSDR a přímo SDR přes SpyServer / ExtIO — použijte
místo toho program, který posílá datagramy spektra N1MM (například CW Skimmer nebo SDR Server na jiném počítači).

### Zoom a volby

- **−** / **+** zvětšují spektrum a vodopád (×1 … ×16) kolem frekvence příjmu.
- Tlačítko **voleb** (ikona posuvníků) otevře volby zobrazení (v N1MM nabídka pravého tlačítka a dialog
  s ozubeným kolem):
  - **Orientace**: automatická (vodorovně, když je okno širší než vyšší), vodorovně, nebo svisle
    (sloupce: frekvence roste směrem nahoru, vodopád vlevo se posouvá zprava doleva);
    volitelně nízké frekvence nahoře;
  - **Zobrazit vodopád** a **Velikost spektra** (20–80 % okna);
  - **Šum jako čára (vodorovně)** (jen vodorovně): okamžité úrovně jako čára a doznívající úrovně nad prahem
    vyplněné;
  - **Zobrazit okamžité úrovně pod prahem** (vypnuto = jen to, co vystoupí nad práh);
  - **Doznívání signálu** (pomalé / střední / rychlé — rychlé pro SSB a přeplněná pásma, pomalé pro klidná pásma);
  - **Pozadí** (černé, šedé, bílé);
  - **Klik přichytí na signál (±2 kHz)** a **Při ladění vymazat spektrum (bez rozmazání)** (omezí rozmazání při
    změně frekvence);
  - značky signálů, filtr značek, spoty, citlivost na statiku a spoty @frekvence (viz výše).

Vstup je otevřený jen po dobu, kdy je okno otevřené (a pro další uživatele audia — CW dekodér, nahrávání
závodu), a po zavření se uvolní. Nic v okně nevysílá; jen ladí rig.

## Nahrávání závodu

Obdoba **QSO recording** v N1MM / **Audio recorder** v DXLogu. **Závod → Nahrávat závod (zap / vyp)**:

- audio přijímače (Nastavení → Audio → Vstup přijímače) se zapisuje do souborů WAV po hodinách UTC:
  `…/MacContestLogger/recordings/20261128-12.wav` (12 kHz, 16 bitů, mono — asi 86 MB za hodinu),
- v okně zápisu svítí `● REC` a nastavení se pamatuje i po restartu,
- **Přehrát nahrávku QSO** v kontextové nabídce řádku deníku přehraje 10 s před a 5 s po čase QSO (spor
  o volací značku nebo číslo),
- po restartu v rámci téže hodiny nahrávání pokračuje do stejného souboru.
