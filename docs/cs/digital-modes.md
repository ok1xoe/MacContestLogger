# Digitální módy

MCL pracuje se dvěma modemy přes zvukovou kartu za stejným oknem Digitální rozhraní:

- **vestavěný RTTY modem** (dekodér a modulátor MMTTY, jako vložené MMTTY v N1MM) — viz
  [Vestavěný RTTY modem (MMTTY)](#vestavěný-rtty-modem-mmtty);
- **fldigi** pro RTTY, PSK a další módy, ovládané přes XML-RPC.

Vše, co je níže popsáno pro Digitální rozhraní — klikání na volačky a slova výměny, okno Grab,
F-klávesy, ESM, Esc, Align/AFC/NET/Rev, AutoTRXUpdate, okno TX, tlačítka zpráv, dvě
rozhraní pro SO2V/SO2R —, funguje stejně s oběma modemy.

## fldigi jako modem (RTTY, PSK...)

Stejně jako N1MM s fldigi umí MCL přenechat modulaci/demodulaci programu **fldigi** a ovládat ho přes jeho
rozhraní XML-RPC.

1. Spusťte fldigi (XML-RPC je ve výchozím stavu zapnuté na portu **7362**).
2. V MCL: **„Nastavení → Digital Modes → Modem pro RTTY / PSK → fldigi“**, zadejte adresu
   a port a klikněte na **„Vyzkoušet“** (ukáže verzi fldigi a
   aktuální modem).
3. Zprávy F1–F12 pro digitální módy jsou v **„Nastavení → Function Keys →
   Digi“**, zvlášť pro Run a S&P (makra
   jako pro CW: `*`/`{MYCALL}`, `!`, `#`, `{SENTRST}`, `{EXCH}`, `{LOG}`,
   `{WIPE}`...; čísla se nezkracují).

V módu RTTY/PSK/... pak F-klávesy vysílají přes fldigi (text do TX
bufferu, zapnutí TX a po odvysílání se fldigi samo přepne na příjem). ESM a opakování
CQ fungují; **Esc** vysílání přeruší (`main.abort`).

## Frekvence a mód (fldigi)

- **AutoTRXUpdate** (N1MM; Nastavení → Digital Modes nebo menu **Nastavení** okna; výchozí zapnuto):
  s rigem v módu postranního pásma (USB/LSB, PKTUSB/PKTLSB, DATA-U/L) ukazuje stupnice potlačenou
  nosnou, takže se QSO **zapíše a spotuje** na stupnici ± audio frekvenci fldigi (USB přičítá,
  LSB odečítá; čte se přes `modem.get_carrier`). V FSK RTTY (mód rigu RTTY/RTTYR) už stupnice
  je frekvence mark a nic se nepřičítá. Stejně jako v N1MM to platí jen, dokud je okno Digitální rozhraní
  otevřené (tehdy se audio frekvence čte), a jen v digitálním módu; frekvence
  napsaná do pole, která se liší od stupnice, se zapíše tak, jak je napsaná. Pole frekvence zadávacího okna
  dál ukazuje stupnici.
- Horní lišta okna ukazuje **přesnou frekvenci** (stupnice ± audio) a audio frekvenci, např.
  `14082.13 kHz · 2125 Hz`.
- **Mód** (N1MM *Op Mode*) vypisuje modemy fldigi (`modem.get_names`; RTTY, BPSK31/63/125, QPSK a CW
  napřed, ostatní pod *Další módy*). Výběr přepne fldigi (`modem.set_by_name`); modem RTTY nebo
  PSK přepne do RTTY nebo PSK i zadávací okno.
- Napsání **RTTY** nebo **PSK** (PSK31, PSK63…) do pole volačky přepne logger **i fldigi**:
  na modemy nastavené v **Nastavení → Digital Modes → Mód fldigi pro RTTY / PSK** (výchozí `RTTY` a
  `BPSK31`).
- Makra `{LDIGFQ}` a `{RDIGFQ}` pošlou frekvenci levé (VFO A / rig 1) a pravé (VFO B /
  rig 2) strany v kHz s jedním desetinným místem (stupnice ± audio jako výše), např. `QSY {LDIGFQ}`.

## Ladění fldigi z loggeru (Align, AFC, NET, Rev, Lock)

Tlačítka vedle řádku TX (ovládání fldigi z N1MM):

- **Align** (také `{ALIGN}`) přeladí rig tak, aby signál pod kurzorem fldigi padl na
  **frekvenci zarovnání** — střed vašeho filtru — a přesune tam kurzor fldigi
  (`modem.set_carrier`). Nezbytné pro FSK, kde je vysílací frekvence daná rigem. Nastavení
  → Digital Modes: *Zarovnání RTTY* (výchozí 2210 Hz — kurzor fldigi je střed, tedy mark 2125 +
  85) a *Zarovnání ostatní* (výchozí 1500 Hz). Směr se řídí módem rigu: USB/PKTUSB nahoru,
  LSB/PKTLSB a FSK RTTY dolů (RTTYR nahoru).
- **AFC**, **Rev** a **Lock** přepínají AFC, reverzi a zámek TX ve fldigi (`main.set_afc`,
  `main.set_reverse`, `main.set_lock`); tučné tlačítko je zapnuté (čte se při otevření okna).
- **NET** („TX follows RX“ z MMTTY) je vypnutý Lock ve fldigi: NET zapnuto = Lock vypnuto.
- `{ENABLEAFC}` / `{DISABLEAFC}` a `{ENABLENET}` / `{DISABLENET}` ve zprávě dělají totéž.
- *AFC zapnout s CQ a TU* (N1MM „AFC On/Off with CQ“): zprávy CQ (F1) a TU (F3) v Run zapnou AFC,
  zprávy S&P ho vypnou.
- *NET podle Run / S&P* (N1MM „NET On/Off with Run Change“): přepnutí na S&P zapne NET (Lock vypnuto),
  na Run ho vypne (Lock zapnuto).
- *Kompenzace posunu FSK* (N1MM Shift Frequency Compensation): v FSK RTTY (mód rigu RTTY/RTTYR) se
  posun (výchozí 170 Hz, může být záporný) přičte k zapisované a zobrazované frekvenci, pro rigy, jejichž
  stupnice neukazuje mark.

## Okno Digitální rozhraní

**„Okno → Digitální rozhraní“** — obdoba
N1MM *Digital Interface*. MCL si bere dekódovaný text z fldigi a kreslí ho
**ve vlastním okně**, takže s ním můžete pracovat přímo:

![Digitální rozhraní s dekódovaným RTTY; volačky a slova výměny jsou podtržené](../img/digital-interface.png)

- **Klik na volačku ji vloží do pole volačky** (vaše vlastní volačka
  podtržená není). Ve fldigi neklikáte — XML-RPC nemá funkci „uživatel klikl na
  slovo“, takže odtud není cesta zpět. Proto musí být text
  v okně loggeru, stejně jako v N1MM.
- **Klik na jinak podtržené slovo ho vloží do výměny.** Kam
  patří, rozhoduje definice závodu: nejdřív `validation` z
  YAML (rozsah, délka, regex), pak tvar podle typu pole. V CQ
  WW RTTY jde `599` do reportu a `15` do zóny — do reportu
  se dostat nemůže, protože RST má tři číslice. Z několika vyhovujících polí vyhrává **první
  prázdné**, takže částečně vyplněnou výměnu klik nepřepíše, dokud
  je kam jinam psát. Slovo, které se nehodí nikam, podtržené není.
- **Dvojitá výměna se rozpozná jako celek.** Pole se přiřazují podle
  volačky **na stejném řádku**, ne podle právě psané — výměna patří
  stanici, která ji poslala. V CQ WW RTTY se u `W3LPL 599 05 NY` zvýrazní zóna
  **i** stát, kdežto u `DL1ABC 599 14` jen zóna,
  protože stát posílají jen stanice W/VE. Do obou polí klikáte zvlášť.
- Nad textem je **seznam volaček** v pořadí, v jakém se volačky
  objevily. Pořadí se nikdy nepřeskupuje — jinak by se v pileupu měnilo pod
  kurzorem a klik by trefil špatnou volačku.
- Horní lišta ukazuje **modem a stav TX/RX** a tlačítko **„Vymazat“**
  (vymaže jen okno; RX buffer ve fldigi zůstane, takže se text
  nezačne číst znovu).
- **F1–F12, Enter a Esc fungují i tady.** Po kliknutí na volačku zůstane klávesnice
  v tomto okně, jinak byste nemohli hned odpálit F4 (volačka) nebo F2
  (výměna). Klávesy se posílají do zadávacího okna, kde žije celá
  logika: **Shift+F** vezme zprávu z opačné sady (Run ↔ S&P),
  **Enter** provede krok ESM nebo zapíše QSO a **Esc** zastaví vysílání.
  Fokus zůstává v okně, takže z jednoho místa můžete vybrat volačku, poslat
  výměnu a zapsat QSO.

## Okno příjmu (N1MM Digital Interface)

**Myš** (klávesy macOS místo kláves N1MM — Ctrl+klik je v systému sekundární klik):

| Myš | Akce |
|---|---|
| klik na volačku | do pole volačky (slovo výměny do jeho pole, jako výše) |
| **Option+klik** | volačka do [zásobníku volaček](call-stacking.md) (N1MM Alt+klik) |
| **Cmd+klik** | slovo pod ukazatelem do pole zadávacího okna, ve kterém je textový kurzor, ať je to kterékoli (N1MM Ctrl+klik) |
| **Shift+klik** | slovo převedené Letters ↔ Figures (RTTY: `TOO` → `599`, `UE` → `73`), pak do pole volačky (volačka), do jejího pole výměny nebo do pole s kurzorem |
| **pravý klik** (nebo Ctrl+klik) | s *Pravý klik = Enter (ESM)* je to Enter — celé QSO lze odjet myší (N1MM „Rt Click = Return NOT menu“); jinak kontextové menu textu |

Pod textem ukazují ukazatele **Pod myší** a **Letters/Figs** slovo pod
ukazatelem a jeho čtení v opačném registru.

**Barvy.** Volačky jsou obarvené jako v bandmapě: podle dupe a počtu nových násobičů na
frekvenci a módu aktivního zadávacího okna. *Ověřování volaček* (N1MM Callsign Validity) v
menu **Nastavení** vybírá: *Vše, co vypadá jako volačka* (obecně), *Jen volačky ze zdrojů* (zvýrazněné
a klikatelné jsou jen volačky nalezené ve vybraných zdrojích) nebo *Obojí, neověřené žlutě*
(výchozí: obecně a volačka, kterou žádný ze zdrojů nezná, dostane **žluté** pozadí).
Zdroje jsou Master.scp, call history, spoty z DX clusteru a volačky v
deníku. *Barva volačky jako pozadí* dá barvu za volačku (značka neověřené volačky se pak
změní na žlutý text). *Hledat volačky z Master.scp i v šumu* najde známou volačku i uvnitř
slova, které samo volačkou není (`EEEEW1AWEEEE`); z několika vyhrává poslední.

**Vaše vlastní vysílání.** Text, který fldigi vrací během vysílání (echo vaší zprávy), se
zobrazuje ztlumeně a jeho volačky nikdy nejdou do seznamu volaček (N1MM: během vysílání se volačky
negrabují).

**Pauza.** Zelený pruh vlevo od textu okno pozastaví (zežloutne): nový text se zadrží
— fldigi se dál čte a seznam volaček se dál plní —, dokud se na pruh znovu neklikne, takže
můžete v klidu rolovat zpět a klikat. S *Pozastavit příjem nad volačkou* ukazatel nad volačkou
okno pozastaví sám, dokud je pole volačky prázdné (pauzovací rutiny N1MM).

**Další volby** v **Nastavení**: *Hover* (volačka pod ukazatelem jde do pole volačky
bez kliknutí), *Po kliku na volačku kurzor do výměny* (N1MM „Send Space on Callsign Mouse Click“),
*Neposuvné okno příjmu* (neposuvné okno N1MM: text na obrazovce se nikdy nehýbe; když přicházející
řádek dojde dolů, okno otočí stránku, takže nejnovější řádek je nahoře, a přicházející
řádek je podtržený) a *V titulku frekvence rigu, ne přesná* (titulek a `{LDIGFQ}`/`{RDIGFQ}`
ukazují stupnici místo stupnice ± audio).

## Okno Grab

Řádek nad textem je **Grab okno** z N1MM: posledních 10 volaček rozpoznaných v přijatém
textu, ta, která se vezme jako další, je zvýrazněná. Nepřidává se: vaše vlastní volačka, volačka, která už je
v poli volačky, text přijatý během vašeho vysílání a (volby v **Nastavení → Grab okno**)
dupy (*Dupy do Grab okna nedávat*, výchozí zapnuto) nebo volačky, které nejsou v Master.scp. Volačka
převzatá z textu kliknutím ze seznamu zmizí. Přidávají se jen volačky nové od posledního čtení, za kterými už
následuje další text, takže se vymazaný seznam znovu nezaplní ze starého textu.

| Klávesa / ovládání | Akce |
|---|---|
| tlačítko **Grab**, **Alt+G**, `{GRAB}` | zvýrazněná volačka do vymazaného zadávacího okna (ze seznamu zmizí). V CW/SSB nebo s prázdným seznamem vezme Alt+G místo toho další volačku ze [zásobníku volaček](call-stacking.md) |
| klik na volačku v řádku | tato volačka do pole volačky |
| **CLR** | vymaže seznam |
| pravý klik na volačku | vybrat ji, smazat ji, vymazat seznam, řazení **LIFO** (nejnovější napřed, výchozí) nebo **FIFO** |
| **Insert** (klávesa Help na klávesnici Macu; také lze přemapovat) | s prázdným polem volačky vezme zvýrazněnou volačku, pak pošle jeho volačku + výměnu (F5+F2); s ESM v S&P nejdřív F4, dokud není zadaná výměna; dupe pošle v Run F6 (nebo F5+F2 s *Work dupes*) a bez ESM nic — tabulka Insert z N1MM; kurzor jde do výměny |
| `{LOGTHENGRAB}` (jen Run) | jako [`{LOGTHENPOP}`](call-stacking.md#logthenpop-zapsat-a-pokračovat), s další volačkou vzatou z okna Grab: `! {LOGTHENGRAB} TU {F5}{F2}`. S prázdným seznamem se QSO zapíše a pošle se zpráva TU. ESM tuto klávesu nikdy samo nevybere — dejte ji na vlastní klávesu (N1MM: nedávat do klávesy TU ani Next Call) |
| `{DELALL}` / `{DELTOP}` / `{DELSEL}` | smaže celý seznam / jeho vrchol / zvýrazněnou volačku |
| `{SCQ}` | obnovit CQ: zapne opakování CQ (Run) — dejte ho na konec zprávy TU |

Další volby v **Nastavení → Grab okno**: *QSY vymaže Grab okno* (změna frekvence o víc než
500 Hz seznam vymaže), *CQ vymaže Grab okno* (odeslání F1 ho vymaže), *Po grabu kurzor do výměny*
(N1MM „Send Space on Using Grab“) a *Při grabu dát volačku z pole do bandmapy* (volačka, kterou
grab nahradí, se nejdřív uloží do bandmapy, jako Alt+O).

Se zapnutým Digital Call Stacking (Run) dá Alt+G do zásobníku volaček i volačku, která byla v poli,
a **Ctrl+Alt+G** přesune zvýrazněnou volačku z Grab do zásobníku, aniž by se dotkl
pole.

## Vysílání: okno TX, makra a tlačítka

**Okno TX** (N1MM): řádek pod textem. **Alt+T** nebo tlačítko **TX** (v digitálním módu) spustí
vysílání fldigi; každý znak napsaný do řádku pak hned odchází, Enter začne nový řádek.
**Alt+T** znovu nebo **RX** se po odvysílání textu vrátí na příjem (`^r` fldigi); **Esc** zastaví hned.
Bez vysílání pošle Enter napsaný řádek jako zprávu. **Ctrl+K** v digitálním módu otevře
okno, spustí vysílání a dá kurzor do řádku TX (v CW dál otevírá CW z klávesnice).

**Makra digitálních zpráv** (také vše z CW klíče):

| Makro | Akce |
|---|---|
| `{TX}` / `{RX}` | Zprávy N1MM začínají `{TX}` a končí `{RX}`. Zpráva **s `{TX}` a bez `{RX}` nechá fldigi vysílat** (ukončí to okno TX, Alt+T nebo Esc). Zpráva bez obou funguje jako dřív (fldigi se po ní vrátí na příjem). Samotné `{TX}` nebo `{RX}` přepne na vysílání / zpět na příjem |
| `{ENTERLF}`, `{ENTER}` | nový řádek |
| `{CLRRX}` / `{CLRTX}` | vymaže přijatý text Digitálního rozhraní / TX buffer fldigi |
| `{ALT-T}` / `{ALT-Q}` | jako Alt+T (vysílání zap/vyp) / Alt+Q (zpět na CQ frekvenci) |
| `{FILE:name}` | text souboru ve složce `FunctionKeyMessages` v datové složce (nejvýš 64 kB, zalomení řádků se zachová) |
| `{DI1}`…`{DI24}` | text tlačítka zprávy |
| `{NAME}` | jméno protistanice z [call history](call-history.md) |
| `{ESC}` | zastaví probíhající vysílání, než tato zpráva odejde (jako Esc) |
| `{PROFILE1}`…`{PROFILE16}` | profil n vestavěného modemu na vysílající přijímač, než text odejde (prázdný slot nastavení ponechá a oznámí to) |
| `{Hxx}` / `{Hxxxx}` | znak s tímto šestnáctkovým kódem, např. `{H0D}` (CR) nebo `{H2B}` (`+`); řídicí kódy jiné než CR/LF se neposílají |

`{TX}`, `{RX}`, `{CLRTX}` a `{ALT-T}` v CW a SSB nedělají nic.

**Tlačítka zpráv.** **Nastavení → Digital Modes → Tlačítka zpráv Digitálního rozhraní** (nebo v okně
**Nastavení → Tlačítka zpráv**) ukáže pod textem 0, 8, 16 nebo 24 dalších tlačítek DI1–DI24; jejich
texty používají stejná makra a posílají se z aktivního zadávacího okna (s jeho kontrolkou, Esc, `{LOGTHENPOP}`).
**Načíst .mc… / Uložit .mc…** je čte a zapisuje jako soubor zpráv N1MM (`Label,Text` na řádek).

**Nastavení → Odeslat textový soubor…** pošle textový soubor přes fldigi (nejvýš 64 kB).

**CW ID** (Nastavení → Digital Modes nebo menu Nastavení okna): po každém digitálním vysílání se fldigi
přepne na svůj CW modem, pošle text (výchozí `DE {MYCALL}`) a obnoví se předchozí modem;
Esc ho zastaví jako každé vysílání (modem se také obnoví).

**Nastavení → Ukládat přijatý text do souboru** (N1MM „Output Main RX Window to Text File“) připojuje
vše přijaté do `ExportFiles/<MMddyyyy>DigitalInterface1Output.txt` v datové složce.

## Zásobník volaček (call stacking)

**Option+klik** (N1MM Alt+klik) na volačku, v textu nebo v seznamu volaček, ji dá do
[zásobníku volaček](call-stacking.md), aniž by se dotkl pole volačky. Menu **Nastavení**
okna má N1MM **Digital Call Stacking**: *Vypnuto*, *FIFO*, *LIFO* nebo *FIFO, násobiče
napřed*. Když je zapnuté a jste v **Run** s volačkou už v poli,
obyčejný klik na jinou volačku jednu z nich uloží do zásobníku místo nahrazení pole: FIFO uloží
kliknutou volačku, LIFO uloží volačku z pole a kliknutou vloží. Klávesa
s `{LOGTHENPOP}` (například `! {LOGTHENPOP} TU {F5}{F2}`, i jako klávesa Next Call v ESM) pak
pracuje uložené stanice jednu po druhé.

Čtení je **přírůstkové**: MCL se ptá na délku RX bufferu
(`text.get_rx_length`) a stahuje jen to, co ještě nemá (`text.get_rx`).
Když buffer ve fldigi vymažete, pozná se to podle zkrácení a čtení
začne od začátku, ale historie v okně zůstane. Interval
čtení je 300 ms — ve srovnání s MMTTY vloženým přímo v N1MM se text zpožďuje
o tento zlomek sekundy.

S vestavěným modemem čte okno text svého přijímače stejně každých 300 ms, z paměti místo
přes XML-RPC.

## SO2V / SO2R: dvě Digitální rozhraní

Stejně jako v N1MM může mít každé zadávací okno vlastní Digitální rozhraní: **Okno → Digitální rozhraní** (DI1)
patří k VFO A / rigu 1, **Okno → Digitální rozhraní 2** (DI2) k VFO B / rigu 2. Spusťte druhé fldigi
(jiný port XML-RPC, např. `fldigi --xmlrpc-server-port 7363`) a nastavte ho v **Nastavení → Digital Modes
→ Druhé fldigi (SO2V/SO2R)**; port 0 znamená žádné druhé fldigi (DI2 pak ukazuje fldigi rozhraní DI1).

- Klik v DI2 vyplňuje okno VFO B; jeho klávesy, Enter a tlačítka působí na okno VFO B.
- Dokud je aktivní okno VFO B / rigu 2, F-klávesy a makra vysílají přes druhé fldigi;
  okno, které má fokus vysílání, ukazuje ve své horní liště červené **TX**.
- **Cmd+Alt+←** / **Cmd+Alt+→** (N1MM Ctrl+←/→, které macOS používá pro Spaces) aktivuje VFO A / rig 1
  nebo VFO B / rig 2 a vynese jeho Digitální rozhraní dopředu.
- Obě okna sdílejí jedno okno Grab a jeden zásobník volaček.
- **TX lockout mezi DI1 a DI2** (N1MM Config → SO2R *TX lockout
  (digital)*), v Nastavení → Digital Modes: *Vypnuto* (výchozí — vysílat smějí obě fldigi),
  *První vyhrává* (zatímco jedno rozhraní vysílá, druhé se odmítne s
  „TX LOCKOUT: DI1 vysílá — nevysílám“), *Poslední vyhrává* (fldigi vysílajícího rozhraní
  se přeruší a odejde nové vysílání).

### Další příjmová okna

N1MM umí dekódovat stejné audio více dekodéry. Zde je každý další dekodér další instance fldigi
poslouchající stejnou zvukovou kartu: vypište je v **Nastavení → Digital Modes → Další příjmová
okna** (`host:port`, nejvýš čtyři). Jejich text se objeví připojený nad textem DI1 (N1MM „Enable Attached
RX Windows“) a s *Volačky z nich do Grab okna* (N1MM „RX Windows add to Grab window“) se jejich
volačky přidávají do okna Grab. Klikat do nich nejde — jsou na čtení.

Vícekanálový PSK prohlížeč (vícekanálové MMVARI, signal browser fldigi) **k dispozici není**: rozhraní
XML-RPC fldigi kanály svého prohlížeče nezpřístupňuje. Náhradním řešením je několik instancí fldigi jako další
příjmová okna.

## RTTY hardware: TU/TNC, TinyFSK, WinKeyer 3.1

**Nastavení → Digital Modes → RTTY: rozhraní pro vysílání** je *Default RTTY Interface* z N1MM. PSK a
ostatní módy přes zvukovou kartu jdou vždy přes fldigi; v RTTY mohou zprávy jít do:

| Rozhraní | Vysílání | Příjem | Esc |
|---|---|---|---|
| **fldigi** (výchozí) | AFSK nebo vlastní FSK fldigi | fldigi | `main.abort` |
| **TU / TNC** (PK-232, KAM, HAL DXP-38, jiné) | sériový port: příkaz **{TX}**, text, příkaz **{RX}** | text z TNC v Digitálním rozhraní | příkaz **Esc** |
| **TinyFSK** (FSK klíčovač K0SM s Arduinem, 9600 8N1) | `[` text `]` | fldigi | `\` |
| **WinKeyer 3.1** (WinKeyer z CW klíče) | režim FSK RTTY (`00 13`), `[` text `]` | fldigi | `\` |

- Příkazy TNC mohou používat `{CTRL-A}`…`{CTRL-Z}`, `{ENTER}`, `{ENTERLF}`, `{ESC}`; prázdná pole použijí výchozí
  hodnoty typu (příklady N1MM: PK-232 `X{ENTER}` / `{CTRL-D}` / `{CTRL-C}R{ENTER}TC{ENTER}`, KAM `{CTRL-C}T` /
  `{CTRL-C}E` / `{CTRL-C}R RTTY {ENTER}`). HAL DXP-38 předvolbu nemá — zadejte jeho příkazy z jeho manuálu.
- WinKeyer: rychlost 45,45/50/75/100 Bd, *Reverse* a *FSKMAP* (FSK na KEY, PTT klíčuje rig). Odeslání CW
  nejdřív vypne režim RTTY WinKeyeru.
- Žádné z těchto zařízení nehlásí konec vysílání: kontrolka F-klávesy zhasne po
  době, kterou text při rychlosti RTTY trvá (N1MM má s TNC stejné omezení). `{TX}` bez `{RX}`,
  Alt+T a okno TX drží vysílání jako s fldigi.
- RTTY přes hardwarový klíčovač funguje bez fldigi; Digitální rozhraní pak fldigi (nebo
  TNC) potřebuje jen pro příjem.
- **Hardwarové cesty jsou implementované podle dokumentace zařízení (sketch TinyFSK, API K1EL WK 3.1,
  příklady TNC z N1MM) a testované jen proti atrapám — ne na skutečném hardwaru.**

## Vzhled

**Nastavení → Digital Modes → Vzhled Digitálního rozhraní** (N1MM Skins, Colors and Fonts):
písmo přijatého textu (prázdné = systémové neproporcionální písmo), jeho barva a pozadí
(`#RRGGBB`); velikost se řídí ovladačem velikosti písma okna. *Barva volačky jako pozadí* v menu
okna dá barvy stavu za volačky.

## Vestavěný RTTY modem (MMTTY)

N1MM vkládá MMTTY; MCL má jádro RTTY z MMTTY vestavěné. Dekodér a modulátor jsou z MMTTY (Makoto Mori,
JE3HHT, a Nobuyuki Oba, JA7UDE), převzaté beze změny přes port pro macOS **RYRY**; licence jsou
v `third-party/MMTTY/NOTICE.md` a v okně O aplikaci.

**Nastavení → Digital Modes → Modem pro RTTY / PSK → „Vestavěný (MMTTY, jen RTTY)“**. PSK a ostatní
módy dál potřebují fldigi.

### Dva přijímače, jeden stereo vstup

Každé Digitální rozhraní má vlastní přijímač: **DI1** = rádio 1 / VFO A, **DI2** = rádio 2 / VFO B.
Obvyklé zapojení SO2R / SO2V je jeden **stereo** vstup zvukové karty s audiem rádia 1 v levém kanálu a
rádia 2 v pravém (N1MM: „2 RX: audio left, audio right“). Pro každý přijímač vybíráte v
nastavení:

| Volba | Možnosti | Výchozí |
|---|---|---|
| Vstup | vstup přijímače z **Nastavení → Audio** nebo vlastní vstup rádia 2 (ten, který je vybraný v oknech rádia 2, např. CW Reader 2) | vstup přijímače |
| Kanál | levý, pravý, oba (smíchané) | přijímač 1 levý, přijímač 2 pravý |

Mono vstup dává stejné audio v obou kanálech. Přijímač poslouchá, jen dokud je okno jeho Digitálního rozhraní
otevřené, a vstup sdílí s vodopádem, CW Readerem a nahráváním závodu.

**Ladění je pro každý přijímač nezávislé** (mark, posun, rychlost, AFC, NET, Rev): každé okno ladí svůj
přijímač. *Společné ladění obou přijímačů* zajistí, že se změna na jednom
přijímači provede i na druhém.

### Okna přijímačů

Stejně jako v N1MM je každý přijímač skupina: nahoře jeho dekódovaný text a pod ním jeho **panel RTTY enginu** (okno
enginu MMTTY). DI1 se otevře v levé polovině obrazovky a DI2 v pravé; obě jsou
v menu Okno (*Digitální rozhraní*, *Digitální rozhraní 2*) a pamatují si, kam jste je dali.
Klik na volačku nebo slovo výměny jde do zadávacího okna toho rádia.

Panel enginu:

- **Spektrum a vodopád** se značkami **mark** (žlutá) a **space** (oranžová). **Klik** dá
  mark pod ukazatel (posun zůstane); **pravé tlačítko** tam nastaví notch MMTTY; **kolečko**
  posouvá práh squelche.
- **M / S** — frekvence mark a space; se zapnutým AFC sledují signál.
- **Posun** (shift: 170, 200, 425, 850 Hz) a **rychlost** (45,45, 50, 75, 100, 110 Bd; také menu Op Mode:
  `RTTY` = 45,45, `RTTY-50`, `RTTY-75`…).
- **Demodulátor** (IIR, FIR, PLL nebo FFT z MMTTY; výchozí IIR).
- **Profil** — profily modemu MMTTY: 16 slotů v `RttyProfiles.json` v datové složce. *Uložit do*
  uloží celé nastavení tohoto přijímače — posun, rychlost, demodulátor, AFC/NET/Rev, squelch, filtry,
  volby AA6YQ/LMS/notch — pod jménem; *Načíst* dá profil na tento přijímač (se společným laděním na
  oba); *Smazat* vyprázdní slot. Soubor profilů, který nejde přečíst, se nikdy nepřepíše.
- **SQ** — squelch (text jen nad prahem, červená čára v měřiči úrovně).
- **XY** — XY osciloskop MMTTY: mark proti space; správně naladěný signál je kříž.
- Rozsah zobrazení (300–3000, 1000–2500, 1700–2700 nebo 0–6000 Hz).
- **Kanály** — vícekanálový příjem MMTTY (RTTY prohlížeč N1MM): další dekodéry se spustí na
  signálech RTTY nalezených ve spektru tohoto přijímače (dvojice tónů vzdálených o posun přijímače), každý sleduje svůj
  signál s AFC a používá posun, rychlost a Rev přijímače. Řádek pro každý kanál ukazuje jeho mark, jeho volačky a
  jeho poslední text: **klik na volačku** ji vloží do zadávacího okna tohoto rádia, klik na **mark** tam naladí
  přijímač. *Nastavení → Digital Modes*: nejvýš 1–8 kanálů (výchozí 4) a počet sekund, po který kanál vydrží
  bez signálu (výchozí 15). Kanály jen přijímají; zastaví se, když se okno zavře.

**AFC**, **NET** a **Rev** vedle řádku TX přepínají přijímač okna, **Align** funguje jako s
fldigi (nosná je střed mezi mark a space, takže výchozí frekvence zarovnání 2210 Hz je
mark 2125 + 85). AutoTRXUpdate v USB/LSB zapisuje a spotuje stupnici ± tento střed.

### Vysílání

- **AFSK**: audio modulátoru jde na vybraný zvukový výstup (*Výstup AFSK*; rádio 2 může mít vlastní,
  prázdné = výstup rádia 1) s *Úroveň AFSK* (výchozí 50 %). **PTT** se klíčuje přes CAT na rigu
  vysílající strany (*PTT přes CAT*, výchozí zapnuto; vypnuto = VOX nebo vlastní datové PTT rigu).
- **FSK, vestavěné** (EXTFSK z MMTTY bez pluginu; výchozí vypnuto): *FSK přes sériový port* určuje sériový
  port, jehož linka **DTR** nebo **RTS** klíčuje FSK vstup rigu (rig v módu RTTY/FSK). Znaky Baudot modulátoru
  se klíčují s přesným časováním ve vlákně reálného času (1 start bit, 5 datových bitů, 1,5 stop bitu při
  rychlosti přijímače; klid = mark, aktivní linka = space, *obrácená polarita* je prohodí). PTT jde na druhou
  linku portu, nebo — s *CAT / VOX* — jako u AFSK. Žádné audio se neposílá; vlastní text se přesto dekóduje zpět jako echo.
  Linka TX portu (break) se nepoužívá.
- **FSK přes klíčovač**: vyberte TinyFSK nebo WinKeyer 3.1 v **RTTY: rozhraní pro vysílání** — zprávy pak jdou
  do klíčovače a vestavěný modem jen přijímá (jako s fldigi).
- F-klávesy, ESM, opakování CQ, okno TX, `{TX}`/`{RX}` a tlačítka zpráv fungují jako s
  fldigi; **Esc** zastaví hned (výstup se zastaví, PTT se uvolní). Váš vlastní text se dekóduje zpět
  z modulátoru (zobrazený ztlumeně, nikdy se negrabuje).
- Se dvěma přijímači vysílá strana, která má fokus vysílání; platí *TX lockout mezi DI1 a DI2*.
- CW ID (Nastavení → Digital Modes) potřebuje CW modem fldigi a s vestavěným modemem se přeskočí.
- Každý nový přijímač začíná na mark 2125 Hz, posun 170 Hz, 45,45 Bd se zapnutým AFC a NET.

Nic nevysílá, dokud nepošlete zprávu, nestisknete TX nebo Alt+T; vestavěný modem je vypnutý, dokud
ho nevyberete v nastavení.

## Sdílení CAT s fldigi

Když MCL ovládá rig, jeho `rigctld` drží sériový port a fldigi **ho
neotevře**. Ve fldigi proto nastavte **Configure → Rig Control → Hamlib**, rig
**Hamlib NET rigctl** a zařízení `localhost:4532` — oba programy pak mluví s jedním
démonem. PTT nechte na „PTT via Hamlib command“; RTS/DTR na tomto
portu použít nelze a u rigů s hardwarovým handshake (např. TS-590SG přes USB) je hamlib
odmítne.

V režimu **„Spustit rigctld“** je ovšem démon
podproces MCL, takže když se aplikace ukončí, skončí i on a fldigi ztratí
spojení (pomůže jen „Initialize“ v jeho nastavení ovládání rigu). Kdo provozuje
digitální módy pravidelně, měl by **démona spouštět sám** a zvolit
**„Připojit k běžícímu“** v **„Nastavení → Hardware →
Připojení“**:

```bash
rigctld -m <model> -r <zařízení> -s <rychlost> -t 4532
```

Restart MCL pak fldigi nerozhodí. V macOS to lze pověsit na launchd
agenta (`~/Library/LaunchAgents`), aby se démon spouštěl sám po přihlášení.
