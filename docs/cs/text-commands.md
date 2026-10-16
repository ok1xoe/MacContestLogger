# Textové příkazy v poli volačky

Místo volačky napiš do pole **volačky** příkaz a potvrď ho klávesou **Enter**.
Příkaz se provede, pole se vymaže a výsledek se zobrazí ve stavovém řádku
hlavního okna. Na velikosti písmen nezáleží.

Sada příkazů vychází z N1MM Logger+
([Callsign Box Text Commands](https://n1mmwp.hamdocs.com/manual-windows/entry-window/))
a DXLogu ([Text commands](https://dxlog.net/docs/index.php?title=Keyboard_and_text_functions#Text_commands)).

## Frekvence (kHz)

| Zadání | Význam | Příklad (na 14 074 kHz) |
|---|---|---|
| celá frekvence | QSY na zadanou frekvenci, i na jiné pásmo | `14025.1` → 14 025,1 kHz · `7012` → 7 012 kHz |
| částečná frekvence | počítá se od dolního okraje aktuálního pásma | `025.1` → 14 025,1 kHz · `250` → 14 250 kHz |
| `0` | začátek aktuálního pásma | `0` → 14 000 kHz |
| `+n` / `-n` | posun o n kHz | `+2` → 14 076 kHz · `-0.5` → 14 073,5 kHz |

### Druhé VFO a split (vyžaduje transceiver připojený přes CAT)

| Zadání | Význam |
|---|---|
| `/14030`, `/025`, `/+2` | frekvence **druhého VFO (B)**. Split se nezapne a příjem na VFO A zůstává. Relativní zadání se počítá od VFO B, pokud je známé (split), jinak od VFO A |
| frekvence + **Ctrl+Enter** | **split**: zadaná frekvence je vysílací. `+2` + Ctrl+Enter znamená vysílat o 2 kHz výš, `14030` + Ctrl+Enter vysílat na 14 030 kHz |
| `SPLIT` | zapne split a frekvenci VFO B nechá, jak je |
| `NOSPLIT` / `SPLITOFF` | vypne split a vysílá se opět na VFO A |
| `SWAP` | prohodí VFO A ↔ B (DXLog) |

Když je split zapnutý, informační lišta ukazuje červeně **SPLIT TX 14030.0**. Stav se
čte z rigu, takže se zobrazí i split zapnutý přímo na rigu.

Desetinná čárka funguje stejně jako tečka (`14025,1`). Celá frekvence má přednost:
`1830` na 20 m znamená 1 830 kHz (160 m), ne 14 000 + 1 830. Zadání, které nevede na žádné
pásmo, se neprovede a hlavně se **nezaloguje jako volačka**. Stavový řádek
ukáže proč. S připojeným CAT se přeladí i rig.

## Mód

`CW`, `SSB`, `USB`, `LSB`, `AM`, `FM`, `RTTY`, `PSK` (`PSK31`, `PSK63`, `PSK125`, `PSK250`),
`FT8`, `FT4`, `JT65`, `DIGITAL` (`DIGI`)

Příkaz přepne mód pro logování QSO a s připojeným CAT i mód rigu.
Výchozí report se přepne na 599 nebo 59. `USB` a `LSB` se logují jako SSB a
postranní pásmo volí CAT podle zvyklosti podle frekvence (LSB pod 10 MHz).
V jednomódovém závodě je mód daný definicí, takže se příkaz neprovede.

## Ostatní

| Příkaz | Alias | Akce |
|---|---|---|
| `OPON` | `LOGIN` | přihlášení operátora; samotné `OPON` otevře dialog, `OPON OK1XOE` ho nastaví rovnou (jako Ctrl+O) |
| `WIPELOG` | `CLEARLOG` | smaže všechna QSO aktuálního deníku a vynuluje skóre. Nejdřív se zeptá. V clusteru se smazání projeví i na ostatních stanicích. |
| `VERSION` | `VER` | verze programu |
| `EXPORT` | | export deníku do ADIF (jako z menu) |
| `IMPORT` | | import QSO z ADIF/Cabrilla (jako z menu) |
| `WRITELOG` | `MAKELOG` | export deníku do Cabrilla (jako z menu) |
| `RESCORE` | | přepočítá skóre závodu od začátku (jako Nástroje → Přepočítat skóre) |
| `ESM` | `ESMON` | zapne ESM (Enter odesílá zprávy), viz [esm.md](esm.md) |
| `NOESM` | `ESMOFF` | vypne ho |
| `AUTORSP` | `AUTORSPON` | zapne automatické přepínání Run/S&P podle CQ frekvence, viz [run-sp.md](run-sp.md) |
| `NOAUTRSP` | `NOAUTORSP`, `AUTORSPOFF` | vypne ho (jako Alt+F11) |
| `SPLIT` | | zapne split (viz výše) |
| `NOSPLIT` | `SPLITOFF` | vypne split |
| `SWAP` | | prohodí VFO A ↔ B |
| `SETUP` | | otevře Nastavení |
| `TOUR 1200/30` | | etapa závodu, dupe jen v rámci etapy; `TOUR` bez argumentu vezme pole Snt, `NOTOUR` ji vypne — viz [qso-party.md](qso-party.md) |
| `ROVERQTH HAM` | | můj okres (rover); bez argumentu dialog |
| `COUNTYLINE DAD,JEF` | | hranice okresů: QSO se zaloguje pro každý okres; `NOCOUNTYLINE` to vypne |
| `BONUS W1AW,K1BON` | | bonusové stanice (QSO party); bez argumentu dialog |
| `SPOTME` | | spotne vlastní stanici do DX clusteru (DXLog; totéž dělá makro F-klávesy `{SPOTME}`); Alt+P / Spot It spotne volačku z pole |
| `NETON` | `NET` | zapne síťovou synchronizaci deníku (cluster musí být vyplněný v Nastavení) |
| `NETOFF` | `NONET` | vypne síťovou synchronizaci; stanice dál loguje lokálně |
| `OPOFF` | `LOGOUT` | odhlásí operátora, vrátí výchozího z údajů stanice (DXLog) |
| `AUTORSP` / `RUNSP` | `RUNSPON` | zapne automatické přepínání Run/S&P (DXLog) |
| `NOAUTRSP` / `NORUNSP` | `RUNSPOFF` | vypne ho |

### CW a opakování CQ

| Příkaz / klávesa | Alias | Akce |
|---|---|---|
| `RPT`, **Alt+R** | | opakování CQ: F1, doběhnutí, pauza, znovu. Psaní volačky ho pozastaví (po vymazání pole pokračuje), **Esc** nebo `NORPT` ho vypne |
| **Ctrl+R** | | pauza mezi CQ v sekundách (1.8; číslo nad 100 = milisekundy, jako v N1MM) |
| `FULLABBREV` | | zkrácená čísla T, A, U, E, D, N (DXLog) |
| `PROABBREV` | | zkrácená čísla T a N (097 → TN7) |
| `SEMIABBREV` | | zkrácená čísla: jen nuly jako T |
| `NOABBREV` | | zkrácená čísla vypnutá |
| `WORKDUPE` | `WORKDUPEON` | ESM: dupe v Run se udělá jako nové QSO |
| `NOWORKDUPE` | `WORKDUPEOFF` | ESM: dupe stanici se pošle QSO B4 |

Všech devět stylů zkrácených čísel z N1MM lze zvolit v Nastavení → CW klíč.

### Program (DXLog)

| Příkaz | Alias | Akce |
|---|---|---|
| `BYE` | `EXIT`, `QUIT` | ukončí program, nejdřív se zeptá |
| `EXITNOW` | `QUITNOW` | ukončí program okamžitě |
| `CLEARLOGNOW` | | smaže deník **bez potvrzení** |
| `NEW` | | nový závod |
| `OPEN` | | otevřít závod |
| `CLOSE` | | zavře závod (volné logování) |
| `COPYLOG` | | záloha databáze vedle ní, s časem v názvu (`log-20261128-120000.sqlite`) |
| `RELOAD` | `RELOADNOW` | znovu načte definice závodů a otevře závod |
| `REOPEN` | `REOPENNOW` | obnoví deník z databáze a přepočítá skóre |
| `BCLOG` | | jednou rozešle celý deník přes UDP broadcast |
| `RESET` | | znovu připojí transceiver (CAT) a CW klíč |
| `DEBUGCAT` | | okno komunikace CAT |
| `AUTORELOAD` | | při startu rovnou otevřít poslední závod |
| `NOAUTORELOAD` | | při startu zobrazit úvodní dialog |
| `MSGS` | `MESSAGES`, `AMSGS` | Nastavení → Function Keys |
| `WKEY` | `WKSETUP` | Nastavení → CW klíč |
| `NETCONFIG` | | Nastavení → Cluster |
| `BEACONS` | | načte soubor majáků (N1MM `Beacons.txt`) do bandmapy na dobu uvedenou v hlavičce souboru |

Formát souboru majáků (N1MM): řádky s `#` jsou komentáře, první následující řádek je
počet hodin, pak `callsign;frequency kHz;locator;comment`, např.
`OZ7IGY/B;144471,1;JO55WM;`.

## Volačka vs. příkaz

Klíčové slovo musí tvořit **celý** obsah pole (argument berou jen `OPON` a `LOGIN`).
`CW1A`, `NET1X` nebo `OPONX` jsou proto normální volačky a `WIPELOG NOW` se neprovede.
Čistě číselné zadání nemůže být volačka, takže se bere jako frekvence.

## Nepodporované příkazy

Tyto příkazy N1MM a DXLogu ovládají funkce, které MacContestLogger nemá (nebo které
na macOS nedávají smysl):

| Příkaz | Proč |
|---|---|
| `LIGHT` (N1MM) | aplikace nezná optické pásmo |
| `ALIGN` | ladění MMVARI (digitální dekodér) |
| `QQSL` | Intelligent Quick QSL |
| `CTSPACE` / `NOCTSPACE`, `SOUND` / `NOSOUND` | nastavení interního klíče DXLogu (Winkeyer si drží vlastní) |
| `CWAUTO` / `NOCWAUTO` | automatické vysílání při psaní volačky |
| `SYNCCW` / `SYNCSPEED` | SO2R / SO2V (jedno VFO pro logování) |
| `MULT`, `RUN`, `RUN1`, `RUN2`, `PASSFREQ`, `REMOTE`, `ILOCK…` | typ multi-op stanice, předávání, interlock |
| `POSTCONTEST` | režim úprav po závodě |
| `MORSERUNNER`, `SUPERSIM` | simulátory |
| `SENDLOG`, `COPYLOGCLEAR` | odesílání do databáze SCP; nejasná funkce i v DXLogu |
| `DEFINEKEYS`, `FOCUS` / `NOFOCUS` | přemapování kláves, přebírání fokusu |
| `CTYFILES` | soubor zemí se bere z `~/dxcc-json`, v Nastavení není |

## RIT

| Příkaz | Akce |
|---|---|
| `RIT 120`, `RIT -50` | RIT na offset v Hz |
| `NORIT`, `RITOFF`, `RITCLEAR`, `CLEARRIT` | RIT vypnout |

## Skripty

| Příkaz | Akce |
|---|---|
| `SCRIPT name` | provede řádky souboru `scripts/name.txt` jako textové příkazy — viz [scripting.md](scripting.md) |
