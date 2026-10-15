# Nastavení (Configurer)

![Nastavení — záložka Hardware](../img/settings.png)

Záložek je 19; skrývá se pod nimi téměř veškeré chování loggeru. Dvě
z nich navštívíte nejčastěji:

![Function Keys: ESM, Run/S&P a zprávy F-kláves](../img/settings-function-keys.png)

![Klávesy: přemapování zkratek vstupního okna](../img/settings-keys.png)

Všechny záložky Nastavení jsou funkční (dřívější makety rozvržení N1MM byly nahrazeny):

| Záložka | Obsah |
|---|---|
| Hardware | rádio (hamlib), SO1V / SO2V / SO2R, rádio 2 a OTRSP, nožní spínač, transvertory |
| Function Keys | zprávy CW, hlasové a digitální F1–F12, ESM, [call stacking](call-stacking.md) |
| Klávesy | přemapování zkratek |
| Digital Modes | jak zapisovat datový druh provozu rádia (PKTUSB → FT8 / RTTY / DIGITAL...) |
| Other | krok rychlosti CW a druhý krok (Shift+PgUp/PgDn), krok ladění a RIT (CW / fone), krok QSY maker `{PGUP}`/`{PGDN}`/`{FREQUP}`/`{FREQDN}`, samostatné soubory funkčních kláves pro každého operátora, nulování RIT po QSO, návrat RX na kmitočet TX po QSO v Run se splitem, pípnutí u duplikátu |
| CW klíč | klíčování Winkeyerem / přes CAT; *Zobrazovat odesílané CW ve stavovém řádku* (N1MM *Display Sent CW*); váha CW a závodní mezery mezi slovy; klíčování DTR/RTS s linkou PTT, zpoždění PTT a PTT přes CAT; příposlech CW ze zvukové karty; nastavení Winkeyeru (záložka Winkey v N1MM, viz [CW klíčovač](cw-keyer.md#winkeyer-settings)) |
| Mode Control | druh provozu v deníku převzatý z rádia / podle bandplánu / vždy pevný; RTTY do rádia jako FSK nebo AFSK |
| Antennas | tabulka antén, rotátor (rotctld, UDP) |
| Score Reporting | online výsledková tabule, Club Log Live Stream, DXCC z Club Logu ([Data DXCC](dxcc-data.md)) |
| Broadcast Data, WSJT/JTDX, Audio, Stanice, Závod, Cluster, DX Cluster, Online callbooks, Bandplán, Digi frekvence, Mapa | beze změny |

## OK, Použít a Zrušit

Dole jsou tlačítka **OK**, **Použít** a **Zrušit**.
OK vše uloží a okno zavře. **Použít** (také ⌘S) provede přesně totéž
uložení a použije tytéž změny (nové připojení, jazyk, klávesy, ...), ale nechá
okno otevřené na stejné záložce, takže můžete pokračovat v úpravách; dokud se nic nezměnilo,
je zašedlé. Zrušit pak okno zavře, aniž by vrátilo, co už bylo
použito. Pokud se uložení nepodaří, okno zůstane otevřené s vašimi úpravami a zobrazí se chyba,
u OK i u Použít.

## Jazyk rozhraní

Texty v aplikaci jsou česky a překládají se pomocí souborů v adresáři
**`language`** v datech aplikace (macOS
`~/Library/Application Support/MacContestLogger/`). Seznam jazyků **není
zapsán v aplikaci** — je to obsah toho adresáře, takže překlad může přidat kdokoli
zkopírováním souboru.

**Konvence: `lang_<kód>.json`** (`lang_de.json`, `lang_pl.json`, `lang_pt_BR.json`).

```json
{
  "_name": "Deutsch",
  "Skóre": "Punkte",
  "Mapa": "Karte"
}
```

- **klíč** je český text přesně tak, jak se objevuje v aplikaci; **hodnota** je překlad;
- **`_name`** (volitelné) je název jazyka pro menu — bez něj se zobrazí kód velkými písmeny;
- **co chybí, zůstane česky**, takže můžete překládat po částech a neúplný soubor nic nerozbije;
- **vadný soubor** aplikaci neshodí: jazyk v menu zůstane, jen se nepřeloží.

**Nastavení → Other → Jazyk / Language** nabízí
seznam nalezených jazyků, **Načíst znovu** (po zkopírování souboru) a
**Otevřít adresář**. Jazyk se přepne hned po OK,
bez restartu.

Aplikace obsahuje **angličtinu** (`lang_en.json`) a **němčinu**
(`lang_de.json`); oba soubory se při prvním spuštění rozbalí do adresáře a
slouží i jako šablony. Existující soubor se nikdy nepřepíše, takže vaše vlastní úpravy
zůstanou zachovány.

Nový překlad začněte ze souboru `lang_en.json` v adresáři `language` jako
šablony — obsahuje všechny klíče. Zkopírujte ho do `lang_<kód>.json` a nahraďte
hodnoty svým překladem; co ještě přeloženo není, zůstane viditelné jako
originál. Klíče nepište ručně — ručně psaný seznam se od kódu rozejde,
jakmile se nějaký text přejmenuje.

Některé zprávy obsahují **`%s`** jako zástupný symbol pro hodnotu doplněnou za běhu
(`"Opraveno %s z %s QSO"`). Překlad musí zachovat stejný počet
zástupných symbolů; jejich pořadí lze změnit.

## Volby rádia (Hardware → Set)

Skupina **Volby rádia** v listu rádia obsahuje volby N1MM pro jednotlivá rádia:

- **Icom CI-V adresa (hex)** — zobrazí se u modelu Icom. Adresu zadejte jako v N1MM, bez
  `H` (`94`, `94H` i `0x94` jsou přijaty). Předá se `rigctld`, který spouští aplikace
  (`--set-conf civaddr=0x94`); prázdné = výchozí hodnota hamlibu. Sdílený `rigctld`, který spouštíte sami, potřebuje
  `-C civaddr=0x94` na svém vlastním příkazovém řádku.
- **Dotazování rádia** — Normální (každých 500 ms), O 50 % pomalejší (750 ms) nebo O 100 % pomalejší
  (1 s) pro rádio, které má s častým dotazováním potíže.
- **Timeout TRX** (výchozí 15 s) — když se spojení s rádiem ztratí (nezavřeli jste ho
  vy) a do této doby se neobnoví, bandmapa ukáže červený pruh **Problém s rádiem**
  s tlačítkem **Reset Radio**, které rádio připojí znovu (× pruh skryje). 0 = žádné upozornění.
- **Reverzní CW (CW-R)** — kdykoli aplikace přepne rádio do CW, pošle místo toho CW-R
  (`M CWR`). Rádio 2 má vlastní políčko ve skupině SO2R na záložce Hardware. Ctrl+Alt+R dál přepíná CW / CW-R
  ručně.
- **Ztlumit mikrofon rádia během hlasových zpráv** — ve výchozím stavu vypnuto. Zatímco
  hlasová zpráva z počítače klíčuje rádio přes CAT, zisk mikrofonu rádia se přečte, nastaví na 0 a obnoví
  po uvolnění PTT (hamlib `MICGAIN`; např. Elecraft K3, Ten-Tec Orion). Používejte jen tehdy, když zvuk zprávy
  vstupuje do rádia linkovým / datovým vstupem, ne mikrofonním. Rádia bez `MICGAIN` se volba
  netýká.
- **Vedlejší přijímač stále zapnutý** — zapne dual watch hamlibu (`DUAL_WATCH`)
  při každém připojení rádia (K3 s vedlejším přijímačem, řada FT-1000, rodina IC-756…). Rádio bez této funkce
  příkaz ignoruje. S touto volbou **Alt+F12** přepíná vedlejší přijímač (přepínač Dual Receive v N1MM); bez
  ní Alt+F12 zkopíruje kmitočet A → B.

Sériový port (rádio, Winkeyer, nožní spínač, OTRSP), který byl nastaven, ale teď ho nelze najít (odpojený
USB adaptér), se zobrazí s hvězdičkou, `* /dev/cu.usbserial-…`, a pod jeho rozbalovací nabídkou je řádek s varováním.

## Mode Control

- **Podle módu rigu** — výchozí.
- **Podle bandplánu** — CW v CW segmentu, SSB ve fone segmentu, v digitálním
  segmentu konkrétní digitální druh provozu z rádia (FT8...), jinak DIGITAL. Hodí se,
  když rádio hlásí USB i při digitálním provozu.
- **Vždy** — pevný druh provozu (např. RTTY při provozu přes externí program).
- **RTTY do rádia**: FSK (RTTY režim rádia) nebo AFSK (datový režim PKTLSB).
- **Ostatní digitální druhy provozu do rádia** (PSK, FT8…; N1MM „Mode sent to radio“): PKTUSB (datový režim rádia,
  výchozí), PKTLSB, USB nebo LSB — USB/LSB pro rádio bez datového režimu; zapisovaný druh provozu se pak řídí pravidlem
  výše.

Jednodruhovému závodu určuje druh provozu definice; pravidla platí pro volné
logování a vícedruhové závody.

## Okna a jejich obnovení

Každé nástrojové okno si pamatuje svou **polohu a velikost** (`windowGeometry` v
`config.json`) a otevřená okna se po restartu znovu otevřou (`openWindows`): deník,
CAT log, dostupné násobiče, DX cluster, bandmapa, blacklist, HamQTH log, Info,
skedy, skóre, přesun násobičů, dupesheet (VFO A i VFO B), rotátor, statistiky, předpověď
šíření, poznámky k pásmům, vodopád, editor definic, QTC, mapa (i v režimu DXCC)
a okna násobičů (DXCC, zóny, okresy...). Druhé vstupní okno SO2V/SO2R
se otevře automaticky podle režimu v Nastavení → Hardware. Dialogy
(Nový závod, operátor...) se neobnovují.

### Rozložení oken a ztracená okna

Obdoba Tools → Save / Restore Window Positions v N1MM:

- **Nástroje → Uložit rozložení oken…** uloží otevřená okna a jejich místa
  pod jménem — nabídne se značka operátora, takže každý operátor může mít své rozložení
  (`layouts/<name>.json` v datovém adresáři).
- **Nástroje → Obnovit rozložení oken…** přesune otevřená okna na uložená místa a
  otevře okna rozložení, která jsou zavřená (žádné okno se nezavře).
- **Okno → Přesunout ztracená okna na hlavní obrazovku** přenese
  každé okno, které je mimo všechny připojené displeje (odpojený monitor), do levého horního rohu hlavního
  displeje — obdoba obnovení přes Ctrl+Shift+klik v N1MM.
- Přepínání mezi okny pomocí Ctrl+Tab z N1MM je v macOS **Cmd+`** (a Cmd+Shift+`); Ctrl+Tab ve vstupním
  okně si zachovává význam z N1MM.

### Přichytávání oken a převzetí fokusu

Dva přepínače v menu **Nastavení**, oba ve výchozím stavu vypnuté a pamatované mezi spuštěními:

- **Přichytávat okna k okrajům** (N1MM „Snap windows to edges“): okno, které přetáhnete a pustíte do 12 bodů od
  okraje obrazovky (kromě lišty menu a Docku) nebo od jiného okna MacContestLogger, se k němu přichytí — vedle
  sebe nebo zarovnané s okrajem druhého okna. K přichycení dojde při uvolnění myši; okna, která aplikace přesouvá
  sama (obnovení rozložení), zůstanou beze změny. Písma titulkových pruhů z N1MM nemají v macOS obdobu.
- **Převzít fokus od jiných aplikací při ladění rádia** (N1MM „Grab Focus From Other Apps When Radio Is Tuned“):
  když otočíte knoflíkem rádia, které aplikace ovládá, a vpředu je jiná aplikace, MacContestLogger se přesune
  dopředu se vstupním oknem toho rádia (v SO2R pro rádio 2 okno rádia 2). Změna kmitočtu, kterou aplikace
  provedla sama (QSY, spot, šipky, prohození VFO), to nikdy neudělá a nic se nestane, když je otevřený dialog nebo list,
  nebo když aplikace fokus už má. macOS může přepnutí aplikací v některých případech přesto odmítnout.

## Vzhled

**Nastavení → Other → Vzhled**:

- režim **podle systému** (výchozí), **světlý** nebo **tmavý** — platí pro všechna okna,
- **barevný akcent**: tyrkysová (výchozí), modrá, oranžová nebo **vysoký kontrast**
  (černé pozadí, bílý text, žlutý akcent — pro noční provoz),
- každé okno má vlastní velikost písma (A− / A+ vpravo nahoře) a okno si ji pamatuje.

### Skiny, barvy a písma

Obdoba záložek **Colors**, **Fonts** a **Skins** v Configureru N1MM, rovněž v **Nastavení → Other**:

- **Skiny** — skin je režim vzhledu, akcent, barvy a písma najednou. Vyberte
  vestavěný (Výchozí, Klasický N1MM, Noční provoz, Vysoký kontrast), **Načíst skin…** ze
  souboru `.mclskin` nebo **Uložit skin…** a sdílejte svůj vzhled s jiným Macem. Skin se stává součástí
  nastavení; OK ho uloží.
- **Barvy** — výběr barvy pro každou položku: barvy značky ve vstupním okně (nové QSO, násobič, dvojitý
  násobič), duplikát/chyba, informace o násobiči, pozadí QuickEditu, **pozadí pole s
  kurzorem** (barva fokusu v N1MM, ve výchozím stavu vypnutá), kontrolka připojeného rádia, barvy spotů v bandmapě
  a v okně Dostupné (nové QSO, jeden násobič, dva a více, duplikát), pruhy bandplánu a poznámky k pásmům. Změněná barva
  nahradí vestavěnou ve světlém i tmavém vzhledu; šipka vedle ní nebo **Všechny barvy výchozí**
  vrátí výchozí (která se řídí vzhledem).
- **Písma** — rodina proporcionálních textů a textů s pevnou šířkou (tabulky a vstupní
  pole). Velikosti zůstávají pro každé okno zvlášť. Prázdné = systémové písmo.
- **Bublinová nápověda u spotů** — bublinovou nápovědu spotu v bandmapě a v oknech násobičů
  (spotter, stáří, komentář...) lze vypnout. Styl „balloon“ z N1MM je vzhled Windows; macOS má jediný
  styl bublinové nápovědy. VoiceOver čte podrobnosti spotu v obou případech.

## Profily nastavení

Obdoba více konfigurací v N1MM / profilů v DXLogu. **Nastavení →
Profily nastavení…**:

- **Uložit aktuální** — celá konfigurace (stanice, rádio, klávesy, zprávy F-kláves, cluster,
  vzhled...) pod jménem, např. „Doma“, „Expedice“, „Multi-op“ (`profiles/<name>.json`
  v datovém adresáři),
- **Načíst** — přepíše aktuální nastavení profilem a okamžitě použije klávesy, druhy provozu,
  režim rádia a definice závodů; spojení s rádiem a sítěmi je potřeba navázat znovu (nebo
  aplikaci restartovat),
- **Smazat** profil.

Deníky a databáze se profilem nemění.

### Zálohy nastavení a obnovení výchozích hodnot

- Jednou denně se při startu `config.json` zkopíruje do `config-backups/config-<date>.json`; uchovává se posledních **7**
  (obdoba denních záloh INI v N1MM).
- Okno Profily nastavení je ukazuje; **Obnovit** převezme nastavení ze zálohy.
- **Výchozí nastavení…** (N1MM „Clear INI file settings“) vrátí každé nastavení na výchozí hodnotu.
  Údaje stanice zůstanou.
- Obojí se nejdřív zeptá a před jakoukoli změnou zálohuje aktuální nastavení. Databáze, složka s daty
  závodů, otevřená okna a jejich místa zůstanou. Rádio a sítě pak připojte znovu (jako po
  načtení profilu).

### Datová složka (N1MM UserDir)

**Nastavení → Other → Datová složka** ukazuje, kde aplikace uchovává svá data. **Spustit s jinou datovou složkou…**
aplikaci ukončí a spustí ji znovu nad zvolenou složkou (přes
`MCL_DATA_DIR`): s vlastním nastavením, profily, zálohami a ve výchozím stavu i databázemi — pro jiného uživatele, klubovou
stanici nebo testovací sestavu. **Spustit s výchozí datovou složkou** vrátí výchozí složku. `config.json` obsahuje
absolutní cesty, takže datovou složku nekopírujte; založte novou (začne jako při prvním spuštění) nebo nastavení
přeneste profilem.

### Stanice podle databáze

**Nastavení → Stanice → Údaje stanice podle databáze** — jako v N1MM si každá databáze
pamatuje svou stanici: přepnutí databáze uloží stanici vedle opouštěné databáze (`<name>.station.json`)
a převezme vlastní stanici otevřené databáze. Databáze bez ní převezme aktuální stanici. Ve výchozím stavu vypnuto.

## Jazyk

**Nastavení → Other → Jazyk / Language**: čeština (výchozí) nebo angličtina, plus jakýkoli další
jazykový soubor nalezený v adresáři `language` (viz výše). V angličtině jsou přeložena menu,
titulky oken, záložky Nastavení, záhlaví tabulky deníku a hlavní popisky vstupního
okna a pruhu skóre; zprávy stavového řádku a dokumentace
zůstávají česky. Klíčem je český text a chybějící překlad se zobrazí
česky; test kontroluje, že je přeložené celé menu.

## Synchronizace času

Obdoba **Sync time** v DXLogu / synchronizace času v N1MM. **Nastavení → Other →
Synchronizace času**:

- **NTP server** (výchozí `pool.ntp.org`, prázdné = vypnuto) — při startu, po uložení
  nastavení a každou půlhodinu se změří odchylka hodin počítače (SNTP),
- odchylka nad 1 s: varování ve stavovém řádku a ve zprávách a `HODINY +2.3 s`
  ve vstupním okně,
- **Opravovat čas nově zapsaných QSO** — čas QSO se posune o
  změřenou odchylku (systémové hodiny se nemění; to vyžaduje práva
  správce — doporučuje se zapnout automatický čas v Nastavení systému). Ručně
  zadaný čas (dodatečné zadání) se nemění.

## Call history (záložka Závod)

**Závod → Call history** obsahuje hlavní soubor call history, další soubory sloučené
za ním (**Přidat soubory…** / **Odebrat**), vlastní soubor otevřeného závodu (**Přiřadit závodu…**, použije se hned), celkový počet
načtených značek a tři přepínače: **Zapnout dohledávání v call history** (také zaškrtávací
položka v menu Nastavení), **Zobrazovat informace uživatele (UserText)** a **Při změně
volačky smazat výměnu doplněnou z call history nebo spotu** (N1MM *Clear auto-populated exchange on callsign change*).
Podrobnosti: [Call history](call-history.md).

## Lišta menu

Menu odpovídají N1MM+: **Soubor**, **Úpravy**, **Závod**, **Nástroje**,
**Nastavení**, **Okno** a **Nápověda**. Menu aplikace obsahuje O aplikaci,
Nastavení `Cmd+,` a Ukončit.

| Menu | Položky |
|---|---|
| Soubor | Nový závod, Otevřít závod, Otevřít nedávné (posledních 9 závodů otevřené databáze), Nová / Otevřít databázi, Zkopírovat závod do jiné databáze, Import (QSO, Sloučit deník, Importovat call history), Export (ADIF, ADIF podle data, Cabrillo, EDI, CSV / text / souhrn, call history), Odeslat výsledek na 3830, Tisk deníku |
| Úpravy | akce vstupního okna s vašimi aktuálními klávesami vedle nich (vymazat, vrátit, +1 k číslu, poznámka, najít, smazat poslední QSO), pak Zpět, Znovu, Vyjmout, Kopírovat, Vložit a Vybrat vše pro textová pole |
| Zobrazení | Zobrazovat ? u neznámých volaček, Hledat volačku na QRZ.com, Hledat volačku na Google (značka napsaná v aktivním vstupním okně, otevře se v prohlížeči) |
| Závod | Dodatečné zadání, Nahrávat závod, Žádný (volné logování) |
| Nástroje | Přepočítat skóre, Přepočítat posledních N hodin, Přepočítat DXCC v deníku, Přiřadit volačku k zemi, Stáhnout master.scp, Aktualizovat definice, Aktualizovat DXCC z Club Logu, Importovat / Odstranit seznam zemí ([Data DXCC](dxcc-data.md#import-a-country-list-from-a-file)), Aktualizovat call history, Vymazat call history, Načíst soubor majáků, Editor definic, Logování běhu programu, Otevřít složku diagnostiky, Zkontrolovat novou verzi programu, Kontrolovat novou verzi při spuštění, Stáhnout nejnovější PDF manuál (viz níže) |
| Nastavení | Nastavení (všechny záložky), Klávesy, Profily nastavení, Zapnout dohledávání v call history (zaškrtávací položka, viz [Call history](call-history.md#enabling-the-lookup)), Zkratky výměny, Hlášení pro nevidomé (VoiceOver, viz [Vstupní okno](entry-window.md#announcements-for-blind-operators-voiceover)), Práh AutoSend, Převzít fokus při ladění rádia, Přichytávat okna k okrajům ([výše](#přichytávání-oken-a-převzetí-fokusu)), SO2R |
| Okno | okna aplikace, Multiplikátory a za oddělovačem **Vlastní** s okny okenních pluginů ([Okna pluginů](plugin-windows.md)) |
| Nápověda | Dokumentace (`Alt+H`), Klávesové zkratky, Textové příkazy, Pravidla závodu (`officialUrl` definice otevřeného závodu), Kalendář závodů (WA7BNM), Nahlásit chybu (GitHub issues), Zobrazit chybový log, Otevřít datovou složku (respektuje `MCL_DATA_DIR`), Zkontrolovat aktualizace, Stáhnout nejnovější PDF manuál, Stáhnout nejnovější HTML manuál |

Klávesy v menu Úpravy a Nápověda se jen zobrazují: reaguje na ně dál vlastní obsluha kláves vstupního okna
(Nastavení → Klávesy), takže přemapovaná klávesa se zobrazí jako přemapovaná.

Vlastní `menu.json` (viz níže) nahradí vestavěné menu jako celek. Pokud jste si ho vytvořili před tímto
uspořádáním, zachová vaši starou strukturu; novou získáte, když starý soubor odsunete a vytvoříte čerstvou kopii
tlačítkem **Vytvořit menu.json k úpravám**. Uzel, jehož `id` začíná na `sep.`, je oddělovací čára.

### Verze programu, chybový log a diagnostika

- **Nástroje → Zkontrolovat novou verzi programu…** (také **Nápověda → Zkontrolovat aktualizace…**) se zeptá
  GitHubu na poslední zveřejněné vydání MacContestLoggeru a porovná ho s běžící verzí. Novější
  vydání nabídne v dialogu, jehož tlačítko **Otevřít stránku vydání** otevře jeho stránku v prohlížeči; aplikace nic
  nestahuje ani neinstaluje. Dotaz proběhne jen tehdy, když položku zvolíte, nebo — když
  zaškrtnete **Kontrolovat novou verzi při spuštění** ve stejném menu (ve výchozím stavu vypnuto) — jednou při každém startu; pak se
  dialog objeví jen tehdy, když novější verze existuje. S `MCL_INERT_NETWORK` se dotaz nikdy neprovede.
- **Nápověda → Zobrazit chybový log** otevře `<data folder>/diagnostics/errors.log`: uchovává se v něm s časem každá zpráva programu
  z okna Info (nepovedená stahování a nahrávání, varování Cabrilla, aktualizace definic…).
- **Nástroje → Logování běhu programu (diagnostika)** (zaškrtávací položka, při každém startu vypnutá; `MCL_DIAGNOSTICS=1` ji zapne
  už od startu) zapisuje `<data folder>/diagnostics/program.log`: zprávy, každý stavový řádek a každou
  akci menu. Přiložte ho k hlášení chyby. **Otevřít složku diagnostiky** ukáže složku ve Finderu. Oba logy se
  rotují při 1 MB (předchozí část zůstane jako `….log.1`).
- **Nápověda → Stáhnout nejnovější PDF manuál…** (také v **Nástroje**, Download latest PDF manual v N1MM) uloží
  tuto uživatelskou příručku jako jedno PDF (obsah s čísly stran, záložky pro každou kapitolu a oddíl, funkční
  odkazy) ke čtení offline. Nejdřív se zeptá, kam soubor uložit, a pak stáhne
  `MacContestLogger-manual.pdf` přiložený k poslednímu zveřejněnému vydání na GitHubu. Používá se jen tato adresa
  (přesměrování se následují jen na vlastní stahovací servery GitHubu), soubor musí být PDF a nejvýš 64 MB, jinak se nic
  nezapíše. Když vydání manuál ještě nemá nebo stahování selže, dialog řekne proč a nabídne
  **Otevřít dokumentaci online** (tyto stránky v prohlížeči). Dotaz proběhne jen tehdy, když položku zvolíte;
  s `MCL_INERT_NETWORK` nikdy.
- **Nápověda → Stáhnout nejnovější HTML manuál…** uloží tutéž příručku jako jeden samostatný soubor HTML
  (`MacContestLogger-manual.html` z posledního vydání, se stejnými pravidly; soubor musí být dokument HTML).
  Všechny obrázky jsou vložené, takže se otevře offline v jakémkoli prohlížeči. Vlastní PDF vytvoříte tak, že ho otevřete v Safari a zvolíte
  **File → Export as PDF…**, nebo ho vytisknete z Chromu (**Save as PDF**; vypněte prohlížečem přidávané *Headers and
  footers* a nechte zapnuté *Background graphics*). Tiskne se na A4 s bílým pozadím; Chrome navíc přidá průběžné
  záhlaví s kapitolou a čísly stran.

## Menu aplikace

Menu v horní liště (a seznam záložek Nastavení) popisuje `menu.json`.
Aplikace ho hledá **v datovém adresáři**:

```
~/Library/Application Support/MacContestLogger/menu.json
```

Dokud tam soubor není, použije se vestavěná definice z aplikace —
tu upravit nelze, protože je zabalená uvnitř bundle. Vlastní
kopii vytvoříte v **Nastavení → Other → Menu aplikace**
tlačítkem **Vytvořit menu.json k úpravám**; tlačítko
existující soubor nepřepíše. **Otevřít adresář** ho ukáže
ve Finderu, **Načíst menu znovu** použije vaše úpravy v běžící
aplikaci (bez restartu).

Každý uzel má `id` (nemění se — identifikuje akci), volitelný
`label` (libovolný popisek) a `state`:

| `state` | Co dělá |
|---|---|
| `enable` | položka je viditelná a funguje (výchozí) |
| `disable` | položka je viditelná, ale zašedlá |
| `hidden` | položka se vůbec nezobrazí |

Neznámá hodnota se bere jako `enable`, takže překlep (`hide` místo `hidden`)
se projeví tím, že položka zůstane viditelná.

Vadný soubor aplikaci o menu nepřipraví: při startu se zobrazí dialog
s důvodem (včetně řádku a sloupce v JSON) a běží
vestavěné menu. Smazáním souboru se vrátíte k vestavěné definici.
