# TOUR, QSO party (rover, county line, bonusové stanice) a spoty

Textové příkazy z N1MM+
([Callsign Box Text Commands](https://n1mmwp.hamdocs.com/manual-windows/entry-window/),
[Rover, Mobile and County Line Support](https://n1mmwp.hamdocs.com/manual-supported/contests-setup/setup-qsop-contests/#Rover_Mobile_and_County_Line_Support))
a DXLogu (`SPOTME`). Obecný seznam příkazů je v [text-commands.md](text-commands.md).

## TOUR – závody se sezeními

Některé závody (hlavně ruské a ukrajinské) se jedou v sezeních a tutéž
stanici lze v každém sezení udělat znovu.

| Příkaz | Akce |
|---|---|
| `TOUR 1200/30` | sezení začínají ve 12:00 UTC a trvají 30 minut. Duplicity se kontrolují jen v rámci sezení |
| `TOUR` | parametry z pole **Snt** (jako N1MM, např. `1200/30`). Když tam nejsou, ukáže aktuální nastavení a začátek běžícího sezení |
| `NOTOUR` / `TOUROFF` | bez sezení, duplicity za celý závod (vypne i sezení z definice závodu) |

- Formát je `hhmm/mm`; délku lze zadat i jako `hhmm` (`2100/0100`).
  Nejkratší sezení je 5 minut.
- Sezení na sebe plynule navazují, i přes půlnoc.
- Nastavení se **ukládá se závodem** (N1MM ho po restartu zapomene) a
  skóre se okamžitě přepočítá.
- Zadávací okno ukazuje `TOUR 1200/30 do 1230Z` (konec běžícího sezení).
- Při přechodu do dalšího sezení přijde zpráva „Nové sezení závodu
  1230Z–1300Z“ (stavový řádek + zprávy) — obdoba
  **Period autoswitch** z DXLogu.

### Periody v definici závodu

Závod se sezeními je nemusí mít nastavené ručně — stačí je
uvést v definici YAML („Nástroje → Editor
definic“):

```yaml
period:
  durationHours: 4
  sessions: { start: "1200", minutes: 60 }   # sezení po hodině od 12:00 UTC
```

Po otevření závodu se sezení zapnou sama. Příkaz
`TOUR hhmm/mm` je přepíše (uloží se se závodem), `NOTOUR` je vypne.

## Rover – ROVERQTH

| Příkaz | Akce |
|---|---|
| `ROVERQTH HAM` | můj aktuální okres. Ukládá se do dat stanice (Rover QTH), takže přežije restart |
| `ROVERQTH` | dialog s aktuální hodnotou |

- Okres se vysílá ve výměně (pole se zdrojem `ROVER_QTH`, viz níže)
  a CW makrem `{ROVERQTH}`.
- Ukládá se ke každému QSO, takže Cabrillo má na každém řádku okres, odkud
  jste skutečně vysílali.
- **Z nového okresu lze tutéž stanici udělat znovu:** duplicita se počítá
  zvlášť pro každý můj okres.
- Zadávací okno ukazuje `Rover HAM`.

## County line – COUNTYLINE

| Příkaz | Akce |
|---|---|
| `COUNTYLINE DAD,JEF,WAL` | vysílám z hranice okresů (county line) |
| `COUNTYLINE` | dialog (prázdné = konec county line) |
| `NOCOUNTYLINE` | konec county line |

- Každé QSO se zapíše **jednou za každý okres** (N1MM: 3 okresy = 3 QSO
  v deníku), s tím okresem v odeslané výměně.
- Všechny kopie mají odvysílané pořadové číslo. Protistanice si zapíše jedno
  číslo a další QSO pak má číslo vyšší o počet kopií.
- CW makro `{COUNTYLINE}` vysílá `DAD/JEF/WAL`. V režimu county line se `{ROVERQTH}`
  ignoruje a naopak, takže jedna sada zpráv slouží oběma režimům (N1MM).
- County line se neukládá (jako v N1MM); po restartu se musí zadat znovu.
- **Protistanice na county line:** napište její okresy do přijímaného pole jako `ORDES/JEF` (zkratka za
  `ORDES/ORJEF`, okresy jednoho státu) nebo `IDFRA/UTCAC` (dva státy). Zapíše se jedno QSO za každý okres (N1MM 7QP).
  Je k tomu potřeba `split: true` u přijímaného pole okresu (přidejte ho do definice vytvořené ze šablony
  „Nová QSO party…“: `- { id: qth, type: DISTRICT, required: true, split: true }`). Složenou hodnotu
  zadejte při zápisu QSO; úprava už zapsaného QSO s jedním okresem na složené QSO nepřidá.
- Zadávací okno ukazuje `County line DAD/JEF/WAL`.

## Bonusové stanice – BONUS

| Příkaz | Akce |
|---|---|
| `BONUS W1AW, K1BON` | seznam bonusových stanic (oddělených čárkou nebo mezerou) |
| `BONUS` | dialog s aktuálním seznamem (prázdné = smazat) |

- Stačí základ volací značky: `W1AW` platí i pro `W1AW/M` nebo
  `W1AW/ESX`. V N1MM se musí vypsat každá varianta.
- Seznam se **ukládá se závodem** a skóre se okamžitě přepočítá.
- Kolik bodů bonus dává a jak často, určuje definice
  závodu (viz níže).
- Zadávací okno ukazuje `Bonus 2` (počet stanic).

## Spoty do DX clusteru

| Příkaz / klávesa | Akce |
|---|---|
| **Spot It** (tlačítko), **Alt+P** | spotuje volací značku z pole na aktuálním kmitočtu. Když je pole prázdné, spotuje poslední zapsané QSO (N1MM) |
| `SPOTME` / `SPOTME CQ TEST` | spotuje vlastní stanici s komentářem (výchozí „CQ“), DXLog |

- Odešle se `DX <kHz> <volací značka> <komentář>`. DX cluster musí být připojený.
- **Self-spotting je v mnoha závodech zakázaný** a stavový řádek na to
  upozorní. Zkontrolujte si pravidla závodu.

## Definice závodu (YAML)

Aby rover, county line a bonusové stanice něco dělaly, musí je definice QSO party
popisovat:

```yaml
exchange:
  sent:
    - { id: rst, type: RST,  source: AUTO_RST }
    - { id: qth, type: TEXT, source: ROVER_QTH }    # můj okres (ROVERQTH / COUNTYLINE)
  received:
    - { id: rst,  type: RST,  required: true }
    - { id: cnty, type: TEXT, required: true }

scoring:
  qsoPoints: { mode: FIRST_MATCH, default: 1 }
  bonuses:
    # 100 bodů za bonusovou stanici, jednou na pásmo a mód
    - { id: bonus, when: { bonusStation: true }, value: { fixed: 100 }, scope: PER_BAND_MODE }
  total: "qsoPoints * multTotal + bonusPoints"
```

- `source: ROVER_QTH`: hodnota pole je okres roveru, v county line
  okres dané kopie QSO. Jen závod s takovým polem počítá duplicitu
  zvlášť pro každý můj okres a zapisuje QSO za každý okres county line.
- Predikát `bonusStation: true`: protistanice je na seznamu `BONUS`.
- `scoring.bonuses` se nyní skutečně vyhodnocuje. Každý bonus s podmínkou `when`
  se přizná jednou za `scope` (`ONCE`, `PER_BAND`, `PER_MODE`, `PER_BAND_MODE`);
  duplicita bonus nedostane. Do skóre vstupuje jako proměnná `bonusPoints` ve
  vzorci `total`.

## Seznamy okresů

Okresy QSO party (nebo okresy / sekce jiného závodu) jsou v datech závodů
**sadou násobičů**. Seznam se do aplikace načte v
**„Nástroje → Editor definic → Importovat okresy…“**:

1. vyberte soubor se seznamem — řádky `CODE,Name` (jako oddělovač také `;`, tabulátor
   nebo mezera, `#` komentář, hlavičkový řádek `Code,County` se přeskočí),
2. zadejte id sady (`ohqp_counties`) — vytvoří se `multipliers/<id>.yaml` + `.csv`,
3. **„Nová QSO party…“** vytvoří definici ze šablony: vysílám
   svůj okres (`ROVERQTH`), přijímám okres (stanice ze státu) nebo
   stát, násobiče okresy (`<id>_counties`) a státy/provincie (`na_areas`),
   CW 2 body, fone 1 bod — body a pravidla upravte podle pravidel
   dané party.

S načtenou sadou se okresy kontrolují: `ROVERQTH` a `COUNTYLINE` upozorní na
okres, který v seznamu není, okno **„Okresy“** ukazuje udělané /
chybějící okresy a přijatý okres mimo seznam je v tabulce deníku
varováním.

## Vestavěné QSO party

Vestavěné jsou QSO party California (CQP), Florida (FQP), New England (NEQP), 7th Call Area (7QP), Indiana (INQP)
a Delaware (DEQP), včetně seznamů okresů.

- **Ve státě, nebo mimo stát** se řídí **sekcí ARRL** v datech stanice (jako v N1MM): sekce státu
  party z vás dělá stanici ve státě (pro CQP kalifornské sekce EB, LAX, ORG, SB, SCV, SDG, SF, SJV,
  SV; pro 7QP AZ, EWA, ID, MT, NV, OR, UT, WWA, WY). Při vytvoření deníku stavový řádek řekne, kterou z nich
  jste; stanice mimo USA a Kanadu by měla mít sekci `DX`, jinak dostane výzvu k opravě.
- Stanice ve státě dělají všechny a počítají státy / provincie (okres státu party se počítá jako ten
  stát) a tam, kde to pravidla říkají, i země DXCC; stanice mimo stát smějí dělat jen stát party a počítají
  jeho okresy. QSO se stanicí mimo stát z venku se zapíše s varováním a nic nepřinese.
- Nastavte **ROVERQTH** na svůj okres (ve státě) nebo svůj stát / provincii (mimo stát): to se vysílá.
- Mobilní stanice v jiném okrese je nová stanice (`dupe.byField`); stanice na county line se zapíše jako `ALC/BAK`.

| Party | Okresy (přijímaný kód) | Body | Násobiče |
|---|---|---|---|
| 7QP | 259, stát + okres (`ORDES`, `AZYVP`) | fone 2, CW 3, digi 4 | mimo: okresy jednou; uvnitř: 50 států, 13 provincií a nejvýš 10 zemí DXCC jednou |
| Indiana | 92, `IN` + okres (`INMRN`) | 2 za QSO CW nebo fone | všichni: okresy jednou za mód; uvnitř i ostatních 49 států a 13 provincií (bez DX) |
| New England | 68, stát + okres (`MAMID`) | fone 1, CW a digi 2 | mimo: okresy jednou; uvnitř: státy, provincie a země DXCC jednou |
| Delaware | 3: `NDE` New Castle, `KDE` Kent, `SDE` Sussex | uvnitř: fone 1, CW a digi 2; mimo: 10 a 20 | za pásmo: mimo okresy; uvnitř státy, provincie a země DXCC; × výkon (QRP 3, LOW 2, HIGH 1) |

Stanice ve státě u 7QP, Indiany a Delaware správně započítají i okresy ostatních party téhož víkendu:
okres jako `ORDES`, `INMRN`, `MAMID` nebo `NDE` se počítá jako jeho stát (sada `qp_weekend_qth`). Definice Delaware
vynechává bonus 50 bodů za elektronický deník, spojení stanic ve státě na 6 m a výš a deník FT8/FT4,
který pravidla chtějí jako samostatný soubor s výměnou Field Day.

## Společný deník téhož víkendu (IN7QPNE)

O prvním květnovém víkendu běží QSO party 7QP, Indiana, New England a Delaware současně a jejich
pořadatelé přijímají jeden deník pro všechny (N1MM **IN7QPNE**). Stanice **mimo všechny čtyři oblasti** zvolí závod
**„7QP + Indiana + New England + Delaware QSO Parties (combined, IN7QPNE)“**:

- Vysílejte RS(T) a svůj stát / provincii nebo `DX` (nastavte **ROVERQTH**).
- Přijatý okres zapište přesně tak, jak byl vyslán. Kód určuje party, její body za QSO a její násobič:
  `ORDES` je 7QP, `INMRN` Indiana, `MAMID` New England, `NDE` Delaware. Cokoli jiného není stanice čtyř
  party: zapíše se s varováním a nic nepřinese.
- County line se zadává jako `ORDES/JEF` (zkratka za `ORDES/ORJEF`, okresy jednoho státu), `IDFRA/UTCAC` (dva
  státy) nebo `INMRN/HAM`; zapíše se jedno QSO za každý okres.
- Každá party se hodnotí podle vlastních pravidel a skóre je jejich součet. Okno Skóre ukazuje každou party:
  `7QP: points 5 × multipliers 1 = 5  ·  Indiana: … =  score 76`. Výkonový koeficient Delaware platí jen pro
  část Delaware (výkonová kategorie z nastavení závodu).
- Stanici lze udělat jednou na pásmo a mód, mobilní stanici znovu z každého okresu. Indiana nemá digitální QSO a
  New England nemá 160 m; taková QSO pro tu party nic nepřinesou.
- Stejný soubor Cabrillo (`CONTEST: IN7QPNE`) pošlete všem čtyřem pořadatelům; každý si vyhodnotí svá QSO.

Stanice uvnitř jedné z oblastí používá vlastní definici dané party; definice pro stanice ve státě už počítají
okresy ostatních party jako jejich státy.

Definice používá `scoring.parts` (viz [definition-editor.md](definition-editor.md)); verze, které to neznají,
ukazují jediný součet všech bodů krát všechny okresy.

Zdroje: [pravidla 7QP](https://www.7qp.org/) a jeho seznam okresů (States & Counties), [pravidla Indiana QSO
Party](https://www.hdxcc.org/inqp/rules.html) a [okresy](https://www.hdxcc.org/inqp/counties.html),
[pravidla New England QSO Party](https://www.neqp.org/rules), [pravidla Delaware QSO
Party](https://www.fsarc.org/qsoparty/rules-2024.html), [nastavení QSO party v N1MM+](https://n1mmwp.hamdocs.com/manual-supported/contests-setup/setup-qsop-contests/).

## Seznamy sekcí v dialogu závodu

Podobně jako **Edit Section List** a **Import Section List** v N1MM vypisuje dialog závodu (Soubor → Nový závod…,
Soubor → Nastavení závodu…) seznamy okresů / sekcí zvoleného závodu:

- **Upravit seznam…** otevře seznam jako řádky `CODE,Name`; **Uložit** ho zapíše a znovu načte
  data závodů. První uložení si ponechá seznam dodaný s daty závodů.
- **Obnovit původní** vrátí dodaný seznam.

Upravený seznam se při aktualizaci definic („Nástroje → Aktualizovat definice“) nepřepíše.
