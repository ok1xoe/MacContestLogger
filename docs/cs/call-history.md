# Call history

Obdoba N1MM+ **Call History**
([Call History Lookup](https://n1mmwp.hamdocs.com/setup/call-history/#Call_History_Lookup))
a DXLog **Prefill database**.

## Nastavení

**„Nastavení → Závod → Call history“**: soubor
ve formátu N1MM (textové CSV). Pod polem se ukazuje počet načtených volaček.
Soubory pro jednotlivé závody lze stáhnout například z
[n1mm.hamdocs.com](https://n1mmwp.hamdocs.com/setup/call-history/) nebo od
pořadatelů.

```
# komentář
!!Order!!,Call,Name,State,CQZone,Exch1
W1AW,Hiram,CT,5,
OK1XOE,Tomas,,15,JN79
```

Řádek `!!Order!!` určuje sloupce; bez něj platí pořadí N1MM
`Call,Name,Loc1,Loc2,Sect,State,CK,BirthDate,Exch1,Misc,UserText`.
Soubor může jako oddělovač používat i `;`: když je první oddělovač za `!!Order!!`
středník (`!!Order!!;Call;Name;State`), datové řádky se dělí podle `;`.

Ve stejné skupině je:

- **Další soubory call history (sloučené)** —
  **Přidat soubory…** vybere jeden nebo více souborů, **Odebrat** jeden
  ze seznamu odstraní (viz [Více souborů v jedné tabulce](#více-souborů-v-jedné-tabulce)),
- vlastní soubor aktivního závodu s **Přiřadit závodu…** / **Zrušit přiřazení**,
  což se na otevřený závod uplatní hned
  (viz [Vlastní soubor závodu](#vlastní-soubor-závodu)),
- **Načteno celkem: N volaček** — volačky všech načtených souborů dohromady,
- **Zapnout dohledávání v call history**, tentýž přepínač jako položka menu níže,
- **Zobrazovat informace uživatele (UserText)** — řádky call history
  a UserText v zadávacím okně.

## Zapnutí dohledávání

Obdoba N1MM **Config → Enable Call History Lookup**: menu **„Nastavení →
Zapnout dohledávání v call history“** je zaškrtávací
položka (výchozí zapnuto; klíč konfigurace `callHistoryLookupEnabled`). Když je vypnutá, z call history
se nic nepředvyplňuje (předvyplnění z callbooku zůstává); zpětné hledání a řádek
UserText fungují dál, jako v N1MM.

### Přiřazení souboru k závodům (řádky `#CONTEST`)

Stejně jako v N1MM může komentářový řádek uvádět závod, pro který je soubor určen — `#` na začátku
řádku, jeden závod na řádek, na velikosti písmen nezáleží:

```
#CQWWCW
# cq-ww-ssb
# QSO Party PA
```

Při otevření závodu se jména porovnají se závody, které logger zná (definice
v datové složce závodů), podle jejich id a jména, bez ohledu na velikost písmen, mezery,
pomlčky a jinou interpunkci (`#CQWWCW`, `# CQ WW CW` i `#cq-ww-cw` označují
`cq-ww-cw`):

- uvádí-li soubor známé závody a **jeden z nich je otevřený závod**, dohledávání se
  **zapne**,
- uvádí-li známé závody, ale **ne tento**, dohledávání se **vypne**,
- neuvádí-li žádný komentář známý závod (obyčejné komentáře nebo jen krátká jména N1MM, pro
  která logger nemá definici), přepínač zůstane, jak je.

Děje se to jednou při otevření závodu (a při změně jeho souboru); pozdější přepnutí položky
menu platí. Komentáře a direktivy souboru se zachovají, když ho logger
ukládá (aktualizace z deníku, vymazání).

## Vlastní soubor závodu

Obdoba N1MM **Contest Setup → Associated Files**. Okno **Nový závod**
má pole **Call history závodu** s tlačítkem **Vybrat soubor…**;
prázdné znamená hlavní soubor z Nastavení. Dokud je tento závod otevřený, používá se jeho
soubor místo hlavního (další soubory se dál přimíchávají) a
při otevření jiného závodu se logger přepne zpět. Soubor se pamatuje s nastavením
závodu a nabídne se znovu, až se bude stejný závod zakládat příště. Pro závod,
který už je otevřený, použijte **Přiřadit závodu…** v Nastavení → Závod → Call history.

## Více souborů v jedné tabulce

Obdoba N1MM **File → Import → Import Call History** s více vybranými soubory:
menu **„Soubor → Import → Importovat call history…“**
umožní vybrat jeden nebo více souborů (Cmd+klik); přidají se k dalším souborům
v Nastavení → Závod → Call history a hned se načtou. Další soubory se slučují za
hlavním do jedné tabulky, v jejich pořadí:

- volačka, která v tabulce ještě není, se přidá,
- u volačky, která tam už je, přepíší **neprázdná** pole pozdějšího souboru ta
  dřívější; prázdná pole je nechají, jak jsou,
- **UserText** se připojí (`!!AppendUserText!!`, výchozí), pokud pozdější soubor neuvádí
  `!!NoAppendUserText!!` (pak ho nahradí),
- odlišný **Loc1** přesune předchozí do **Loc2** (alternativní lokátor), pokud pozdější
  soubor neuvádí `!!NoLoc2AltGrid!!`.

Samotné soubory se nemění: **Aktualizace z deníku** a **Vymazání call history** zapisují
jen hlavní soubor (nebo vlastní soubor závodu). Export zapíše sloučenou tabulku.

## Direktivy importu

Řádky direktiv N1MM začínají `!!` a mohou být kdekoli v souboru; víc jich může sdílet
řádek, oddělené `,` nebo `;` (`!!MapStateToSect!!;!!FourCharGridSq!!`):

| Direktiva | Účinek |
|---|---|
| `!!MapStateToSect!!` | prázdné `Sect` převezme hodnotu `State` |
| `!!FourCharGridSq!!` | 6znakové lokátory (`Loc1`, `Loc2`) se zkrátí na 4 znaky |
| `!!AppendUserText!!` | opakovaná volačka připojí svůj UserText (výchozí) |
| `!!NoAppendUserText!!` | opakovaná volačka nahradí svůj UserText |
| `!!Validate50State!!` | `State`, který není jedním z 50 států USA, se zahodí (DC není stát, takže se zahodí také) |
| `!!NoLoc2AltGrid!!` | odlišný Loc1 přepíše předchozí, místo aby ho přesunul do Loc2 |
| `!!MapOnSection!!` | sekce Ontaria GTE (GTA), ONN, ONE a ONS se změní na ON |
| `!!ValidateArrlSection!!` | `Sect`, který není sekcí ARRL/RAC, se zahodí (PR a VI sekce jsou, ON není) |

Soubor **s** direktivami se řídí pravidly importu N1MM i pro volačku opakovanou uvnitř
souboru (pole se slučují jako výše). Soubor **bez** jakékoli direktivy se čte přesně jako dřív
(pozdější řádek téže volačky nahradí celý záznam), takže existující soubory se chovají stejně.

## Předvyplnění výměny

Po napsání volačky (od 3 znaků, po krátké pauze) se **prázdná** pole
přijaté výměny vyplní z call history:

1. sloupec se stejným jménem jako pole (`name`, `state`, `zone`...),
2. jinak podle typu pole: CQ zóna ← `CQZone`, ITU ← `ITUZone`, stát/provincie ←
   `State`/`Sect`, lokátor ← `Loc1`, okres ← `District`/`Loc2`, text ← `Name`,
3. jinak `Exch1` (když má závod jediné „volné“ pole).

Pole lokátoru vezme nejdřív lokátor z dřívějšího QSO se stejnou stanicí v otevřeném deníku (N1MM; počítá se stejná
základní volačka, takže `OK1ABC/P` dostane lokátor zapsaný pro `OK1ABC`), potom ten z call history.

Report a pořadové číslo se nevyplňují. Hodnoty, které jste ručně přepsali, se
nemění; když volačku změníte, předvyplněné hodnoty předchozí
volačky zmizí.

## Aktualizace z deníku

Obdoba N1MM **Update Call History from log** a DXLog **Update prefill
database from log**. Menu **„Nástroje → Aktualizovat call history z deníku“**
(jen v otevřeném závodě):

- z každého QSO vezme pole přijaté výměny (bez reportu a pořadového
  čísla); je-li stanice v deníku vícekrát, platí **nejnovější** QSO,
- hodnotu zapíše do sloupce pojmenovaného jako pole, jinak do
  typického sloupce podle typu (CQ zóna → `CQZone`...); chybějící sloupce se přidají do
  `!!Order!!`,
- sloučí se s existující call history (přidá nové volačky, přepíše hodnoty,
  ostatní sloupce nechá) a atomicky ji uloží zpět do souboru,
- lokátor se řídí pravidlem N1MM pro **Loc1/Loc2**: lokátor odlišný od uloženého Loc1
  se stane Loc1 a předchozí Loc1 se přesune do Loc2 (starší Loc2 se zahodí); 4znakový
  lokátor se přepíše 6znakovým lokátorem téhož čtverce (bez přesunu) a 4znakový
  lokátor nikdy nenahradí 6znakový ze svého čtverce. `!!NoLoc2AltGrid!!` v souboru
  přesun vypne.

Zapisuje **hlavní** soubor — vlastní soubor otevřeného závodu, pokud ho má —, nikdy
další sloučené soubory. Bez nastaveného souboru se vytvoří `CALLHISTORY.txt` v
datové složce aplikace a cesta se uloží do nastavení. X-QSO a smazaná QSO
se nepoužijí.

## Vymazání call history

**„Nástroje → Vymazat call history…“** po potvrzení vyprázdní načtenou call
history: soubor si ponechá své sloupce (záhlaví `!!Order!!`) a žádnou volačku a historie v loggeru je hned
prázdná. Soubor se **nikdy neztratí**: jeho předchozí obsah se nejdřív zkopíruje vedle něj jako `<soubor>.bak-<čas UTC>`
(například `CALLHISTORY.txt.bak-20261128-143000`). N1MM **Clear Call History then Update** jsou tyto dvě položky menu
za sebou: vymazat, pak **Aktualizovat call history z deníku**. Chcete-li si ponechat kopii jinde,
použijte nejdřív **Soubor → Export → Call history (N1MM)…** (viz [Import a export](import-export.md)).

## Řádky call history a UserText

Obdoba N1MM **Show User Information**. Se zapnutým **Zobrazovat informace uživatele
(UserText)** (Nastavení → Závod → Call history; výchozí zapnuto, klíč konfigurace
`callHistoryShowUserInfo`) ukazuje proužek pod frekvencí zadávacího okna (i okna
VFO B) vedle řádku callbooku pro napsanou volačku:

- `Call history: Name: Hiram, State: CT, Loc1: FN31, CQZone: 5` — sloupce záznamu kromě
  volačky a UserText, dokud je dohledávání zapnuté,
- **UserText** záznamu modře samostatně — i když je dohledávání vypnuté, jako v N1MM.

U volačky bez záznamu se nezobrazí nic.

## Zpětné hledání

Obdoba N1MM **Reverse Call History Lookup**
([dokumentace](https://n1mmwp.hamdocs.com/setup/call-history/#Reverse_Call_History_Lookup)).
Když vám uteče volačka, ale zachytíte výměnu (typicky jméno a stát v
QSO party):

1. nechte pole volačky **prázdné** a do polí výměny vyplňte, co víte,
2. pod polem volačky se objeví `Call history: W1AW K1ABC ...` — volačky,
   jejichž záznam call history odpovídá **všem** vyplněným polím (bez ohledu na velikost písmen;
   report a pořadové číslo se nepočítají),
3. klik vloží volačku do pole.

Pole se porovnávají se stejnými sloupci, ze kterých by se předvyplňovala.

**Okno Check** (Okno → Check) má úplnější zpětné hledání: prohledává i QSO deníku, přijme
částečnou hodnotu (od prahu počtu znaků, se shodou od začátku hodnoty nebo kdekoli) a vypíše až 100
volaček; viz [Kontrola volacích značek](call-check.md#zpětné-hledání).

## Callbook (HamQTH / QRZ.com)

Obdoba N1MM **Callbook lookup**. S účtem HamQTH nebo QRZ.com („Nastavení
→ Online callbooks“, zapnuto) se po krátké pauze v
psaní volačky dohledá:

- pod polem volačky řádek `Callbook: name · locator · CQ 15 · ITU 28`,
- prázdná pole výměny jako lokátor, CQ zóna, ITU zóna a pole `name` se
  předvyplní (call history má přednost; ručně zadané hodnoty se
  nemění a předvyplnění zmizí, když se volačka změní).

Výsledky se ukládají do mezipaměti sdílené s dohledáváním spotů a program se
na stejnou volačku neptá dvakrát.

### Ruční dohledání

Automatické dohledání čeká na pauzu v psaní a respektuje nastavení „Volat … pro módy“.
O dohledání lze požádat i ručně; ignoruje omezení
módů i pauzu, ale stále potřebuje uživatelské jméno a heslo služby:

- **Nastavení → Online callbooks → „Preferovaný online callbook“**
  vybírá HamQTH (výchozí) nebo QRZ.com (klíč konfigurace `preferredCallbook`).
- Poslední tlačítko akční lišty zadávacího okna nese název této služby. Hned se
  zeptá služby na volačku z pole volačky. Výsledek jde do řádku
  `Callbook:` a vyplní prázdná pole výměny, která umí (lokátor, CQ zóna, ITU zóna,
  jméno), podle stejných pravidel jako automatické dohledání: pole, do kterého jste psali, se nikdy
  nepřepíše a vyplnění zmizí, když se volačka změní. Když se nic nenajde,
  řádek řekne proč (nenalezeno, přihlášení selhalo, chyba sítě). Tlačítko je zašedlé s
  nápovědou, když služba nemá přihlašovací údaje nebo je pole volačky prázdné. Funguje i v
  okně VFO B.
- Menu řádku okna deníku („Přehled spojení“) i menu spotu v bandmapě mají
  **Dohledat na HamQTH**, **Dohledat na QRZ.com** a **Dohledat na Google**. Otevřou
  stránku volačky v prohlížeči (`https://www.hamqth.com/<CALL>`, `https://www.qrz.com/db/<CALL>`, hledání Google);
  přihlašovací údaje nejsou potřeba a nic se nedohledává přes API ani nezapisuje do deníku. **Zobrazení**
  má položky pro QRZ.com a Google pro volačku napsanou v zadávacím okně.

## Kontroly lokátoru (VKV)

- **Velký čtverec:** když lokátor nevyplní nic jiného (žádné dřívější QSO, call history ani callbook) a země volačky
  podle dat lokátorů (`multipliers/ww_digi_grid.csv`) vysílá jen z jednoho velkého čtverce (field), pole (`JO`) se
  vyplní; zbytek lokátoru dopište za něj.
- **Lokátor proti zemi:** napsaný lokátor, který nesedí k zemi volačky, ukáže v zadávacím okně červený štítek
  `JN79 nesedí k zemi DL`. Kontrola používá data lokátorů; pro velký čtverec
  bez dat vzdálenost od souřadnic země (3 500 km, jako u lokátorů ve spotech).
