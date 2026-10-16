# Multi-op a síť

Síťový deník (MQTT broker plus autorita, samostatná aplikace v Javě
(cluster-app, Java 21), která není součástí tohoto repozitáře) sdílí mezi stanicemi
kromě QSO i provozní informace.

Každá stanice najde broker sítě v **Nastavení → Cluster**: zadáním jeho adresy, tlačítkem **Najít broker v
LAN (Bonjour)** v místní síti, nebo tlačítkem **Najít cluster přes Tailscale**, když jsou stanice propojené
přes Tailscale. Obě hledání proběhnou jen po stisku tlačítka
([Průvodce síťovým deníkem](network-logbook-guide.md), oddíl 5). MacContestLogger samotné ostatní
stanice nehledá: všechny se potkávají u brokeru.

## Stav sítě

![Stav sítě: stanice, jejich pásma a spojení](../img/network-status.png)

**Okno → Stav sítě** ukazuje všechny stanice síťového deníku:
ID stanice, operátora, typ stanice (RUN, RUN1, RUN2, MULT), pásmo, mód, frekvenci, Run/S&P,
pass frekvenci (Alt+Z), počet QSO, rate posledních 10 a posledních 100 QSO, poslední QSO
(značku a čas UTC) a stav. Rate a poslední QSO se počítají ze sdíleného deníku
(každé QSO nese ID stanice, která ho zapsala).

**Sloupce** v horní části okna zobrazí nebo skryjí sloupce, posunou je doleva nebo doprava
(*Pořadí sloupců*) a vrátí výchozí sadu (N1MM: pravý klik na
záhlaví). Volba se ukládá.

Sloupec stavu uvádí:

- **online**: stanice se hlásí (heartbeat každých 30 s, při změně okamžitě),
- **vysílá**: stanice právě vysílá (zobrazeno červeně),
- **neaktivní N s**: žádný heartbeat déle než 90 s,
- **offline**: stanice se odpojila nebo ztratila spojení (MQTT Last Will).

Stav je na brokeru uchován (retained, `station/status/<stationId>`), takže nově připojená
stanice vidí ostatní okamžitě. ACL brokeru dovoluje stanici zapisovat jen vlastní stav
(viz `docs/cluster-aclfile`).

### Záložka Zprávy

**Zprávy** (záložka Messages v N1MM) vypisuje každou síťovou zprávu, kterou tato stanice odeslala (→) nebo
přijala (←), s časem UTC, stanicí, typem a obsahem — stopa pro hledání problémů
v síti; **Vymazat** ji vyprázdní.

Po připojení pošle každá stanice ostatním své **nastavení**: verzi programu, otevřený
závod a kategorii operátorů/vysílačů z nastavení závodu (a znovu při každé
změně). Když se jiná stanice online liší, ukáže záložka Zprávy červené varování (a
popisek záložky ⚠) a stavový řádek oznámí každý nový rozdíl jednou (varování N1MM
o nesouladu konfigurace). Každý nový rozdíl — například multi-single na jednom počítači a multi-two
na jiném — se také zapíše do programových zpráv okna Info, obdoby Message Window v N1MM.

### Záložka Akce

**Akce** (záložka Actions v N1MM):

- **Volat o pomoc**: všechny stanice nebo jedna stanice uslyší výstražný zvuk a uvidí
  ve stavovém řádku „POMOC: stanice OP1 volá o pomoc“.
- **Pass frekvence**: totéž co Alt+Z (viz níže).
- **Resetovat pořadová čísla na všech stanicích**: každá
  stanice pokračuje za nejvyšším pořadovým číslem odeslaným v deníku (nikdy ne níž než její vlastní
  příští číslo).
- **Synchronizovat čas z master stanice**, viz
  níže.

### Master stanice a čas

N1MM udržuje hodiny všech počítačů v souladu podle **master** stanice. V MCL má
**Nastavení → Cluster**:

- **Master stanice**: tato stanice odpovídá na žádosti ostatních o čas svými
  hodinami (opravenými vlastní kontrolou NTP, když je zapnutá *korekce času QSO*).
- **Čas QSO podle hodin master stanice**: tato
  stanice se při objevení master stanice a pak každých 10 minut zeptá na její čas, změří
  rozdíl po vzoru NTP (polovina doby odezvy) a o něj opravuje čas nových QSO, stejně
  jako to dělá korekce NTP. Samotné hodiny počítače se nemění (to by vyžadovalo
  administrátorská práva); kontrola NTP dál měří, ale její odchylka se nepoužije, dokud se
  používá čas master stanice.

## Chat

![Chat mezi stanicemi](../img/chat.png)

**Okno → Chat** (N1MM Messaging, DXLog Gab): zprávy všem stanicím nebo jedné
(vybrané nad řádkem zprávy; nabízí stanice ze Stavu sítě). Enter odešle.
Příchozí zpráva se objeví i ve stavovém řádku. Zprávy jdou přes broker na
`station/msg` (QoS 1, neuchovávají se, takže stanice offline je nedostanou).

## Předávání stanic (pass)

Stanici, se kterou sami pracovat nemůžete (například násobič na jiném pásmu), předáte
stanici, která je na správném pásmu:

1. napište značku do pole značky,
2. stiskněte **Ctrl+Alt+P**. Je-li online právě jedna další stanice, značka jde rovnou
   k ní; jinak se otevře **Stav sítě** a u cílové stanice kliknete na **Předat**.

Příjemce dostane značku do své **bandmapy** na své vlastní frekvenci (spotter
`PASS-<station>`), do chatu a do stavového řádku; text obsahuje i frekvenci
předávající stanice.

**Pass frekvence (Alt+Z).** Stanice může oznámit, kde přebírá předané stanice: **Alt+Z**
se zeptá na frekvenci v kHz (nabídne aktuální; prázdné = zrušit) a pošle ji všem
stanicím. Značka předaná této stanici pak přistane v její bandmapě na pass frekvenci místo
její aktuální. Starší verze ukazují oznámení jen jako řádek v chatu.

## Partner a zásobník volaček

![Okno Partner se zásobníkem volaček](../img/partner.png)

**Okno → Partner** (DXLog Partner, N1MM call stacking) je pro druhého operátora, který
poslouchá pileup na stejném rigu nebo na druhém přijímači:

- vybere runnera (stanici online) a vidí jeho pásmo, mód, frekvenci a **co runner
  právě píše do pole značky**,
- napíše značku a Enterem ji pošle do **runnerova zásobníku**.

Runner vidí zásobník v zadávacím okně („ZÁSOBNÍK DL1ABC K1ZZ (Alt+G)“)
a **Alt+G** (nebo **Ctrl+Alt+K**) vloží další značku do pole. Partnerovy značky se přidají
k runnerovu vlastnímu [zásobníku volaček](call-stacking.md) — jeden zásobník nejvýš 10 značek bez
duplicit a bez dupe, v pořadí zvoleném v Nastavení → Function Keys → Zásobník volaček; s
klávesou další volačky je ESM odpracuje jednu po druhé (`{LOGTHENPOP}`).

Když runner zapíše značku, kterou mu partner dal do zásobníku, značka se smaže
z partnerových zadávacích oken (N1MM: wipe the callsign when it is logged by the stack target).

## Deník a export

Dokud se používá síťový deník, má okno Přehled spojení dva sloupce navíc: **Op** (operátor
QSO) a **Stn** (ID stanice, která ho zapsala; sloupce Op a R# v N1MM).

**Soubor → Export → ADIF podle data…** nabízí volbu **Stanice sítě**,
když deník obsahuje QSO více stanic: ADIF pak obsahuje jen QSO této
stanice (N1MM *Export ADIF by multi-user station name*).

## Makra pro více uživatelů

Zprávy funkčních kláves mohou používat makra N1MM pro více uživatelů `{MESSAGE}`, `{PASS …}`,
`{PASSMSG …}` a `{LASTPASSEDFREQ}` (viz [CW klíč → makra](cw-keyer.md)). Fungují jen
při připojeném síťovém deníku; text za `{MESSAGE}` se nikdy nevysílá.

## Interlock / blokování vysílání

**Nastavení → Cluster → TX interlock**:

- **Kdekoli (jeden signál)**: pro kategorie s jedním signálem najednou
  (M/S, M/2): když vysílá kterákoli jiná stanice, tato nevysílá,
- **Na stejném pásmu**: provoz na stejném pásmu (DXLog „Interlock and inband
  operation“): blokují se jen stanice na stejném pásmu.

Pod rozsahem zvolte, co se stane, když chtějí vysílat dvě stanice (softwarové blokování vysílání
v N1MM):

- **První vyhrává** (N1MM *Block my transmitter*, výchozí): dokud jiná
  stanice vysílá, tato nezačne;
- **Poslední vyhrává** (N1MM *Force other station to stop*): tato stanice smí začít,
  i když jiná vysílá, a když jiná stanice začne vysílat, zatímco tato
  vysílá, tato přestane (CW, hlas, digitální módy, ladění a PTT nožním spínačem; opakování CQ se
  vypne) s hlášením „TX LOCKOUT: vysílá STN2 — zastaveno“.

PTT **nožním spínačem** (Nastavení → akce nožního spínače PTT) prochází interlockem stejně jako
klíč a pro ostatní stanice se počítá jako vysílání.

Blokuje se CW (funkční klávesy, ESM, CW z klávesnice), hlasový klíč, digitální vysílání a
ladění nosnou; stavový řádek ukazuje „TX LOCKOUT: vysílá STN2“.
Začátek vysílání se ostatním oznámí okamžitě, konec
do 1 s. Interlock jde přes síť (broker), takže má zpoždění v řádu desítek
ms. Nenahrazuje hardwarový zámek (například přepínač s PTT interlockem), když dvě
stanice zmáčknou klíč ve stejném okamžiku.

## Server pořadových čísel

Když více stanic posílá pořadová čísla ze **společné řady** (M/S, M/2), mohly by dvě stanice
odeslat stejné číslo současně. **Nastavení → Cluster → Pořadová čísla ze serial
number serveru** to řeší stejně jako N1MM/DXLog:

- autorita vydává čísla z jedné řady: 1 + max(nejvyšší odeslané číslo v deníku,
  poslední vydané),
- stanice má číslo pro příští QSO **rezervované předem** (požadavek
  `serial/request`, odpověď `serial/reply/<stationId>`); po zapsání QSO si hned řekne o
  další,
- dokud rezervace nedorazí (autorita neběží, výpadek sítě), stanice
  počítá lokálně (local-first) a zadávací okno ukazuje „SNS: čekám na číslo“.

Vydané, ale nepoužité číslo (rezervace na konci závodu) zůstane v řadě jako mezera,
jako v N1MM. Po restartu autority řada pokračuje od nejvyššího
zapsaného čísla.

## Typ stanice (RUN / MULT) a pravidla změn pásma

**Nastavení → Cluster**:

- **Typ stanice** (DXLog Station type): *RUN* nebo *MULT*. Stanice MULT smí zapsat jen
  QSO, které přináší nový násobič. Ostatní vidí typ ve Stavu sítě.
  V Multi-two může mít stanice RUN číslo **Run1** nebo **Run2** (N1MM Run1/Run2); ostatní
  pak vidí *RUN1* / *RUN2*.
  **Ctrl+Alt+M** přepíná mezi RUN a MULT z klávesnice (N1MM Run/Mult). Okno Info ukazuje typ
  pod svými časovači (indikátor MULT/RUN v N1MM).
- **Pravidla provozu při zápisu**: *Nehlídat* /
  *Upozornit* (výchozí) / *Nezapsat*. Nástroj kontroluje pravidlo N minut na pásmu
  (například CQ WW M/S 10 min) a limit změn pásma za hodinu (například
  CQ WPX M/S 10/h) podle pravidel **zvolené kategorie** v definici
  závodu. S volbou *Nezapsat* projde zápis jen přes **Ctrl+Alt+Enter**.

Počítají se jen QSO **této stanice** (v síťovém deníku ne QSO
ostatních), takže stanice run a mult mají pravidlo každá zvlášť. Časovač doby na
pásmu a počítadlo změn zůstávají v okně Rate.
