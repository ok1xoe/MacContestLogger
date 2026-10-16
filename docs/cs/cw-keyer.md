# CW klíč

V módu CW posílají funkční klávesy F1–F12 CW zprávy. Klíčovat lze dvěma způsoby,
stejně jako v N1MM+
([Choosing Your CW Method](https://n1mmwp.hamdocs.com/setup/interfacing/#Choosing_Your_CW_Method))
a DXLog
([Winkey configuration](https://dxlog.net/docs/index.php?title=Menu_Options#Winkey_configuration)).

## „Nastavení → CW klíč“

| Způsob | Jak funguje | Co umí |
|---|---|---|
| **Klíčovač rigu přes CAT (rigctld)** (výchozí) | text jde přes rigctld do klíčovače vestavěného v rigu (hamlib `send_morse`), např. Kenwood TS-590, Icom, Yaesu, Elecraft | prostý text. Zkratky (prosigns) se posílají jako dvojice písmen; změny rychlosti `<` `>` uvnitř zprávy rig nepodporuje |
| **K1EL Winkeyer (sériový port)** | sériový port (USB), protokol Winkeyer 2/3 | všechno: zkratky (AR, SK...), změny rychlosti uvnitř zprávy, přesné přerušení |
| **Linka DTR/RTS sériového portu (jednoduché rozhraní)** | jednoduché tranzistorové rozhraní na sériovém (USB) portu: jedna linka klíčuje CW, druhá PTT | všechno, co Winkeyer umí z klávesnice (prvky tvoří logger); bez pádel |
| **Vypnuto** | | |

Pro CAT musí být transceiver připojený (ikona v informační liště) a **rig
musí být v módu CW**. Jinak hamlib vysílání odmítne. Rychlost se na
rigu nastaví automaticky před zprávou.

**Rig musí mít také zapnutý break-in.** Při CW přes CAT si rig klíčuje
sám, když text přijme, a většina rigů to dělá jen se zapnutým break-in;
s vypnutým break-in se zpráva přijme bez chyby (CAT log ukáže
`RPRT 0`), ale rig jen přehraje příposlech, nebo nic, a nevysílá.
Na Kenwoodu TS-590S/SG stiskněte v módu CW **VOX** (rozsvítí se „BK-IN“); semi nebo
full break-in a zpoždění se nastavují v CW menu rigu. Když F-klávesy na pásmu „nic
nedělají“, zkontrolujte nejdřív break-in.

Další volby:
- **Rychlost (WPM):** výchozí 28. V zadávacím okně ji měníte
  klávesami **PgUp / PgDn** (±2 WPM) nebo číselníkem. Ukládá se při ukončení programu.
- **Cut čísla:** pořadová čísla s 0 → T a 9 → N (109 → 1TN).
- **Úvodní nuly:** pořadová čísla doplněná na tři číslice (007).

### Váha a mezery

- **Váha CW (%)** (N1MM, záložka Other, „CW Weight“): 30–70, výchozí 50
  (standardní poměr 1:1). Vyšší hodnoty prodlouží každý prvek a zkrátí mezeru
  za ním, takže rychlost zůstane stejná.
- **Závodní mezera mezi slovy (6 teček místo 7)** (N1MM „Use CW contest word spacing“): 6 teček
  mezi slovy místo 7.

Obojí platí pro klíčovače, které si prvky tvoří samy (Winkeyer, když se mu
nastavení posílají). Klíčovač rigu přes CAT používá vlastní nastavení váhy v rigu.

### Klíčování DTR/RTS a PTT

V N1MM port CW/Other s DTR nebo RTS nastaveným na *CW* / *PTT*. Vyberte port,
**Linku CW** (DTR nebo RTS) a volitelně **Linku PTT** (tu druhou).
Port se otevře s oběma linkami dole, takže se nic neklíčuje, dokud se nepošle zpráva,
a Esc, zavření klíčovače i ukončení programu vždy nechají klíč uvolněný a PTT vypnuté.

- **Zpoždění PTT před vysíláním (ms)** (N1MM „PTT Delay“): PTT se zapne a
  první prvek následuje až po tomto zpoždění, takže relé zesilovače nikdy
  nepřepíná pod výkonem. Výchozí 50 ms.
- **Doběh PTT po vysílání (ms):** jak dlouho zůstane PTT zapnuté po posledním prvku
  (výchozí 30 ms). Mezi zprávami poslanými těsně za sebou zůstává PTT zapnuté.
- **PTT příkazem rádia (CAT) při CW** (N1MM „PTT via Radio Command“, mód
  CW): CAT PTT rigu (`T 1` / `T 0`) se zapne a vypne kolem zprávy,
  se stejným zpožděním a doběhem, navíc k lince PTT (nebo místo ní).
  Bez připojeného rigu se zpráva neodklíčuje.

Prvky časuje logger ve vlastním vlákně s vysokou prioritou (platí váha
a závodní mezera mezi slovy); změny rychlosti `<` `>` i zkratky fungují. Ladění
(Ctrl+T) zapne PTT, počká zpoždění a drží klíč stisknutý.

PTT příkazem rádia podle módu: **CW** = volba výše (klíčovač rigu přes CAT
a Winkeyer si klíčují PTT samy); **SSB** = *Hlasový klíč → PTT přes CAT*;
**digitální módy** = PTT si klíčuje fldigi, TinyFSK nebo TNC samo.

Poznámka: macOS při otevírání sériového portu na okamžik zvedne DTR; pokud na to vaše rozhraní reaguje,
použijte pro PTT linku RTS.

### Příposlech CW zvukovou kartou

*Přehrávat odesílané CW jako tón* (výchozí vypnuto) přehraje každou odeslanou CW zprávu jako
příposlech na vybraném zvukovém výstupu, s vlastní výškou tónu (300–1200 Hz) a
hlasitostí. Tón se tvoří ze stejné posloupnosti prvků jako klíčování DTR/RTS
(váha, mezery mezi slovy, změny rychlosti, zpoždění PTT před prvním prvkem),
s měkkými hranami. Esc ho zastaví. Je určený pro klíčování DTR/RTS; Winkeyer i
většina rigů mají vlastní příposlech.

### Nastavení Winkeyeru

Záložka Winkey v N1MM. Nic se neposílá, dokud není zaškrtnuto **Posílat nastavení do Winkeyeru při
otevření**; bez toho si Winkeyer ponechá vlastní nastavení (po zapnutí) jako
dřív. Je-li zaškrtnuto, nastavení se pošle po otevření hostitelského režimu a znovu po každé
změně (s další zprávou), s klíčovačem v režimu Winkeyer 2 (WK3 ho přijme):

| Nastavení | Příkaz Winkeyeru |
|---|---|
| Režim klíčování: Iambic B (výchozí), Iambic A, Ultimatic, Semi-auto (bug) | mode register |
| Autospace, Prohodit pádla, Závodní mezera mezi slovy | mode register |
| Příposlech zapnutý, Příposlech jen při klíčování pádly, Kmitočet příposlechu (400–4000 Hz v krocích Winkeyeru) | sidetone + pin config |
| Váha CW | weight |
| PTT výstup, PTT náběh a doběh (kroky 10 ms, až 2,55 s; doběh 0 = rozhoduje doba držení) | PTT lead/tail + pin config |
| Doba držení PTT: 1; 1,33; 1,67 nebo 2 mezery mezi slovy | pin config |
| Prodloužení prvního znaku, Kompenzace klíčování (ms) | first extension, keying compensation |
| Potenciometr rychlosti: minimum a rozsah (WPM) | speed pot setup |

CW a PTT jdou na výstupy KEY 1 / PTT 1. Nastavte náběh PTT dost dlouhý pro
relé vašeho zesilovače (N1MM doporučuje aspoň 10 ms, když se PTT používá), aby
nikdy nepřepínalo pod výkonem.

**Potenciometr rychlosti:** *Potenciometr rychlosti ignorovat* (výchozí) — Winkeyer vysílá
rychlostí loggeru bez ohledu na knoflík. *Potenciometr rychlosti mění rychlost CW v deníku*
— otočení knoflíkem nastaví rychlost CW v zadávacím okně, stejně jako
PgUp / PgDn (poloha se přečte i jednou při otevření klíčovače). Třetí volba N1MM
(potenciometr jen pro CW z pádel a klávesnice) k dispozici není.

## „Nastavení → Function Keys → CW“

Zprávy F1–F12 zvlášť pro **Run** a **S&P**. Výchozí sada odpovídá
N1MM „CW Default Messages.mc“. Záložka se otevře přes Alt+K nebo pravým klikem na
tlačítko F-klávesy v zadávacím okně (na sadě, kterou klávesy právě posílají); najetí myší na
tlačítko ukáže jeho zprávu.

### Soubory funkčních kláves (.mc)

Sady SSB, CW a Digi se čtou a zapisují jako soubory funkčních kláves N1MM:
**Načíst .mc…** naplní zobrazenou sadu ze souboru, **Uložit .mc…** ji zapíše,
**Kopírovat do schránky** ji zkopíruje jako text souboru. V souboru jsou řádky začínající
`#` komentáře; každý jiný řádek je zpráva (i prázdné řádky), `Label,Message`;
řádky 1–12 jsou zprávy Run F1–F12, řádky 13–24 zprávy S&P (chybějící zprávy S&P
opakují zprávy Run), `&&` v popisku je `&`. Vlastní soubory `.mc` z N1MM se načtou tak, jak jsou.

**Soubor závodu (N1MM Associated Files).** S otevřeným závodem **Přiřadit soubor k
závodu…** načte soubor do sady a zapamatuje si ho pro závod; **Uložit
jako soubor závodu…** uloží sadu do nového souboru a přiřadí ho. Soubory závodu se
načtou při každém otevření závodu a změna sady v Nastavení se zapíše zpět do
jejího souboru. **Zrušit přiřazení** přiřazení odstraní.

**Samostatné soubory pro každého operátora** (Nastavení → Other, N1MM „Use Separate Function Key
Files for Each Operator“): operátor jiný než volačka stanice, který se přihlásí přes
Ctrl+O nebo `OPON`, dostane poprvé kopii zpráv stanice a potom své vlastní
zprávy; jeho změny se nikdy nedotknou zpráv stanice (master), které
se vrátí, když se znovu přihlásí volačka stanice. Soubory operátorů se ukládají ve
složce `FunctionKeys/` v datové složce.

| Makro | Význam |
|---|---|
| `*` nebo `{MYCALL}` | moje volačka |
| `!` nebo `{CALL}` | volačka z pole volačky; když je pole prázdné, poslední zapsaná |
| `#` | pořadové číslo (podle voleb cut čísla / úvodní nuly) |
| `{SENTRST}` | odeslaný report z pole Snt |
| `{SENTRSTCUT}` | totéž s cut číslicemi (599 → 5NN) |
| `{EXCH}` | odesílaná výměna z nastavení závodu bez reportu; automatické pořadové číslo se dosadí jako `#` |
| `]` `[` `+` `=` | zkratky SK, AS, AR, BT |
| `<` `>` | rychlost +2 / −2 WPM od tohoto místa zprávy (jen Winkeyer) |
| `~` | poloviční mezera (posílá se jako mezera) |
| `{LOG}` | zapíše QSO |
| `{WIPE}` | vymaže pole |
| `{RUN}` / `{S&P}` | přepne režim |
| `{LDIGFQ}` / `{RDIGFQ}` | frekvence levého / pravého rigu v kHz (v digitálních módech dial ± audio fldigi, viz [digital-modes.md](digital-modes.md#frekvence-a-mód-fldigi)) |
| `{STACKANOTHER}` / `{SOCALLSTACK}` / `{CLRSTACK}` | [zásobník volaček](call-stacking.md): uložit volačku / prohodit ji se zásobníkem / vymazat zásobník |
| `{GRAB}`, `{LOGTHENGRAB}`, `{DELALL}`, `{DELTOP}`, `{DELSEL}`, `{SCQ}` | [okno Grab](digital-modes.md#okno-grab) Digitálního rozhraní |
| `{LOGTHENPOP}` / `{LOGTHENNEXT}` | zapíše QSO a pokračuje další volačkou ze zásobníku; text za makrem jde další stanici ([zásobník volaček](call-stacking.md#logthenpop-zapsat-a-pokračovat)) |

Jiná makra v `{}` se zatím neposílají a stavový řádek na ně upozorní.

Příklad výměny pro CQ WPX (pořadové číslo): `{SENTRSTCUT} #`, pro CQ WW
(zóna z nastavení závodu): `{SENTRSTCUT} {EXCH}`.

## Ovládání

| Klávesa | Akce |
|---|---|
| **F1–F12** nebo klik na tlačítko | pošle zprávu. Běžící zpráva se přeruší, nebo se s [řazením F-kláves za sebou](esm.md#volby-nastavení--function-keys--esm) nová zařadí za ni |
| **Esc** | zastaví vysílání. Pole vymaže až další Esc |
| **PgUp / PgDn** | rychlost ±2 WPM |

Tlačítko právě odesílané zprávy svítí, dokud se vysílá. Délka
se počítá ze skutečného časování Morseovy abecedy a rychlosti.

## Další makra (N1MM)

| Makro | Obsah |
|---|---|
| `{LOGGEDCALL}` | naposledy zapsaná volačka |
| `{NR}` | pořadové číslo (totéž co `#`) |
| `{MYNAME}`, `{MYGRID}` / `{MYLOC}`, `{MYCQZONE}` / `{MYZONE}`, `{MYITUZONE}`, `{MYSTATE}` | údaje stanice z „Nastavení → Stanice“ |
| `{OPERATOR}` | operátor u klíče |
| `{TIME}` | čas UTC `HHmm` |
| `{F1}`...`{F12}` | vloží text jiné F-klávesy ze stejné sady (řetězení, nejvýš 2 úrovně) |
| `{CLEARRIT}` / `{RITCLEAR}` | vynuluje RIT |
| `{CQFREQ}` | skok na CQ frekvenci (a vymazání polí) |
| `{NOSPLIT}` | vypne split |
| `{SPOTME}` | spotuje vlastní stanici do DX clusteru na frekvenci zadávacího okna, s [komentářem spotu](dx-cluster.md#komentář-spotu-spotování-qso-v-sp-a-speciální-volačky) (`CQ`, když je prázdný); ověřte, že pravidla závodu self-spoty povolují |
| `{LASTCALL}`, `{PREVNR}`, `{LASTEXCH}`, `{PREVTIME}` | poslední zapsané QSO: jeho volačka, odeslané číslo, přijatá výměna, jeho čas UTC `HHmm` (pro opakování po zapsání QSO) |
| `{NAME}` | pole Name zadávacího okna; když je prázdné nebo ho závod nemá, jméno z call history |
| `{NAMEANDSPACE}` | totéž následované mezerou (nic, když jméno není) |
| `{CHNAME}` | jméno z call history, i když je dohledávání v call history vypnuté |
| `{GRID}` | můj lokátor (Nastavení → Stanice); `{CLUSTER}` přihlašovací jméno do DX clusteru (volačka stanice, když žádné není nastavené) |
| `{FREQ}` / `{FREQROUND}` | frekvence zadávacího okna v kHz (`14025R3` v CW: R místo desetinné čárky) / zaokrouhlená na kHz |
| `{LRMHZ}` / `{RRMHZ}` | celé MHz VFO A / rádia 1 a VFO B / rádia 2 |
| `{GRIDSQUARE}`, `{GRIDBEARING}`, `{REVGRIDBEARING}`, `{KMGRIDDISTANCE}` | lokátor v zadávacím okně, azimut k němu, zpětný azimut a vzdálenost v km od mého lokátoru (předávání stanic na VKV: `{CALL} {GRIDSQUARE} {GRIDBEARING} deg {KMGRIDDISTANCE} km`) |
| `{TIME2}` / `{TIMEGMT}` | UTC `HHmm` / `HH:mm:ss` |
| `{TIME1}`, `{DATE}`, `{DATE1}`, `{DAYTIME}` | místní `HH:mm:ss`, krátké datum v regionálním formátu systému, `dd.mm.yy`, `yymmddhhmm` |
| `{DATEGMT}`, `{TIMESTAMP}` | datum a čas UTC v regionálním formátu / `yyyy-mm-dd hhmm` |
| `{VARYMSG1&Primary&Alternate&N&}` / `{VARYMSG2…}` | střídavý text: `N` = 0 vždy hlavní, 1 vždy alternativní, víc než 1 alternativní při každém N-tém odeslání (`{VARYMSG1 &CQ * *&CQ CQ * *&3&}` pošle delší CQ každý třetí raz). Počítadla počítají odeslání ve všech módech |
| `{CQ}` | klávesa funguje jako klávesa CQ: zapamatuje se Run a CQ frekvence, jako u F1 |
| `{QSYCQ}` | totéž co `{CQFREQ}` |
| `{EXCHSENT}` | ESM bere výměnu jako odeslanou (výměna odeslaná z jiné klávesy) |
| `{CTRLHOME}` | kurzor do pole volačky s označeným textem |
| `{FORCELOG}` / `{FORCELOGNOTE}` | zapíše i přes kontrolu výměny, jako Ctrl+Alt+Enter — bez dotazu na poznámku / s ním |
| `{SPACE}` | mezerník v poli volačky (přechod na výměnu) |
| `{COMMENT text}` | přidá text do poznámky rozpracovaného QSO, nebo posledního zapsaného QSO, když je pole volačky prázdné |

Znaky, které klíčovač neumí poslat (například `:` v `{TIMEGMT}`), se vynechají.

### Akce po zprávě, makra rigu a stanice

| Makro | Akce |
|---|---|
| `{END}` | konec textu: co následuje, se nikdy nepošle; makra za ním se provedou, jakmile je zpráva odeslaná (`TU {END}{FREQUP}` posune nahoru po „TU“). Esc nebo novější zpráva je zruší |
| `{PGUP}` / `{PGDN}` | rig dolů / nahoru o krok „Nastavení → Other → QSY makry {PGUP}/{PGDN}“ (výchozí 1 kHz) |
| `{FREQUP}` / `{FREQDN}` | rig nahoru / dolů o stejný krok (QSY ve Sprintu, obvykle za `{END}`) |
| `{TURNROTOR}`, `{LONGPATH}`, `{STOPROTOR}` | rotátor na azimut volačky v poli volačky, na její dlouhou cestu, zastavit |
| `{DIGQTCR}`, `{DIGQTCS}`, `{QTC}` | WAE: okno QTC se otevře pro příjem / vysílání; `{QTC}` je záhlaví jeho série (`26/10`), viz [QTC](qtc.md) |
| `{TX}` | ve zprávě, která nic jiného neposílá: PTT aktivního rigu zapnuté přes CAT až do Esc (s 30s pojistkou ladění) |
| `{CAT1ASC cmd}` / `{CAT1HEX hex}` | surový CAT příkaz do rádia 1 (`CAT2…` rádio 2), přes příkaz `w` démona `rigctld`. Více příkazů se odděluje `\`; ASCII příkaz může obsahovat bajty jako `<FE>`; HEX jsou dvojice šestnáctkových číslic (mezery se ignorují) |
| `{CATA1ASC …}`, `{CATI1ASC …}` (a `2`, `HEX`) | totéž, jen když je rádio 1 aktivní / neaktivní |
| `{CATACTASC …}` / `{CATACTHEX …}` | totéž do aktivního rádia |
| `{CATDELAY n}` | pauza n × 50 ms (nejvýš 1 s) po CAT příkazech zprávy |
| `{ANTRX1TOGGLE}`…`{ANTRX4TOGGLE}` | anténní port n aktivního rigu (hamlib `Y n 0`); stejný port znovu přepne jeho RX anténu (`Y n 1`); nikdy během vysílání |
| `{AUXANTSEL nn}` | anténa s kódem nn z tabulky antén, jako by byla vybraná ručně ([antennas.md](antennas.md)); UDP RadioInfo ji nese jako `AuxAntSelected` |
| `{TELNET cmd}` | pošle příkaz do DX clusteru (okno Telnet) |
| `{SETWAVDIR text}` | hodnota `{WAVDIR}` v cestách hlasových zpráv (`{SETWAVDIR {OPERATOR}_2}`); ukazuje ji titulek hlavního okna. Změna operátora ji vynuluje |

CAT příkazy jsou specifické pro rig a posílají se tak, jak jsou napsané: ověřte je v manuálu svého rigu.

### Dvě rádia (SO2R / SO2V), audio a závody

| Makro | Akce |
|---|---|
| `{OTHERFREQ}` / `{OTHERFREQROUND}` | frekvence VFO / rádia druhého zadávacího okna v kHz (`7025R3` v CW) / zaokrouhlená na kHz (pro předání stanice); s jedním oknem TX frekvence splitu rigu |
| `{OTHERBAND}`, `{OTHERMHZ}`, `{OTHERFREQCUT}` | pásmo druhého rádia (`40`, `144`), jeho MHz (`7.0`, `7R0` v CW) a poslední tři číslice kHz jako cut čísla |
| `{JUMPRX}` / `{JUMPRXTX}` | druhé zadávací okno se stane aktivním (v této aplikaci má aktivní okno fokus příjmu i vysílání zároveň) |
| `{CONDJUMP}` | totéž, jen když není split |
| `{FKEY(r1%r2)}` | jiná zpráva pro každé rádio: část před `%` na rádiu 1 (VFO A), část za ním na rádiu 2 (VFO B); s jedním zadávacím oknem první část. Část, která je názvem klávesy, pošle zprávu té klávesy (`{FKEY(F1%F9)}`), cokoli jiného je text zprávy s vlastními makry (`{FKEY(CQ {MYCALL} UP%CQ {MYCALL} TEST)}`). Funguje ve zprávách CW, digi i hlasových |
| `{CTRLF1}`…`{CTRLF12}` | pošle danou F-klávesu druhého zadávacího okna na jeho rádiu (`TU {CTRLF1}` tady poděkuje a na druhém rádiu zavolá CQ). V SO2R se přesune jen fokus vysílání (fokus zápisu zůstane tady); v SO2V, s volačkou napsanou v tomto okně, se fokus vrátí, jakmile je zpráva odeslaná. Vypíná se Ctrl+Shift+L (Nastavení → SO2R → Makro {CTRLFx}) |
| `{STOPTX}` | uvolní PTT (`{TX}` nebo nosnou ladění) |
| `{STEREOON}` / `{STEREOOFF}` | stereo sluchátka SO2R zapnout / vypnout (OTRSP `RXnS` / `RXn`) |
| `{OTRSP cmd}` / `{OTRSPOTHER RX}` | příkaz do zařízení OTRSP, jak je napsaný (`{OTRSP AUX13}`); samotné `RX` je příkaz RX aktivního / neaktivního rádia |
| `{ACTIVEAUDIOTOGGLE}`, `{ACTIVEAUDIOON}`, `{ACTIVEAUDIOOFF}` | ztlumí / zruší ztlumení audia aktivního rigu přes CAT (hamlib `MUTE`; jen rigy, jejichž ovladač to má) |
| `{INACTIVEAUDIOTOGGLE}`, `{INACTIVEAUDIOON}`, `{INACTIVEAUDIOOFF}` | totéž pro neaktivní rig (SO2R) |
| `{POPPREVNEEDEDQ}` / `{POPNEXTNEEDEDQ}` | VKV více pásem: předchozí / další stanice deníku, která na tomto pásmu ještě nebyla pracována, přijde do zadávacího okna se svou výměnou (lokátor…; pořadové číslo a reporty se nekopírují) |
| `{SWAPCONTESTS}` | otevře závod otevřený před tímto (Soubor → Otevřít nedávné); napsaná volačka a výměna se přenesou |
| `{SWAPCONTESTS3}`…`{SWAPCONTESTS6}` | prochází dokola posledních 3–6 otevřených závodů |
| `{SWAPCONTESTS name}` | otevře nedávný závod, jehož název obsahuje dané jméno |
| `{MESSAGE}` | multi-user: zbytek zprávy se nepošle do éteru, ale jako zpráva chatu přes síťový deník; první slovo, které je názvem stanice, ji pošle jen této stanici, `-` všem (`{MESSAGE} OP2 need 20m mult {CALL}`). Mimo síť se zbytek zahodí |
| `{PASS name}` / `{PASS kHz}` | multi-user: frekvence pro předání (zaokrouhlená na kHz; frekvence stanice, když žádnou neohlásila) pojmenované stanice, nebo stanice na pásmu této frekvence (napřed run stanice, pak stanice s frekvencí pro předání); stane se naposledy předanou frekvencí |
| `{PASSMSG name}` / `{PASSMSG kHz}` | multi-user: předá naposledy zapsanou volačku této stanici (jako Ctrl+Alt+P) |
| `{LASTPASSEDFREQ}` | multi-user: frekvence stanice, které se naposledy předávalo (`{PASS …}`, Ctrl+Alt+P, Předat), R místo desetinné čárky (`14025R5`) |
Ostatní makra N1MM pro ovládání rozhraní (`{KEYBOARD}`...) se neposílají a stavový řádek je hlásí jako neznámá.

## CW z klávesnice

![Okno CW z klávesnice](../img/cw-keyboard.png)

Obdoba N1MM **CW keyboard** (Ctrl+K). **Ctrl+K** v zadávacím okně
(nebo „Okno → CW z klávesnice“) otevře okno, ve kterém se
napsaný text posílá klíčovačem:

- **Po slovech** — každé slovo se pošle, jakmile napíšete mezeru (výchozí),
- **Po Enteru** — celý řádek se pošle Enterem,
- Enter pošle zbytek, **Esc** zastaví vysílání a vymaže pole,
- platí makra F-kláves (`*` moje volačka, `!` volačka z pole, `#` číslo...).

## CW Reader (dekódování CW)

Okno **„Okno → CW Reader“** dekóduje CW z
audia přijímače (vstup nastavíte v „Nastavení → Audio → Příjem“, stejný,
jaký používá vodopád).

- Dekodér poslouchá na výšce tónu (výchozí = CW tón z nastavení,
  měnitelný v okně).
- Rychlost se průběžně odhaduje z délky teček a ukazuje se jako „~N WPM“.
- Práh se přizpůsobuje síle signálu a šumu; slabý signál pod šumem se nedekóduje.
- Volací značky nalezené v textu (nejnovější napřed, bez vaší vlastní) se ukazují nad
  textem jako tlačítka — klik vloží volačku do pole volačky.
- **Pozastavit posuv** (jako v N1MM): zobrazený text se přestane posouvat, abyste ho mohli přečíst nebo kliknout na
  volačku, zatímco dekódování běží na pozadí; **Pokračovat** ukáže vše, co se mezitím dekódovalo.

**CW Reader 2** (Okno → CW Reader 2 (rádio 2), druhý reader N1MM v SO2V / SO2R) dekóduje vlastní audio vstup
rádia 2, vybraný nahoře v okně (SO2R: např. druhý USB audio CODEC); jeho volačky jdou do zadávacího okna VFO B / rigu 2.

Dekodér je jednoduchý (Goertzelův filtr plus měření časování). Dobře funguje
na čistém jednotónovém signálu; v pileupu s více stanicemi na stejném tónu
se splete, jako každý takový dekodér.

## Simulátor pileupu (podobný Morse Runneru)

![Simulátor pileupu — trénink závodu bez rádia](../img/simulator.png)

**„Okno → Simulátor pileupu“** spustí trénink
bez rigu: CW z F-kláves (i z ESM a okna CW z klávesnice) jde
do simulátoru místo do klíčovače a z reproduktoru hraje vaše vlastní CW i volající
stanice (tón = CW tón, volající rozprostřeni kolem něj).

- Na **CQ / TU / QRZ** odpovídají volající (počet závisí na „Aktivita“);
  netrpěliví po několika CQ odejdou.
- Když pošlete **volačku** volajícího, odpoví „5NN číslo“; na
  **? / AGN / NR?** výměnu zopakuje.
- Na **část volačky s otazníkem** („OK1?“) odpovědí odpovídající stanice;
  na volačku **s jednou chybou** ji stanice opraví („DE OK1ABC OK1ABC“).
- Po zapsání se QSO porovná s tím, co stanice poslala: okno ukazuje
  počet QSO, chyb a u každého QSO, co bylo správně.
- Volačky se berou z master.scp (databáze); bez něj se vymýšlejí.

- **QSB (únik signálu)** — každý volající pomalu sílí a slábne (každá stanice s vlastní periodou, pokaždé
  stejnou, když volá); **QRM (rušící stanice)** — zatímco volající odpovídají, slabá stanice 150–450 Hz vedle volá
  CQ nebo dokončuje vlastní QSO. Obě zaškrtávátka jsou ve výchozím stavu vypnutá a lze je přepnout za běhu simulace;
  mění jen zvuk — volající, jejich rychlosti a pořadí zůstávají stejné.

QSO se zapisují do **aktivního závodu**, takže si pro trénink založte cvičný
závod. Simulace je jednodušší než Morse Runner: žádný flutter a výměna je vždy RST + pořadové
číslo.
