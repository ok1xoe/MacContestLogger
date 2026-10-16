# Kontrola volacích značek

![Dupesheet — volací značky ve sloupcích podle číslice](../img/dupesheet.png)

Pomůcky pod polem volací značky v zadávacím okně.

## Už pracováno, po pásmech

Obdoba N1MM **Check** (barvy pásem u volačky) a DXLog **Check
callsign**. Jakmile má volací značka v poli aspoň 3 znaky a
stanice už je v deníku, objeví se řádek:

```
Pracováno 3×, naposledy 1412Z:  160  80  [40 CW]  20 CW/SSB  15  10
```

- Pásma jsou pásma závodu (mimo závod 160–10 m); pásmo, které v
  seznamu není a na kterém existuje QSO (např. 6 m), se připojí na konec.
- **Zvýrazněné** pásmo = stanice tam už je, i s módy. **Červené** = je
  i na aktuálním pásmu (dupe podle pásma; dupe podle pravidel závodu ukazuje
  štítek DUPE).
- Ztlumená pásma = zatím nepracováno — kam stanici přesunout.
- Smazaná QSO se nepočítají, X-QSO ano.

## Visible Dupesheet

Obdoba N1MM **Visible Dupesheet**
([dokumentace](https://n1mmwp.hamdocs.com/manual-windows/visible-dupesheet-window/)).
Otevírá se přes **„Okno → Dupesheet“**.

- Pracované volací značky na **aktuálním pásmu** (z rigu, bez CAT z
  posledního QSO) — podle pravidel závodu pro dupe také pro aktuální mód
  (`PER_BAND_MODE`), jen pro mód (`PER_MODE`) nebo pro celý závod (`ONCE`). Mimo
  závod podle pásma.
- Sloupce **0–9** podle číslice oblasti (OK1... → 1, `DL/OK1XOE` → 1),
  volací značky bez číslice ve sloupci **#**; počty v záhlaví.
- Každý sloupec je **řazený podle sufixu** jako v N1MM — písmen za poslední číslicí
  volačky (`OK1XOE` → `XOE`, `DL/OK1XOE/P` → `XOE`), shodné sufixy podle
  celé volačky. Přepínač **„Nastavení → Závod → Dupesheet: řadit volačky podle
  sufixu“** (výchozí zapnuto) ho vypne; sloupce se pak řadí podle celé
  volačky jako dřív.
- **Jeden list pro každé VFO / rádio** (N1MM: „Each VFO/Radio has its own Visible
  Dupesheet“). Okno **Dupesheet VFO A** sleduje pásmo a mód rigu a
  právě psanou volačku. **„Okno → Dupesheet VFO B“**
  otevře druhý list, který sleduje pásmo (z pole frekvence), mód
  a volačku **zadávacího okna VFO B / rigu 2** (SO2V/SO2R); bez frekvence
  v něm ukazuje pásmo posledního QSO.
- Volačky, které obsahují text napsaný v poli volačky (od 2 znaků), jsou
  **zvýrazněné** — dupe je vidět ještě před dopsáním.
- Dupesheet nerozlišuje etapy TOUR (ukazuje celý závod na
  pásmu).

## Stažení master.scp

Obdoba N1MM **Tools → Download latest Check Partial file** a DXLog
**Update Super Check Partial database**. Menu **„Nástroje → Stáhnout master.scp“**:

- stáhne aktuální `MASTER.SCP` ze [supercheckpartial.com](https://www.supercheckpartial.com/),
- uloží ho do souboru nastaveného v „Nastavení → Závod → Soubor master.scp“; není-li žádný nastavený, do datové složky aplikace
  a cestu rovnou nastaví,
- a hned ho načte — návrhy fungují s novými daty bez restartu.

Stahuje se do dočasného souboru a původní se přepíše jen tehdy, když
obsah vypadá jako master.scp (aspoň 1000 volaček, ne chybová HTML stránka).
Při chybě zůstane starý soubor a stavový řádek řekne proč.

## Check partial: deník, spoty a master.scp

Obdoba N1MM **Check window** (včetně jeho [telnetových
funkcí](https://n1mmwp.hamdocs.com/manual-windows/check-window/#Special_Telnet_Features))
a DXLog **Check partials**. Návrhy pod polem volačky (od 2
znaků) pocházejí ze tří zdrojů:

| Zdroj | Vzhled |
|---|---|
| **vlastní deník** | šedě (už pracováno), červeně, je-li to dupe na pásmu |
| **spoty z DX clusteru** | podtržené, barvou zvýraznění — stanice je teď na pásmu |
| **master.scp** | normálně |

Pořadí: přesná shoda → začíná zadaným textem → obsahuje ho; při stejné
shodě má přednost deník, pak spoty, pak master.scp. Díky deníku a
spotům fungují návrhy i bez souboru master.scp a najdou i volačky,
které v něm nejsou (nové, speciální). Výběr šipkami / Enter / Alt+Y
jako dřív.

## N+1

Obdoba DXLog **Check N+1** a okna N1MM **N+1**. Od 3 znaků
volačky se pod návrhy objeví řádek `N+1:` s volačkami, které se od
zadané liší **přesně jedním znakem** — záměnou
(`OK1XOE` ↔ `OK1XDE`), vložením (`OK1XOEE`) nebo vynecháním (`OK1XO`). Zachytí
chyby příjmu, které partial check nenajde. Zdroje: deník (šedě),
spoty a master.scp. Klik převezme volačku do pole.

## Okno Check

Obdoba N1MM **Check window**
([dokumentace](https://n1mmwp.hamdocs.com/manual-windows/check-window/)). Otevírá se přes **„Okno → Check“**.
Sleduje volačku psanou v aktivním zadávacím okně (i v okně VFO B) a ukazuje vedle sebe panely:

| Panel | Zdroj |
|---|---|
| **Deník** | volačky otevřeného deníku |
| **master.scp** | načtený `master.scp` |
| **Telnet** | stanice spotované DX clusterem — volačka se ukáže, až byla spotována **3krát** (dokud její spot žije; nastavitelné) |
| **Call history** | volačky načtené call history |
| **Výměna** | v závodě: hodnoty seznamu násobičů za právě psaným polem výměny (okresy, sekce…) |
| **Zpětné hledání** | volačky, jejichž výměna odpovídá tomu, co jste napsali (viz níže) |

Záhlaví každého panelu ukazuje počet shod a velikost jeho zdroje.

- Od 2 znaků se volačka ukáže, když **obsahuje** napsaný text; od 3 znaků i tehdy, když se liší o
  **jeden znak** (záměna, znak navíc nebo chybějící znak — pravděpodobná chyba příjmu).
- Barvy po znacích: napsané znaky normálně, **zelené** znaky volačku doplňují, **červená** označuje, kde se
  volačka od napsaného liší. **Přesná shoda** je tučná kurzíva.
- Pořadí: přesná shoda, začíná textem, obsahuje ho, liší se o jeden znak; pak kratší volačky napřed.
- Klik vloží volačku do pole volačky (hodnotu výměny do jejího pole).

### Kontextové menu (pravý klik)

| Položka | N1MM | Význam |
|---|---|---|
| Skrýt tento panel | Hide this pane | skryje panel |
| Proporcionální šířka tohoto panelu | Proportional width this pane | 1×–4× normální šířky |
| Zobrazené panely | (zaškrtávátka panelů) | které panely se zobrazují |
| Alt+Y: pořadí panelů | Yank: configuration | pořadí, v jakém Alt+Y prochází panely; klik posune panel o místo nahoru |
| Alt+Y: i duplicitní volačky | Yank: allow dupes | Alt+Y bere i volačky, které jsou na pásmu dupe |
| Řazení: upřednostnit rozdíly na konci volačky | Sorting: Favor end-character differences | mezi stejnými shodami jdou napřed volačky, které se liší jen ke konci (`/P`, poslední písmeno) |
| Telnet: volačka od počtu spotů | (3 spoty) | kolik spotů volačka potřebuje pro panel Telnet |
| Zpětné hledání v call history a deníku | Reverse Call History Lookup | zpětné hledání zapnuto / vypnuto |
| Práh zpětného hledání (znaků) | Set Reverse Lookup Threshold | počet znaků hodnoty výměny, od kterého se hledá (výchozí 2) |
| Zpětné hledání: shoda od prvního znaku | (shoda od začátku) | vypnuto = napsaný text může být kdekoli v hodnotě |

Nastavení se ukládají v konfiguraci (klíče `check*`).

### Alt+Y

**Alt+Y** v poli volačky vezme první volačku panelů v pořadí pro Alt+Y (výchozí Deník, master.scp, Telnet, Call
history, Zpětné hledání) a přeskakuje dupe, pokud nejsou povolené. Další stisk, dokud pole ještě drží
tuto volačku, vezme **další**, stále dokola; napsání čehokoli jiného začne znovu. Funguje i se zavřeným oknem
Check. V poli výměny vezme Alt+Y první hodnotu panelu výměny. Bez jakékoli shody v Check vezme
první návrh check partial jako dřív.

### Zpětné hledání

N1MM **Reverse Call History Lookup**: napište, co jste z výměny zachytili (například okres), a panel vypíše
volačky, jejichž **QSO v deníku nebo záznam call history** to mají — shodovat se musí každá napsaná hodnota, od počtu
znaků prahu, od prvního znaku hodnoty (nebo kdekoli, viz menu). Částečně napsaná volačka zúží
seznam na volačky, které ji obsahují. Nejvýš 100 volaček; report a pořadové číslo se neprohledávají.

## ✓ / ? v poli volačky

Obdoba zaškrtnutí v N1MM a **View → Show ? on Unmatched Calls**. Od 3 znaků ukazuje pole volačky na
svém pravém konci:

- **✓**, když některý zdroj Check (deník, master.scp, spot, call history) má přesně tuto volačku, obarvené podle stavu
  násobiče: zelená = víc než jeden nový násobič, červená = jeden nový násobič, modrá = nové QSO, šedá = dupe;
- **?**, když ji nemá žádný zdroj. **„Zobrazení → Zobrazovat ? u neznámých volaček“**
  otazník vypne.

Značka se zobrazuje, dokud je vidět nějaký Check: okno Check nebo řádek `SCP:` zadávacího okna (Nastavení →
Závod).
