# Data DXCC a Club Log

Deník odvozuje entitu DXCC, kontinent, zónu CQ a název země každé volací značky lokálně. Výsledek
určuje násobiče zemí a zón, body mnoha závodů (`dxccIn`, vlastní/jiný kontinent), pole `DXCC`, `COUNTRY`
a `CONT` v deníku a jeho exportech, mapu, řádky okna Info a rozbor spotů.

## Zdroje

| Zdroj | Kde | Použije se, když |
|--------|-------|-----------|
| Vlastní přiřazení | `<data folder>/dxcc-overrides.json` (viz níže) | vždy, pro volací značky v něm |
| Importovaný seznam zemí | `<data folder>/country/cty.dat` (viz níže) | soubor existuje (nahrazuje zdroje níže) |
| Club Log `cty.xml` | `<data folder>/clublog/` (stahuje aplikace) | přepínač níže je zapnutý **a** kopie je stažená |
| `cty.dat` (AD1C) | `~/dxcc-json/cty.dat` | jinak, pokud soubor existuje |
| `dxcc.json` | `~/dxcc-json/dxcc.json` | jinak |

Datová složka je `~/Library/Application Support/MacContestLogger` (nebo složka v `MCL_DATA_DIR`).
Bez kteréhokoli z nich není jádro závodů k dispozici (viz [Začínáme](zaciname.md)).

## Varování: deník byl vyplněn starší tabulkou zemí

Obdoba varování N1MM, které se zobrazí při otevření databáze, jejíž tabulka zemí je starší než
stažený soubor zemí.

- Každá databáze si pamatuje, **jakými daty DXCC byla její QSO vyplněna**: zdroj
  (Club Log `cty.xml`, `cty.dat` nebo `dxcc.json`) a jeho datum — poslední úspěšné
  stažení z Club Logu, jinak datum změny datového souboru. Vlastní
  přiřazení (`dxcc-overrides.json`) do něj nepatří.
- Razítko se zapíše při otevření **nové nebo prázdné databáze** (také při spuštění
  a po stažení z Club Logu, dokud je deník ještě prázdný) a po
  **Nástroje → Přepočítat DXCC v deníku…**.
- Když se otevře databáze (také při spuštění) a její razítko je **starší** než
  aktuální data, oznámí to stavový řádek a zprávy okna Info, například
  *Deník byl vyplněn starší tabulkou zemí (cty.dat, 2026-03-01) než je aktuální
  (clublog, 2026-10-12) — použij Nástroje → Přepočítat DXCC v deníku…*. Varování
  se vrací při každém otevření, dokud se deník znovu nevyplní.
- Databáze s QSO, ale **bez razítka** (vytvořená starší verzí) dostane aktuální
  razítko potichu, bez varování — jakými daty byla vyplněna, nelze zjistit.
- Razítko patří celé databázi, kdežto nové vyplnění přepočítá QSO
  otevřeného závodu; je-li v jedné databázi více závodů, vyplňte znovu každý z nich.

## Přiřazení volací značky k zemi

Obdoba N1MM **Add call to country**. **„Nástroje → Přiřadit volačku k zemi…“** otevře okno s volací značkou
(tou, která je napsaná v zadávacím okně), prohledávatelným seznamem zemí načtených dat zemí (název, prefix nebo číslo
DXCC) a tlačítkem **Přiřadit**. Seznam **Vlastní přiřazení** níže ukazuje všechna přiřazení s tlačítkem **Odebrat**.

- Přiřazení se ukládají do `<data folder>/dxcc-overrides.json` a mají přednost **před** `cty.xml` z Club Logu
  i před daty v `~/dxcc-json`, takže přiřazená značka dostane tuto zemi, název, kontinent a zóny všude (deník,
  násobiče, spoty, mapa, exporty).
- Značka se shoduje **přesně** (velkými písmeny); `/P`, `/M` a `/QRP` za ní na shodě nic nemění. Jiný prefix nebo
  sufix (`DL/OK1XYZ`, `OK1XYZ/MM`) se vyhledá normálně.
- Změna platí okamžitě pro **příští vyhledání**. QSO už zapsaná v deníku si ponechají zemi, se kterou byla zapsána, až
  do **Nástroje → Přepočítat DXCC v deníku…** (okno to nabízí jako tlačítko); skóre otevřeného závodu se
  přizpůsobí při jeho přepočítání.
- Přiřazení s číslem DXCC, které data zemí neobsahují, se ignoruje.

## Import seznamu zemí ze souboru

Obdoba N1MM **Import country list from downloaded file**. **„Nástroje → Importovat seznam zemí ze
souboru…“** si vyžádá soubor `cty.dat` ve formátu AD1C / country-files.com (například vlastní `wl_cty.dat`
závodu).

- Soubor se nejprve zkontroluje: soubor bez jediného záznamu země se odmítne a používaná data zůstanou.
- Přijatý soubor se zkopíruje do `<data folder>/country/cty.dat` a hned se stane zdrojem DXCC, před `cty.xml`
  z Club Logu a daty v `~/dxcc-json` (ty zůstanou nedotčené). Čísla entit se stále berou z
  `~/dxcc-json/dxcc.json`. Vlastní přiřazení mají i nadále přednost.
- **„Nástroje → Odstranit importovaný seznam zemí“** kopii smaže a vrátí se ke Club Logu / lokálním datům.
- V obou případech se znovu načtou data závodu a razítko zemí deníku se porovná, jak je popsáno výše; chcete-li,
  aby se zapsaná QSO přizpůsobila, vyplňte deník znovu přes **Nástroje → Přepočítat DXCC v deníku…**.

## Club Log `cty.xml`

Club Log zveřejňuje svůj soubor zemí s výjimkami pro konkrétní značky (DXpedice, speciální stanice),
neplatnými provozy a výjimkami zón, vše s daty platnosti. MacContestLogger jej může používat jako
zdroj DXCC:

- **Nastavení → Score Reporting → DXCC z Club Logu (cty.xml)**: přepínač *Používat DXCC z Club Logu*
  (ve výchozím stavu zapnutý) a tlačítko *Aktualizovat DXCC z Club Logu*. Stejná aktualizace je v menu
  *Nástroje → Aktualizovat DXCC z Club Logu*.
- Ke stažení je potřeba **API klíč** Club Logu zadaný ve skupině Club Log Live Stream výše
  (`https://cdn.clublog.org/cty.php?api=<key>`). Bez klíče se nic nestahuje.
- **Při spuštění** se soubor stáhne na pozadí, když je přepínač zapnutý, klíč je zadaný a poslední
  stažení *nebo pokus* je starší než 24 hodin. **Na vyžádání** se stáhne, když je poslední úspěšné
  stažení starší než 24 hodin; jinak stavový řádek řekne, kdy bude další stažení
  možné.
- Pravidla provozu Club Logu jsou dodržena: nejvýš jedno stažení `cty.xml` za den, každé vyhledání je lokální,
  do Club Logu se nikdy nic neposílá kvůli jednotlivému QSO.
- Každé stažení se zaznamená do `clublog.log` v datové složce (požadavek s `api=***`, stav HTTP,
  velikost a výsledek); API klíč se tam nikdy nezapisuje.
- Složka `clublog/` obsahuje surový soubor (`cty.xml`), jeho zpracovanou kompaktní podobu (`cty.json`, načítá se
  při spuštění) a čas posledního stažení a pokusu (`cty-state.json`).
- Neúspěšné stažení (offline, chyba HTTP, odmítnutý klíč, poškozený soubor) ponechá poslední kopii; bez kopie
  zůstávají zdrojem lokální data. Výsledek se ukáže ve stavovém řádku, v Nastavení a ve zprávách okna
  Info.
- Po úspěšném stažení a při změně přepínače se znovu načtou data závodu a otevřený
  závod se přepočítá s novým zdrojem.

### Pořadí vyhledávání

1. **Výjimka** — celá volací značka, jak byla zapsána, s výjimkou platnou k datu QSO.
2. **Neplatný provoz** — značka je k tomu datu uvedena jako neplatná: žádná entita DXCC.
3. `/MM` (námořní mobil) a `/AM` (letecký mobil) se nepočítají do žádné entity; `/P`, `/M`, `/QRP`, `/A`,
   `/R`, `/LH`, `/B`, `/J` se ignorují.
4. **Prefix** — nejdelší prefix platný k datu QSO, vzatý z kratší části portable
   značky (`DL/OK1XOE`, `OK1XOE/DL` → `DL`); jednociferný sufix posouvá oblast značky
   (`UA1ABC/9` → `UA9`).
5. **Výjimka zóny** — volací značka s vlastní zónou CQ k danému datu přepíše zónu.

Číslo DXCC (ADIF) výsledku je číslo Club Logu. `cty.xml` neobsahuje zóny ITU a názvy zemí píše
velkými písmeny, proto se název a zóny ITU berou z lokálních dat (`~/dxcc-json`), pokud znají
stejné číslo DXCC.

### Které datum se použije

- Každé QSO se vyhodnocuje k **vlastnímu času**: vyplnění země při zápisu nebo importu,
  *Přepočítat DXCC v deníku…*, body a násobiče jádra závodů při zápisu, při přehrání nebo přepočtu
  otevřeného závodu, kontrola přesunu násobičů a `mcl-scorecheck` (datum a
  čas každého řádku Cabrillo `QSO:`). Přepočet starého deníku proto dá stejný výsledek jako v době, kdy
  byl zapsán.
- Živé značky, které ještě nejsou QSO — spoty, bandmapa, řádky okna Info, mapa, náhled v zadávacím
  okně — používají **aktuální datum**.
