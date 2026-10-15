# DX cluster

![Okno DX clusteru se spoty](../img/dx-cluster.png)

![Bandmapa se spoty a stínovaným bandplánem](../img/bandmap.png)

## Více souběžných spojení (nody + skimmery)

Obdoba DXLog.net **DXC** (několik nodů a skimmerů najednou). Kromě
hlavního spojení z okna **DX Cluster** mohou běžet další:

1. **„Nastavení → DX Cluster“**: u oblíbeného clusteru zaškrtněte
   **„Souběžně“** (např. RBN `telnet.reversebeacon.net:7000`,
   lokální CW Skimmer Server, druhý node).
2. Po OK (a při každém startu) se souběžné oblíbené clustery samy připojí
   a **přihlásí** uloženým jménem (volačkou).
3. Spoty ze všech spojení jdou do **jedné bandmapy** a jedné paměti spotů (stejné
   filtry, blacklist, barvy násobičů). Výpis v okně DX Cluster
   ukazuje řádky ze souběžných spojení s předponou `[name]`.
4. Pod stavem hlavního spojení je řádek `Souběžně: RBN ✓ · Skimmer ...`
   (✓ přihlášeno, ... připojeno, ✗ odpojeno). Spadlé
   spojení se znovu otevře po dalším uložení nastavení.
5. Stejný řádek v okně DX Cluster slouží jako rychlý přepínač: za **„Souběžně“**
   je jedno zaškrtávátko pro každý oblíbený cluster (se značkou jeho stavu), takže můžete příjem
   spotů z RBN zastavit, nebo znovu spustit, aniž byste otevírali nastavení. Zaškrtnutí
   nebo odškrtnutí funguje jako zaškrtávátko v Nastavení → DX Cluster plus OK: uloží se
   (takže přežije restart a Nastavení ukazuje totéž) a spojení
   se otevře a přihlásí, nebo zavře („Souběžné spojení ukončeno“).

Oblíbený cluster, ke kterému je hlavní okno právě připojené, se jako souběžný
nezdvojuje; v přepínači se nenabízí a nelze ho zaškrtnout, dokud ho
hlavní okno používá. Odškrtnutí **„Souběžně“** spojení zavře. Příkazy z
okna DX Cluster jdou jen do hlavního spojení.

## CW Skimmer / RBN

Obdoba N1MM **CW Skimmer and the Reverse Beacon Network**
([dokumentace](https://n1mmwp.hamdocs.com/manual-windows/telnet-window/#CW_Skimmer_and_the_Reverse_Beacon_Network_RBN_))
a DXLog **DX cluster own station spots**.

- **Spojení**: RBN (`telnet.reversebeacon.net`, port 7000 CW / 7001 digi) nebo
  lokální CW Skimmer Server jako oblíbený cluster — ideálně **souběžně** s
  běžným nodem.
- **Rozpoznání**: spot ze skimmeru = spotter končí na `-#` nebo má komentář
  tvar `19 dB 28 WPM CQ`.
- **Počet skimmerů**: tutéž stanici hlášenou několika skimmery (v rozmezí 1 kHz)
  počítá jako jeden spot s počtem potvrzení; bandmapa ukazuje `OK1XOE ×3`.
- **Filtr** (Nastavení → DX Cluster → „Skimmer spoty: min. skimmerů“): `0` skryje spoty ze skimmerů, `1` ukáže všechny, `2` a víc
  ukáže jen stanice potvrzené aspoň tolika skimmery — odfiltruje
  „rozbité“ spoty se špatně dekódovanou volačkou. Spoty od lidí se ukazují vždy.
- **Vlastní spoty**: když mě slyší RBN / skimmer, přijde do zpráv okna Info
  zpráva „RBN: ... hears you on 14025.0 kHz, 19 dB, 28 WPM“.

## Sdílení telnetu po síti

Obdoba N1MM **Multi-User telnet** a DXLog.net **DXC** v síti. V
síťovém deníku (synchronizace clusteru přes MQTT) stačí, aby DX cluster měla připojený
**jedna** stanice:

- každý spot, který stanice přijme ze svého clusteru (hlavního i souběžného), se
  pošle přes broker do tématu `spot/new` (QoS 0, bez retain),
- ostatní stanice ho vloží do své bandmapy — stejné barvy, filtry, blacklist;
  dál se nepřeposílá a stanice nedostane zpět své vlastní spoty,
- zapíná se v **„Nastavení → Cluster → Sdílet spoty z DX clusteru“**
  (výchozí zapnuto; stačí
  na stanicích, které mají spoty posílat / přijímat).

Broker musí stanicím povolit `spot/#` — viz `docs/cluster-aclfile`
(`pattern readwrite spot/#`). Autorita (samostatná javová aplikace,
`cluster-app`, Java 21, která není součástí tohoto repozitáře) spoty nezpracovává.

## Automatický split z komentáře spotu

Obdoba N1MM **Split Mode and Frequencies Set Automatically from Cluster Spots**
([dokumentace](https://n1mmwp.hamdocs.com/manual-operating/single-operator-contesting/#Split_Mode_and_Frequencies_Set_Automatically_from_Cluster_Spots))
a DXLog **DX cluster → auto split**. Po kliku na spot (bandmapa, okno
clusteru, Ctrl+↑/↓) se z komentáře spotu přečte vysílací frekvence a zapne se
split (vysílání na VFO B):

| Komentář | Vysílám na (spot 14023.0) |
|---|---|
| `UP 5`, `up5`, `UP 2-4` | +5 / +5 / +2 kHz → 14028 / 14028 / 14025 |
| `UP 1.5` | 14024.5 |
| `UP` | výchozí posun: +1 kHz (CW), +5 kHz (fone podle komentáře) |
| `DOWN 3`, `DN 3` | 14020 |
| `QSX 14025.5` | 14025.5 |
| `QSX 025`, `QSX25` | doplněno z frekvence spotu → 14025 |

- Split dál než 100 kHz od spotu se ignoruje (překlep, jiné pásmo).
- Spot bez splitu vypne split, který zapnul předchozí spot;
  ručně zapnutý split (Ctrl+S, Alt+F7) zůstane.
- Vypíná se v **„Nastavení → DX Cluster → Automatický split z komentáře
  spotu“**.

## Okno DX Cluster (okno Telnet z N1MM)

Podle okna [Telnet](https://n1mmwp.hamdocs.com/manual-windows/telnet-window/) z N1MM Logger+.

**Textový panel.** Řádky clusteru neproporcionálním písmem, které se řídí ovladačem velikosti písma okna (vpravo nahoře).
Řádky spotů jsou barevně odlišené podle módu jako v N1MM — CW modře, digi purpurově, fone barvou textu (mód, který bandmapa
odvodí: komentář, digitální frekvence, bandplán). Spot, který [filtr spotů](#filtr-spotů-pásma-módy-původ-spotteru-pracovatelné)
jinde skryje, zůstane v panelu **zašedlý**. Klik do textu zastaví posouvání (pro přečtení nebo zkopírování řádku);
odjetí ukazatelem z panelu ho obnoví.

**Tlačítka.** Deset programovatelných tlačítek (pravý klik tlačítko upraví). Tlačítko může obsahovat packet/telnet makra N1MM:

| Makro | Význam |
|---|---|
| `{WAIT}` | počká 5 sekund, než se pošle zbytek tlačítka (`SH/WWV{WAIT}SH/WCY`) |
| `{CONN} name` | připojí se ke clusteru `name` ze seznamu (jeho jméno, host nebo `host:port`) a přihlásí se jeho přihlašovacím jménem; aktuální spojení se nejdřív zavře (`{CONN} RBN`) |

Stisky čekají za tlačítkem, které je ještě ve svém `{WAIT}`.

**Možnosti… → Clustery** (záložka Clusters z N1MM); každá změna platí a ukládá se hned:

| Volba | Význam |
|---|---|
| Při otevření okna se připojit a přihlásit… | auto logon z N1MM: když se okno otevře a nic není připojené, připojí se k vybranému clusteru a přihlásí se (výchozí vypnuto) |
| Software clusteru | DXSpider, AR-Cluster, CC Cluster nebo **Rozpoznat automaticky**: rozpozná se pozdrav nodu (`running DXSpider`, `AR-Cluster`, `CC Cluster`); do té doby se předpokládá DXSpider. Určuje formát příkazů, které MCL sestavuje sám: DXSpider `SH/DX 30`, AR-Cluster a CC Cluster `SH/DX/30` (zaškrtávátko „DXSpider cluster“ v N1MM) |
| Počet spotů pro SH/DX z bandmapy | kolik spotů si vyžádá tlačítko **SH/DX** bandmapy (1–100, výchozí 30) |
| Zobrazit tlačítka příkazů | N1MM „Show Telnet Buttons“: skryje tlačítka a ušetří místo |
| Uložit / Načíst tlačítka… | uloží deset tlačítek do textového souboru (`label,command` na řádek, komentáře `#`) a takovou sadu načte zpět; kratší soubor ponechá pro zbytek výchozí tlačítka |

### Seznam clusterů, uložené spoty, náhodné frekvence

- **Nastavení → DX Cluster → Importovat / Exportovat seznam…** (import/export seznamu clusterů z N1MM): textový soubor s jedním
  clusterem na řádek, `name,host:port[,login]`, `#` začíná komentář. Hesla se nikdy neexportují. Import přidá jen
  clustery, jejichž `host:port` v seznamu ještě není; jako každá změna Nastavení platí po Uložit.
- **Nastavení → DX Cluster → Vybrat ze seznamu…** (*Live cluster list* z N1MM): viz
  [Veřejný seznam clusterů](#veřejný-seznam-clusterů) níže.
- **Možnosti… → Uchovat spoty přes restart programu** (N1MM „Save Spots“, výchozí vypnuto): při ukončení se paměť spotů
  zapíše do `spots.json` v datové složce; po startu se spoty, které jsou ještě v limitu *Buffer spotů (min)*,
  vrátí se svými původními časy (volačky na blacklistu zůstanou venku). S vypnutou volbou se soubor při ukončení
  smaže.
- **Možnosti… → Náhodně posunout kmitočet při naladění spotu** (N1MM „Randomize incoming spot frequencies“, výchozí
  vypnuto): naladění spotu z clusteru (klik, skoky po spotech) skončí 50–150 Hz (fone 100–250 Hz) nad ním nebo pod ním,
  aby operátoři, kteří kliknou na stejný spot, nevolali všichni přesně na stejné frekvenci. Vlastní spoty (Mark, Store)
  se ladí přesně; split z komentáře spotu se nemění.
### Veřejný seznam clusterů

*Live cluster list* v N1MM pochází z vlastního reportovacího serveru N1MM, který nemá veřejné rozhraní. MacContestLogger
místo toho udržuje vlastní seznam v repozitáři projektu:
[`cluster-data/clusters.json`](../../cluster-data/clusters.json).

**Výběr clusteru.** *Nastavení → DX Cluster → Vybrat ze seznamu…* otevře seznam:

- **Hledat** filtruje podle každého napsaného slova (jméno, volačka, host, země, místo, lokátor, software,
  poznámky; bez ohledu na velikost písmen a diakritiku). **Včetně skimmerů (RBN)** ukáže nebo skryje zdroje ze skimmerů.
- **Řadit podle**: *Hodnocení* (nejlepší napřed, nehodnocené nakonec), *Země* nebo *Název*.
- Každý řádek ukazuje jméno a volačku, `host:port`, zemi, software, značku skimmeru a hodnocení, pak nápovědu
  k přihlášení, poznámky a datum, kdy byl záznam naposledy ověřen.
- **Přidat do clusterů** nebo dvojklik přidá vybraný cluster jako nový oblíbený, který se přihlašuje
  volačkou stanice (Nastavení → Stanice). Cluster, jehož `host:port` už mezi oblíbenými je, se nepřidá
  podruhé. Jako každá změna Nastavení se nový oblíbený cluster zachová až po **Uložit**.
- Řádek pod seznamem říká, která kopie se ukazuje (ta dodaná s programem, nebo ta stažená z
  GitHubu), a její datum.

**Aktualizace seznamu.** Program kvůli tomuto seznamu nikdy sám nejde na internet. **Aktualizovat seznam z GitHubu**
stáhne `cluster-data/clusters.json` z větve `main` na
`raw.githubusercontent.com`, odkud přicházejí i aktualizace definic závodů. Stažení:

- kontaktuje jen tuto jednu adresu (přesměrování na jiného hostitele se nesleduje) a zastaví se po 256 KB;
- se zkontroluje, než se cokoli zapíše: musí mít formát seznamu a aspoň jeden platný záznam; jinak
  zůstane aktuální seznam a ukáže se důvod;
- se uloží jako `cluster-data/clusters.json` v datové složce a od té doby se používá, pokud novější verze programu
  nedodá novější seznam (vyhrává kopie s pozdějším datem `updated`);
- s nastaveným `MCL_INERT_NETWORK` nedělá nic (tlačítko oznámí, že síť je vypnutá).

**Formát souboru** (JSON, UTF-8):

| Klíč | Povinný | Význam |
|---|---|---|
| `schema` | ano | Verze formátu. Tato verze čte `1`; soubor s vyšším číslem se ignoruje (je určený pro novější verze programu), takže starší programy si ponechají svůj aktuální seznam |
| `updated` | | Datum seznamu, `yyyy-MM-dd` |
| `clusters` | ano | Záznamy |
| `name` | ano | Jméno zobrazené v seznamu a dané oblíbenému clusteru |
| `host`, `port` | ano | Telnetová adresa (jméno hostitele nebo adresa IPv4) a port 1–65535 |
| `callsign` | | Volačka nodu |
| `country`, `dxcc` | | Název země a číslo entity DXCC |
| `location`, `grid` | | Místo a lokátor Maidenhead |
| `software` | | Software clusteru (DXSpider, AR-Cluster, CC Cluster, …) |
| `login` | | Nápověda k přihlášení, např. „your callsign“ |
| `skimmer` | | `true` pro zdroj ze skimmeru / RBN |
| `notes` | | Volný text |
| `rating` | | 0–5, vyšší je lepší (používá ho řazení podle hodnocení) |
| `verified` | | Datum, kdy byl záznam naposledy ověřen proti svému zdroji, `yyyy-MM-dd` |
| `source` | | URL veřejné stránky, která adresu dokládá |

Neznámé klíče se ignorují. Neplatný záznam (bez jména, host, který není jménem hostitele, špatný port) nebo opakovaný
`host:port` se přeskočí; zbytek souboru se přesto použije.

**Údržba seznamu.** Přidávejte jen clustery, jejichž adresu zveřejňuje veřejný zdroj (vlastní stránka nodu,
dokumentace softwaru clusteru, manuál logovacího programu), a dejte tuto stránku do `source` a dnešní datum do
`verified`. `Sources/MCLCore/Resources/clusters.json` (kopie dodávaná s programem) udržujte shodný s
`cluster-data/clusters.json`; kontroluje to test. První záznamy jsou servery RBN popsané výše (CW/RTTY a
FT8/FT4), manuál okna Telnet z N1MM Logger+ (K1TTT, W9PA) a wiki DXSpider (G1FEF).

## Komentář spotu, spotování QSO v S&P a speciální volačky

Další záložky **Možnosti…** v okně DX Cluster, podle záložek *Spot Comment*
a *Special Calls* okna Telnet z N1MM; každá změna platí a ukládá se hned.

**Komentář spotu.** „Comment For All Spots“ z N1MM: komentář posílaný s každým spotem, který MCL vytvoří — Spot It
(Alt+P), předvyplněný text Ctrl+P (lze ho dál upravit) a automatický spot ze S&P níže. Jeho makra berou
hodnoty spotovaného QSO (pole zadávacího okna, nebo zapsanou výměnu, když Spot It spotuje poslední QSO):

| Makro | Hodnota |
|---|---|
| `{GRIDSQUARE}` | pole lokátoru |
| `{MODE}` | mód QSO |
| `{QTH}` | pole státu, provincie, okresu, IOTA nebo textu |
| `{ZONE}` | pole zóny CQ nebo ITU |

Makro bez hodnoty se vynechá; komentář je vždy jeden řádek. U zapsaného QSO se uložená výměna přiřadí
k polím závodu podle pořadí (když byla některá pole prázdná, rozpozná se jen lokátor).

**{SPOTME}.** Makro funkčních kláves `{SPOTME}` (zprávy CW, SSB i digi) spotuje vaši vlastní stanici na frekvenci
zadávacího okna s komentářem spotu (jeho `{MODE}`; `CQ`, když je komentář prázdný) — totéž co textový příkaz
`SPOTME`. Mnoho závodů self-spoty zakazuje: zkontrolujte pravidla. Tlačítka bandmapy ho odmítnou.

**Spotovat všechna S&P spojení** — N1MM Config → Spot all S&P QSOs. **Výchozí vypnuto.** Když je zapnuté,
každé QSO zapsané v S&P se spotuje do veřejné sítě DX clusterů s komentářem spotu, pokud volačka už není
v bandmapě do 1 kHz od frekvence QSO. QSO z Run, dupy, QSO zadaná po závodě (papírový deník) a
simulátor pileupu se nikdy nespotují; dokud je hlavní spojení s clusterem dole, nic se neposílá (a nic se
nehlásí). Spoty jdou do veřejné sítě: ověřte, že to pravidla závodu povolují.

**Zvláštní volačky.** Seznam volaček — bonusové stanice, členové klubu, přátelé —, jejichž spoty dostanou srdíčko
**♥** za volačkou v bandmapě a v okně Dostupné multiplikátory (VoiceOver říká „speciální volačka“). Volačka se shoduje podle svého
základu (`W1AW` označí i `W1AW/M` a `DL/W1AW`). **Importovat…** přidá volačky ze souboru N1MM (první řádek
`Type=FAVORITES SubType=`, pak jedna volačka na řádek) nebo z libovolného prostého seznamu; **Exportovat…** zapíše soubor N1MM;
**Vymazat seznam** seznam vyprázdní. *Automaticky zahrnout bonusové stanice závodu* (výchozí zapnuto) přidá bonusové stanice
aktivního závodu (příkaz `BONUS`).

## Spoty v bandmapě: kliky, call-frame, značky

Podle okna [Bandmap](https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/) z N1MM Logger+.

**Kliky.** Klik na spot na něj naladí rádio (s automatickým splitem výše). Klik na
stupnici frekvencí nebo na prázdné místo naladí frekvenci pod kurzorem; klik na značku CQ
vrátí na CQ frekvenci. Se dvěma rádii nebo VFO (SO2R / SO2V) **Shift+klik** naladí místo toho **druhé** rádio / VFO
a vloží volačku spotu do jeho zadávacího okna; fokus zůstane (N1MM).

| Akce | Volačka |
|---|---|
| klik na spot | volačka se ukáže v **call-frame** nad polem volačky |
| dvojklik na spot | volačka jde rovnou do pole volačky (nahradí, co tam bylo) |
| **Mezerník** v prázdném poli volačky | převezme volačku z call-frame (s předpokládanou výměnou) a pokračuje dál |

Call-frame je z N1MM: vždy ukazuje spot nejbližší k frekvenci zadávacího okna v rámci
**tolerance ladění** módu, takže i naladění poblíž spotu (knoflík VFO, kolečko, Ctrl+↑/↓) ukáže jeho volačku.
Volačka napsaná do pole se nikdy nenahradí. **Nastavení → DX Cluster** má přepínač („Klik na spot
dá volačku do rámečku nad polem“; vypnuto = klik
vyplní pole volačky hned a naladění do 100 Hz od spotu vyplní prázdné pole jako dřív) a
**tolerance ladění** pro CW, SSB a digitální módy (0–20 000 Hz, výchozí 300 Hz, jako v N1MM).
Tolerance se kreslí jako světle modrý pruh na stupnici kolem naladěné frekvence.

**Vždy použít mód spotu (Always use packet spot mode).** „Ladění na spot nastaví i mód spotu“
v Nastavení → DX Cluster: naladění spotu nastaví jeho mód na rádiu i v zadávacím
okně — z komentáře spotu (`CW`, `FT8`, `SSB`…), digitálních frekvencí nebo bandplánu. Výchozí
vypnuto. Závod s jediným módem si svůj mód ponechá.

**Značky za volačkou.**

| Značka | Význam |
|---|---|
| `♥` | [zvláštní volačka](#komentář-spotu-spotování-qso-v-sp-a-speciální-volačky) |
| `#` | spot z CW Skimmeru / RBN |
| `!` | spot z vašeho vlastního skimmeru (spotter je vaše volačka s `-#`) |
| `¤` | východ nebo západ slunce v zemi stanice (do 30 minut) |
| `291°` | azimut od vašeho lokátoru |
| `×3` | potvrzeno třemi skimmery |
| `QSX 027` | stanice poslouchá split (z `UP 2`, `QSX 14027`…): poslední tři číslice kHz na KV |
| `NEW` | spotováno před méně než 3 minutami |

**Bublinová nápověda.** Najetí na spot ukáže přesnou frekvenci, kterou spotter poslal, spottera, před kolika
minutami byl spotován, komentář, frekvenci QSX, kolikrát byl spotován a kolika
skimmery, azimut, šedou linii a „Vlastní spot“. VoiceOver čte stejný text
jako nápovědu spotu.

**Najít volačku.** Pravý klik → „Najít volačku…“: napište volačku nebo její část;
naladí se nejbližší spot nad naladěnou frekvencí, který ji obsahuje (pokračuje dokola od nejnižšího), takže
další použití najde další výskyt. Alt+F8 vrátí tam, kde jste byli.

### Dotazy na cluster a historie spotů

Dotazy N1MM na jednu stanici (*Show Last 10 Spots*, *Show Station*, *Show QSL*, *Show
Sunrise/Sunset* z jeho menu View) jsou v menu spotu v bandmapě (**pravý klik na spot → Dotaz na DX cluster**) a v okně DX
Cluster v pravém kliku na řádek spotu. Jdou do hlavního spojení ve formátu pro software nodu;
odpověď se ukáže v okně DX Cluster.

Menu spotu v bandmapě má také **Natočit rotátor na CALL** (N1MM *Turn Rotor*): rotátor se natočí na stanici,
podle lokátoru spotu, je-li známý, jinak podle země volačky (viz [Antény → Rotátor](antennas.md#rotátor)).

| Položka | Příkaz (DXSpider / AR-Cluster, CC Cluster) |
|---|---|
| Posledních 10 spotů | `SH/DX 10 CALL` / `SH/DX/10 CALL` |
| Stanice | `SH/STATION CALL` |
| QSL informace | `SH/QSL CALL` |
| Východ a západ slunce | `SH/SUN CALL` |
| Callbook clusteru | `SH/QRZ CALL` |

**Historie spotů CALL** (N1MM *Show Telnet history*) vypíše každý spot stanice přijatý v této relaci ze
všech spojení — nejnovější napřed, s časem UTC, frekvencí, spotterem, komentářem a souběžným spojením, ze kterého
přišel —, i poté, co spot z bandmapy zmizel. **Historie spotů mé značky** (*My call spot history*) dělá totéž pro
vaši vlastní volačku (kdo vás spotoval, včetně RBN). Historie drží posledních 20 000 spotů a neukládá se.

**Naladit na tento spot** (N1MM *Jump to this spot*, pravý klik na řádek spotu v okně DX Cluster) naladí
aktivní rádio na spot jako klik na něj v bandmapě.

## Horní lišta bandmapy a uživatelská tlačítka

Podle horní části okna [Bandmap](https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/) z N1MM Logger+.
Pod naladěnou frekvencí má bandmapa řadu ovládacích prvků:

| Ovládání | Akce |
|---|---|
| **SH/DX** | pošle `SH/DX 30` (počet a formát z možností okna DX Cluster) do připojeného DX clusteru (odpověď se ukáže v okně DX Cluster) |
| **Wide / Narrow** | přepne filtr rádia mezi širokou a úzkou šířkou jeho módu; popisek ukazuje aktuální (s CAT; bez něj „Wide/Narrow“) |
| **CQ** | zpět na vaši poslední CQ frekvenci na pásmu (Run), jako klik na značku CQ |
| **RIT +120** | posun RIT; klik ho vynuluje |
| mód (**CW**, **USB**…) | mód rádia; klik nabídne CW, USB, LSB, RTTY, PSK, FT8, FT4, AM, FM (totéž jako napsat mód do pole volačky) |
| ikona posuvníků | otevře editor uživatelských tlačítek |

Šířky filtrů („Set Transceiver Filter Codes“ v N1MM) jsou v **Nastavení → DX Cluster**: CW, SSB
a digi, široká a úzká, v Hz (0 = výchozí šířka rádia). Hamlib nastavuje propustné pásmo spolu s
módem (`M CW 250`), takže kódy filtrů specifické pro rádio nejsou potřeba.

**Uživatelská tlačítka.** Až 36 programovatelných tlačítek v řadách po čtyřech („radio control buttons“ z N1MM). Pravý
klik na tlačítko → „Upravit tlačítka…“ nebo ikona posuvníků nebo pravý klik v bandmapě
→ „Uživatelská tlačítka…“. Každé tlačítko má popisek a příkaz; `|` odděluje stavy,
kterými tlačítko při každém kliku prochází (`Wide|Narrow` s `{CAT M CW 500}|{CAT M CW 250}`).
Příkaz může obsahovat:

| Část | Význam |
|---|---|
| `{CAT …}` | surový příkaz rigctld, např. `{CAT L AF 0.3}`, `{CAT M USB 2400}`, `{CAT Y 2 0}`; kontroluje se jako surový CAT pluginu (žádné PTT, žádné vysílání, žádná frekvence mimo pásma) |
| `{RUN}`, `{S&P}`, `{WIPE}`, `{CLEARRIT}`, `{CQFREQ}`, `{ALT-Q}`, `{NOSPLIT}`, `{CLRSTACK}` | řídicí makra funkčních kláves |
| jiný text | textové příkazy pole volačky oddělené `;` — `14025;CW`, `SPLIT`, `+2`, `RIT 100`, `/14030` (viz [textové příkazy](text-commands.md)); pole volačky si svou volačku ponechá |

Tlačítko nikdy nevysílá: makra zpráv (`{F1}`, `{TX}`, `{LOG}`…) se odmítnou se stavovou zprávou.
**⌘⌥⇧0 … ⌘⌥⇧9, ⌘⌥⇧A … ⌘⌥⇧Z** stisknou tlačítka 1–36, když je aktivní okno Bandmapa (N1MM
Ctrl+Alt+Shift+0…Z).

**Telnetové filtry.** Pravý klik v bandmapě → „Telnet pásma/módy…“ a „Telnet filtry…“ (N1MM
Telnet Bands/Modes, Telnet Filters) otevřou list [filtru spotů](#filtr-spotů-pásma-módy-původ-spotteru-pracovatelné);
obě části filtru jsou v jednom listu.

## Bandplán v bandmapě

Obdoba N1MM **Display of Band Plans in Background of Bandmap Frequency Scale**
([dokumentace](https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/#Display_and_Adjustment_of_Band_Plans_in_Background_of_Bandmap_Frequency_Scale))
a bandplánu DXLog v okně Radio. Bandmapa podbarvuje úseky
provozu pruhem vpravo od osy frekvencí, se svislým popiskem uvnitř:

| Úsek | Barva | Popisek |
|---|---|---|
| CW | indigová | `CW` |
| Digi | jantarová | `DIGI` |
| Fone | tyrkysová | `FONE` |

- Kreslí se oblast IARU, která platí pro **moji** stanici (podle
  kontinentu mé vlastní volačky) — je to vodítko pro mé vysílání, ne pro
  DX stanici.
- Úseky se berou z `contest-data/bandplan.yaml`, tedy ze stejného
  zdroje, ze kterého se odhaduje mód spotu a Mode Control „podle bandplánu“.
  Upravuje se v **„Nastavení → Bandplán“**; změna platí
  okamžitě.
- Při zvětšení se úseky ořezávají na viditelné okno. Popisek se kreslí, jen
  když se vejde do výšky úseku — v oddáleném pohledu tak úzké
  digi pásmo zůstane obarvené, ale bez textu.
- Překryv dvou úseků (soubor ho dovoluje; např. R2 má digi uvnitř CW na
  80 m) se kreslí stejně, jak ho vyhodnocuje odhad módu: vyhrává dřívější úsek,
  pozdější se o překryv zkrátí. Bandmapa tak nikdy neukazuje
  jinou kategorii, než jakou by program na dané frekvenci použil.
- Zapnout/vypnout lze dvěma způsoby: **pravý klik v bandmapě → „Skrýt /
  Zobrazit bandplán“** nebo **„Nastavení → Bandplán →
  Podbarvit úseky v bandmapě“**. Volba se ukládá do konfigurace.

### Úprava bandplánu z bandmapy

Stejně jako v N1MM lze plán měnit tam, kde ho vidíte: **pravý klik v bandmapě → „Bandplán zde (… kHz)“**
na frekvenci pod myší, pak jedna z položek

| Položka | Účinek |
|---|---|
| Začátek / Konec CW zde | spodní / horní okraj CW úseku pásma se přesune na frekvenci |
| Začátek / Konec Digi zde | totéž pro digi úsek |
| Začátek / Konec fonie zde | totéž pro fonický úsek |
| Odebrat úsek zde | úsek pod frekvencí se odstraní |

- Mění se jen moje oblast (ta, kterou bandmapa kreslí). Frekvence se zaokrouhlí na 0,1 kHz.
- Sousední úsek, který by nový okraj překryl, se zkrátí, aby se ho dotýkal, nebo odstraní, když je zakrytý
  úplně, takže se plán nikdy nepřekrývá (pravidlo Nastavení → Bandplán).
- Změna se zapíše do `bandplan.yaml` v datové složce závodů a hned se uplatní, přesně jako Uložit v
  Nastavení → Bandplán. Bez souboru je výchozím bodem vestavěný plán; oblast bez vlastních řádků
  začíná jako kopie R1 (co pro ni bandmapa ukazovala předtím).
- Stavový řádek řekne, proč se nic nezměnilo: frekvence mimo pásma, žádný takový úsek na pásmu nebo okraj,
  který by úsek nechal prázdný.

### Čáry licenčních tříd USA

**Pravý klik → „Zobrazit / Skrýt čáry licenčních tříd USA“** nebo **Nastavení →
Bandplán** nakreslí přes stupnici krátké červené čáry na hranicích podpásem US Extra / Advanced / General podle
47 CFR §97.301: CW 3525, 7025, 14025, 21025 kHz; fone 3600, 3700, 3800, 7125, 7175, 14150, 14175, 14225, 21200,
21225, 21275 kHz. Je to určené pro operátory z USA a ve výchozím stavu vypnuté. N1MM+ kreslí podobnou sadu čar ze staršího
seznamu hranic; MCL používá aktuální předpis.

## Rádio, split a navigace v bandmapě

Obdoba zobrazení rádia v okně Bandmap z N1MM Logger+
([dokumentace](https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/)).

- **Záhlaví:** rádio — **VFO A** / **VFO B**, nebo **Rig 1** / **Rig 2** v SO2R — s modelem rigu z
  Nastavení, dokud je připojený CAT, přijímací frekvence a, dokud rig hlásí split, vysílací
  frekvence **TX 14030.00 kHz** červeně.
- **Šipky:** modrá šipka je přijímací frekvence; dokud je rig ve splitu, označuje červená šipka vysílací
  frekvenci. Najetí na šipku ukáže její přesnou frekvenci. **Klik na červenou šipku split vypne.**
- **Šířka filtru:** modrý pruh vedle pruhu bandplánu ukazuje propustné pásmo rigu (nad frekvencí v USB,
  pod ní v LSB, kolem ní v CW, RTTY, AM a FM), jak ho rig hlásí přes CAT.
- **Zvětšení:** tlačítka + a −, Cmd+= / Cmd+- nebo + / − na numerické klávesnici, když je aktivní okno Bandmapa,
  Ctrl+kolečko, tažení přes frekvence a **pravý klik → Přiblížit / Oddálit**. Zvětšení bandmapy druhého
  rádia přes Shift+numerickou klávesnici z N1MM nemá obdobu: je jedna bandmapa, aktivního rigu.
- **Pravý klik → Vypnout kolečko myši**: kolečko neladí ani nezvětšuje (zámek proti
  nechtěnému přeladění). Ukládá se do konfigurace.
- **Pravý klik → Na spodní / horní okraj úseku pásma**: QSY na spodní nebo
  horní okraj úseku bandplánu (CW, digi, fone), ve kterém je rádio naladěné; mimo všechny úseky na okraj
  pásma.
- **Pravý klik → Nejnižší kmitočet dole**: otočí bandmapu vzhůru nohama, takže
  frekvence rostou směrem nahoru. Ukládá se do konfigurace.

## Odebírání spotů

Kontextové menu bandmapy má položky N1MM pro odebírání (spot pod myší má vlastní *Odebrat spot*):

| Položka | N1MM | Odebere |
|---|---|---|
| Smazat spoty, jen toto pásmo, ponechat vlastní | Remove Spots, This Band Only, Leave Self Spots | spoty pásma bandmapy kromě mých vlastních |
| Smazat spoty, jen toto pásmo | Remove Spots, This Band Only | všechny spoty pásma bandmapy |
| Smazat spoty, všechna pásma, ponechat vlastní | Remove Spots, ALL Bands, Leave Self Spots | všechny spoty kromě mých vlastních |
| Smazat všechny spoty | Remove Spots, ALL BANDS | všechny spoty |

Mé vlastní spoty jsou self spoty: *Mark*, *Store* a volačky uložené při odladění (kreslené tučně). Odebrání
vyčistí paměť spotů, takže spoty zmizí i z okna Dostupné multiplikátory a ze skoků po spotech; nový spot
téže stanice z clusteru se ukáže znovu.

## Filtr spotů (pásma, módy, původ spotteru, pracovatelné)

Podle okna Telnet z N1MM+ (záložky *Bands/Modes* a *Filters*). Otevírá se tlačítkem **Filtr spotů** v
okně DX Cluster (tečka za popiskem znamená, že je filtr aktivní) nebo v *Nastavení → DX Cluster*. Změny v
okně platí a ukládají se hned; v Nastavení platí po Uložit. Stav je v sekci `dxCluster` souboru
`config.json` (klíče `spotFilter*`; konfigurace bez nich znamená „vše zapnuto“).

**Pásma.** Jedno zaškrtávátko pro každé pásmo, které MCL zná, ve čtyřech skupinách: KV (160 m až 10 m, včetně 60 m), VKV (6 m, 2 m, 1,25 m = 222 MHz),
UKV (70 cm, 33 cm = 902 MHz, 23 cm) a Mw (13 cm, 9 cm, 6 cm, 3 cm a milimetrová pásma 24, 47, 76, 122, 134 a 241 GHz). Tlačítka skupin přepínají celou skupinu: když je vše zapnuto, vypnou ji,
jinak vše zapnou.

**Módy.** CW, Fonie a Digi (RTTY, FT8, PSK a podobné). Mód spotu je ten, který už používá bandmapa:
mód uvedený v komentáři, jinak kalibrační digi frekvence, jinak bandplán. Spot, jehož mód nelze
určit, zůstane viditelný, pokud nejsou vypnuté všechny tři módy. *Všechny módy* zapne všechny módy.

**Závod.** Se zaškrtnutým *Jen pásma a módy aktivního závodu* a aktivním závodem musí být spot také na pásmu
definice závodu (když pásma uvádí) a v módu, který definice povoluje. Bez závodu nedělá nic.

**Původ spotteru** (N1MM „Filter by Prefix“). *Jen spoty od spotterů z* EU, NA, SA, AS, AF, OC a *Vlastní země*: projdou jen
spoty, jejichž spotter sídlí tam (DXCC spottera z jeho volačky, bez přípon `-#` / `-2`; u skimmeru se počítá jeho vlastní
poloha). Nic nezaškrtnuto znamená žádný filtr; spotter, kterého nelze určit, je při zapnutém filtru skrytý.

**Prefixy spotterů a call oblasti** (N1MM „Filter by Prefix“). *Prefixy spotterů* přijímá prefixy oddělené mezerami nebo
čárkami (`OK OM DL`): projde spotter, jehož volačka jedním z nich začíná. *Call oblasti vlastní země* 0–9: projde spotter z vaší vlastní
DXCC, jehož call oblast (číslice jednomístné portable přípony `/4`, jinak číslice prefixu) je zaškrtnutá. Volby
původu se kombinují: projde spotter, který odpovídá **kterékoli** z voleb kontinenty, vlastní země, prefixy nebo call oblasti.

**Jen spoty stanic z call history** (N1MM „Show only spots in call history“): jen volačky, které načtená call history zná.
**Jen spoty stanic, které už jsou v deníku**: jen volačky, které už jsou v deníku (na kterémkoli pásmu).

**Skrýt spoty majáků NCDXF/IARU**: skryje spoty 18 stanic International Beacon Project (4U1UN, VE8AT, W6WX,
KH6RS, ZL6B, VK6RBP, JA2IGY, RR9O, VR2B, 4S7B, ZS6DN, 5Z4B, 4X6TU, OH2B, CS3B, LU4AA, OA4B, YV5B, s `/B` i bez).
Majáky, které si načtete sami přes `BEACONS` (Nástroje → Načíst soubor majáků…), jsou vaše vlastní spoty a zůstanou.

**Maják, který právě vysílá**: při naladění na frekvenci majáků (14100, 18110, 21150, 24930 nebo 28200 kHz, ±1 kHz) ukazuje
informační proužek zadávacího okna, který maják NCDXF/IARU právě vysílá (`NCDXF 4U1UN (United Nations NY)`),
podle zveřejněného rozpisu — 10 sekund na maják a pásmo, 3minutový cyklus začínající v 00:00 UTC —, takže
hodiny počítače musí jít přesně (N1MM to ukazuje ve stavovém řádku stejně).

**Nástroje → Naladit maják NCDXF pro pásmo** (N1MM „Tune to beacon for
this band“): na 20, 17, 15, 12 nebo 10 m přejde aktivní zadávací okno a rig na frekvenci majáků pásma v CW
a stavový řádek uvede maják, který právě vysílá, s azimutem od vašeho lokátoru
(`Maják NCDXF: vysílá OH2B (Finland), azimut 27°`). Na ostatních pásmech jen řekne, kde majáky jsou.

**Odstranit chybné (busted) spoty** (N1MM „Remove Busted Spots“): mezi živými spoty jsou dvě volačky v toleranci
ladění módu (Nastavení → DX Cluster), které se liší o jeden znak (změněný, přidaný nebo chybějící znak),
správná volačka a její chybná kopie — typicky špatné dekódování skimmeru. Volačka hlášená méněkrát (spoty,
skimmery) se skryje; při stejném počtu hlášení ta, která přišla později. *I chyby ve dvou znacích* („Two Character Errors“)
bere jako chybné i rozdíly ve dvou znacích. Volačky kratší než čtyři znaky a vaše vlastní spoty se nikdy
neporovnávají. Chybný spot se vrátí, jakmile je volba vypnutá nebo jeho volačka získá víc hlášení.

**Preferovaní spotteři** (preferred spotters z N1MM, typicky váš vlastní skimmer): až tři volačky; `OK1ABC` odpovídá
i `OK1ABC-2`, `OK1ABC-#` a `OK1ABC/3`. Jejich spoty se nefiltrují, ale zvýrazňují: tučně na podbarveném
pozadí v okně DX Cluster, `★` za volačkou v bandmapě a před spotterem v okně Dostupné multiplikátory.
*Obnovit výchozí* je ponechá.

**Zobrazovat nepracovatelné spoty** (N1MM „Show non-workable spots“, výchozí zapnuto). Když je vypnuté a závod je aktivní,
skryjí se spoty na pásmu nebo v módu, které závod nepovoluje. Definice závodů nevyjadřují žádné jiné
pravidlo „nelze pracovat“, takže je to stejný test jako u volby *Závod*; dupy nepracovatelné nejsou a zůstanou
(obarvené jako dupy).

**Obnovit výchozí** vše vrátí: všechna pásma a módy zapnuté, žádný filtr původu, Závod vypnuto, nepracovatelné zobrazené,
volby call history / pracováno / majáky / chybné spoty vypnuté (preferovaní spotteři zůstanou).

**Blacklisty.** Okno Blacklist (Okno → Blacklist) má ovládání z N1MM pro zobrazený seznam (volačky nebo spotteři):
*Blacklist zapnutý* vypne oba seznamy, aniž by se ztratily (už zahozené spoty se nevrátí, nové se
ponechají), *Importovat…* přidá volačky z textového souboru (jedna na řádek nebo oddělené čárkami či mezerami; řádky `#` jsou
komentáře), *Exportovat…* zapíše seznam po jedné volačce na řádek, *Vymazat seznam* ho po potvrzení vyprázdní.

### Tok spotů

```
cluster node(y) / RBN / sdílené řídicí stanicí
        |  surový spot (všechna spojení; blacklisty a minimum skimmerů platí tady, v paměti)
        v
  paměť spotů  --->  události spot-received pro pluginy, sdílení po síti   (nikdy nefiltrováno)
        |
        |  filtr spotů (pásma, módy, závod, původ, pracovatelné) se uplatní při čtení spotů
        +--> okno DX Cluster: řádky `DX de` / `SH/DX` zašedlé  (odpovědi na příkazy a jiný text vždy viditelné)
        +--> bandmapa
        +--> Dostupné multiplikátory (navíc vlastní filtr pásem / módů)
        +--> skoky po spotech (Ctrl/Alt + Nahoru/Dolů)
```

Paměť spotů se filtrem nikdy nemění, takže zrušení skrytí pásma vrátí jeho spoty okamžitě. Vlastní spoty (Mark,
Store, self-spoty) se nikdy neskrývají. Každá stanice uplatňuje vlastní filtr na spoty, které přijímá; spot sdílený
řídicí stanicí přijde nefiltrovaný. Mapa světa, mřížky násobičů a předběžné dohledávání v callbooku čtou celou
paměť spotů. Doba platnosti spotu je stávající nastavení *Buffer spotů (min)* a QSY, které se vzdálí od spotované
frekvence, používá stávající práh pro self-spot; ani jedno nemá nová nastavení. Filtr rádia s fokusem (SO2R / SO2V)
[okna Dostupné multiplikátory](available-window.md) není součástí tohoto filtru.
