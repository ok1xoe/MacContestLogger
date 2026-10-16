# Okna pluginů

**Okenní plugin** je program, který běží, dokud je otevřené některé z jeho oken, a zobrazuje vlastní obsah
v oknech MacContestLoggeru: tabulku QSO podle pásem, sledování cílů, seznam potřebných násobičů, cokoli, co lze
spočítat z deníku. S aplikací komunikuje přes svůj standardní vstup a výstup, jedna zpráva JSON na řádek, a
může se aplikace ptát na data jen pro čtení o deníku, závodě, rigu a spotech.

Událostní pluginy ze [Skriptů a pluginů](scripting.md) (`plugins/<event>/`) fungují beze změny dál; okenní pluginy
žijí vedle nich.

Tato stránka popisuje **protokol 1**. Pozdější verze přidají další (viz [Plán dalšího vývoje](#plán-dalšího-vývoje));
plugin napsaný pro protokol 1 bude fungovat dál.

## Rychlý start

1. Zkopírujte [`docs/plugins/examples/qso-by-band/`](../plugins/examples/qso-by-band/) do
   `~/Library/Application Support/MacContestLogger/plugins/qso-by-band/` a vedle jeho `run.py` dejte
   [`docs/plugins/mcl.py`](../plugins/mcl.py).
2. Udělejte `run.py` spustitelným (`chmod +x run.py`).
3. Zvolte **Okno → Vlastní → QSOs by band**.

Okno se otevře, plugin se spustí a jeho tabulka sleduje každé QSO, které zapíšete.

## Struktura

```
plugins/
  qso-by-band/            ← the plugin id (letters, digits, -, _ and .)
    plugin.json           ← the manifest
    run.py                ← the executable (any language; a script needs #! and chmod +x)
    mcl.py                ← the Python helper (optional)
  qso-logged/             ← an event plugin directory, see scripting.md
    append.sh
```

- Složka **s** `plugin.json` je okenní plugin. Složku bez něj okenní pluginy ignorují.
- 16 názvů událostí (`qso-logged`, `contest-opened`, …) je vyhrazeno pro událostní pluginy: `plugin.json` v takové
  složce se ohlásí v okně zpráv a ignoruje se.
- Složka pluginů se čte při spuštění aplikace a pokaždé, když se otevře menu Okno, takže nový plugin se objeví
  v **Okno → Vlastní** bez restartu.

## Manifest

```json
{
  "protocol": 1,
  "name": "QSOs by band",
  "version": "1.0",
  "permissions": ["read", "ui"],
  "events": ["qso-logged", "contest-opened"],
  "run": "run.py",
  "windows": [{ "id": "main", "title": "QSOs by band", "size": [420, 360] }]
}
```

| Pole | Význam |
|---|---|
| `protocol` | Povinné, `1`. Jiné číslo se odmítne se zprávou. |
| `name` | Zobrazovaný název (výchozí: název složky). |
| `version` | Volný text. |
| `permissions` | Co plugin smí dělat — viz [Oprávnění](#oprávnění). Oprávnění, které tato verze nezná (`cat`, `transmit`, …) → **plugin se nespustí** a okno zpráv oznámí, že potřebuje oprávnění, které tato verze nepodporuje. |
| `events` | Události, které plugin dostává (názvy složek z [tabulky událostí](scripting.md#pluginy)). Nic jiného se neposílá. |
| `run` | Spustitelný soubor, relativně ke složce pluginu (výchozí `run`; žádné `..`). Může to být symbolický odkaz, i na program jinde — složka pluginu je vaše, aplikace spustí, co do ní dáte. |
| `windows` | 1–8 oken: `id` (písmena, číslice, `-`, `_`, `.`), `title` (výchozí: `name`), `size` `[width, height]` pro první otevření (později si okno ponechá velikost, kterou mu dáte), `kind` (výchozí `declarative`, nebo `web` s `page`: soubor `.html` ve složce pluginu — viz [Webová okna](#webová-okna)). Lze vynechat, když má plugin `actions`. |
| `webHosts` | Názvy hostitelů, ze kterých smí webové okno načítat přes `https` (i jejich subdomény); výchozí žádné. |
| `process` | `false`: žádný spustitelný soubor — jen webová okna, která s aplikací komunikují sama (pak žádné `actions`). |
| `webInlineScripts` | `true`: webové stránky smějí spouštět inline skripty (nikdy, když manifest žádá `transmit` nebo `cat`). |
| `actions` | Až 32 klávesových akcí: `{"id","title"}`. Operátor jim přiřadí klávesy v Nastavení → Klávesy; plugin dostane zprávu `key`. Plugin s akcemi a bez oken se spustí při prvním stisku klávesy a běží do ukončení aplikace. |

Problémy v `plugin.json` (chybný JSON, chybějící pole, neznámá událost) se objeví v okně zpráv jako
`[<directory>] …`, každý jednou.

## Oprávnění

| Oprávnění | Uděluje | |
|---|---|---|
| `read` | požadavky na čtení (deník, závod, stav rigu, spoty) | vždy |
| `ui` | `set` pro okna pluginu | vždy |
| `entry` | `entry.*`: značka a výměna aktivního zadávacího okna, vymazání, zápis, stavový řádek | udělí operátor |
| `rig` | `rig.*`: QSY, mód, split, RIT, prohození VFO, aktivní rádio — **nikdy vysílání**, vždy přes zadávací okno jako vlastní akce operátora | udělí operátor |
| `spots` | `spots.add`, `spots.remove`, `spots.mark`, `spots.blacklist` (jen lokálně) | udělí operátor |
| `spots.send` | `spots.send`: spot do **veřejné** sítě DX clusterů (potřebuje i `spots`) | udělí operátor, ve výchozím stavu vypnuto |
| `app.command` | `app.command`: textové příkazy pole značky — nikdy takový, který může vysílat, sáhnout do sítě, spouštět skripty nebo ničit data | udělí operátor |
| `cat` | `cat.send`: surové příkazy `rigctld` pro aktivní rig — čtení a nastavení frekvence, módu, VFO, splitu, RIT/XIT, úrovní, antény; **nikdy** klíčování | udělí operátor, ve výchozím stavu vypnuto |
| `transmit` | `tx.*`: CW, zprávy F-kláves a hlasové zprávy a PTT — **stanice vysílá** | udělí operátor, ve výchozím stavu vypnuto, s varováním |

Plugin, který žádá o oprávnění vyžadující udělení, čeká, dokud operátor nerozhodne: jeho okno ukazuje pruh s
**Rozhodnout o oprávněních…** (a okno zpráv to jednou oznámí). List se otevře jen po tomto kliku nebo z
Nastavení → **Pluginy** — nikdy sám od sebe, takže nikdy nevezme klávesnici uprostřed QSO. Vypíše
nerozhodnutá oprávnění (zaškrtnutá, kromě `spots.send`, `cat` a `transmit`): **Povolit vybrané** udělí zaškrtnutá,
**Odmítnout vše** žádné — plugin se pak spustí s `read` a `ui` a na ostatní dostává chybu `permission`.
Nastavení → Pluginy oprávnění kdykoli udělí nebo odebere; odebrání platí pro každý požadavek zodpovězený od té chvíle,
i pro ten, který už čeká ve frontě. Zpráva `hello` vypisuje aktuálně udělená oprávnění.

- Rozhodnutí se ukládají pro každé oprávnění v `plugin-settings.json` v datové složce, s klíčem podle složky pluginu
  **a** podle `name` z jeho manifestu: jiný plugin vložený do stejné složky nic nezdědí a plugin, jehož
  manifest žádá o nové oprávnění, čeká znovu — list se ptá jen na to nové.
- Souhlas je ochrana operátora před pluginem, který by dělal víc, než čeká, ne bezpečnostní hranice:
  plugin je program běžící pod vaším účtem a mohl by `plugin-settings.json` upravit sám. Aplikace si změny
  tohoto souboru za běhu všimne, oznámí to v okně zpráv a zapíše zpět svá vlastní rozhodnutí.

## Životní cyklus

- **Start:** když se otevře některé z oken pluginu — z **Okno → Vlastní**, nebo při spuštění, pokud bylo okno
  otevřené při posledním ukončení (okna pluginů se uchovávají v `openWindows` jako `plugin:<id>/<window>` stejně jako ostatní okna).
  Každý plugin běží jednou, bez ohledu na to, kolik jeho oken je otevřeno. Pracovní složka je složka pluginu;
  prostředí obsahuje `MCL_PLUGIN_PROTOCOL=1`, `MCL_PLUGIN_NAME=<id>` a `PYTHONUNBUFFERED=1`.
- **Hello:** aplikace nejprve pošle `hello`. Plugin musí do **10 s** odpovědět jakoukoli zprávou (pomocník posílá
  `{"type":"ready"}`), jinak se zastaví jako zamrzlý.
- **Přepnutí závodu:** plugin běží dál; o přepnutí se dozví přihlášením k `contest-closed` a `contest-opened`.
- **Zastavení:** když zavřete jeho poslední okno, aplikace zavře stdin pluginu, pošle `SIGTERM` a o 1 s později
  `SIGKILL`. Čtěte do konce stdin a skončete.
- **Ukončení aplikace:** přihlášení odběratelé dostanou `app-quitting`, pak vstup skončí; na konci ukončování dostane plugin, který ještě běží,
  `SIGTERM` a o 1 s později `SIGKILL`. Plugin nikdy nezdrží ukončení o víc.
- **Pád:** okno si ponechá poslední obsah pod pruhem *Plugin skončil (kód N)* s tlačítkem **Restart**.
- **Zamrznutí:** žádná odpověď na `hello` do 10 s, nebo plugin nečte svůj vstup (víc než 1 MiB čeká nepřečteno): plugin se
  zastaví, pruh to oznámí, **Restart** ho spustí znovu.
- **Zavřený vstup:** plugin smí zavřít svůj vlastní stdin; aplikace mu pak přestane posílat události a interakce s okny
  (nepovažuje se za zamrzlý) a dál ukazuje, co nastavil.
- **Rychlý výstup:** aplikace čte svým vlastním tempem. Zprávy `set` jednoho okna se slučují (vyhrává poslední);
  ostatní zprávy čekají ve frontě, a když jich čeká 32, aplikace přestane číst, takže plugin, který píše rychleji, než aplikace
  stíhá, se zablokuje na vlastním výstupu.
- **Vypnuto:** s nastaveným `MCL_INERT_HARDWARE` nebo `MCL_INERT_NETWORK` se žádný plugin nespustí (okno to oznámí).

## Zprávy

Každá zpráva je jeden řádek UTF-8 JSON zakončený `\n`, nejvýš **1 MiB**. Řádek, který je delší, není JSON nebo není
známá zpráva, se ignoruje a ohlásí v okně zpráv (každý druh problému jednou za běh). Neznámá pole se
ignorují, takže nová pole lze později přidat, aniž by se cokoli rozbilo.

### Od aplikace

```json
{"type":"hello","protocol":1,"app":{"version":"0.9.0"},"contest":{"id":"cq-ww-cw-2026","name":"CQ WW DX CW"},
 "band":"20m","mode":"CW","windows":["main"],"permissions":["read","ui"]}
```
`contest` je bez aktivního závodu `null`; `band` a `mode` jsou hodnoty aktivního zadávacího okna (`null`, když
nejsou známy).

```json
{"type":"event","event":"qso-logged","data":{"time":"2026-10-07T12:00:00Z","call":"OK1ABC","band":"20m", …}}
```
`data` je přesně ten JSON, který pro danou událost dostane na stdin událostní plugin (viz [tabulka událostí](scripting.md#pluginy)),
se stejným omezením četnosti (`frequency-changed` po 1 s, `score-changed` sloučené).

```json
{"type":"ui","window":"main","action":"click","target":"bands","row":2,"rowId":"40m"}
{"type":"ui","window":"main","action":"double-click","target":"bands","row":2,"rowId":"40m"}
{"type":"ui","window":"main","action":"click","target":"refresh"}
{"type":"ui","window":"main","action":"change","target":"by-mode","value":false}
{"type":"ui","window":"main","action":"select","target":"pages","value":"stats"}
```
`row` je index od 0, `rowId` je `id` řádku (nebo položky seznamu) nebo `null`.

```json
{"type":"response","id":7,"result":{"count":1234}}
{"type":"response","id":8,"error":{"code":"unknown_method","message":"unknown method cat.send"}}
```

### Od pluginu

```json
{"type":"ready"}
{"type":"set","window":"main","content":{"elements":[ … ]}}
{"type":"request","id":7,"method":"log.count","params":{"band":"20m"}}
{"type":"log","text":"something worth seeing"}
```
- `set` nahradí celý obsah jednoho z oken pluginu a potřebuje oprávnění `ui` (bez něj se
  zpráva ignoruje a ohlásí). Okno se překreslí nejvýš **5krát za sekundu**: z dávky `set` se ukáže ta
  poslední.
- `request` — `id` je číslo nebo text, vrací se v odpovědi; požadavky se mohou překrývat, odpovědi mohou přijít v libovolném pořadí.
  Současně se odpovídá nejvýš na **4** požadavky jednoho pluginu; další dostane okamžitě chybu `busy` (pošlete ho
  znovu, až přijde odpověď).
- `log` vloží do okna zpráv `[<name>] text` (oříznuto na 500 znaků). Jdou tam i řádky ze **stderr**. Za běh se ukáže
  nejvýš 500 takových řádků, pak jedno upozornění.

## Obsah okna

`content.elements` je svislý seznam prvků. Aplikace je kreslí svými vlastními písmy a barvami; vy volíte
**styl** (význam), nikdy barvu: `normal`, `title`, `muted`, `warn`, `new`, `dupe`, `mult`. Veškerý text se řídí
ovladačem velikosti písma okna (vpravo nahoře, jako v každém okně) a každý prvek čte VoiceOver.

| Prvek | Pole |
|---|---|
| `text` | `text`, `style` |
| `table` | `columns` (texty, nebo `{"title","align":"right"}`), `rows` (seznamy buněk, nebo `{"id","cells","style"}`), `id` (s id pošle klik nebo dvojklik na řádek událost `ui`) — buňka je text, číslo nebo `{"text","style"}`; `style` řádku platí pro jeho buňky bez vlastního stylu |
| `list` | `items` (texty nebo `{"id","text","style"}`), `id` (kliky jako u tabulky) |
| `button` | `id`, `label`, `enabled` (výchozí `true`) → `click` |
| `toggle` | `id`, `label`, `value` → `change` s novou hodnotou `value` (zobrazí se hned) |
| `progress` | `value`, `max`, `label` |
| `tabs` | `id`, `tabs`: `[{"id","title","elements":[…]}]` → `select`; záložky se vnořují nejvýš do hloubky 3 |
| `canvas` | `width`, `height` (body, nejvýš 4 000), `shapes`, `id` (klik pošle `click` s `value` `{"x","y"}` v souřadnicích plátna), `label` (čte VoiceOver) |

Tvary plátna (počátek vlevo nahoře, y dolů; nejvýš 5 000 na plátno, 2 000 bodů na cestu; `style` jako výše, `fill`,
`lineWidth` 0,5–20): `{"shape":"line","x1","y1","x2","y2"}`, `{"shape":"rect","x","y","w","h"}`,
`{"shape":"circle","cx","cy","r"}`, `{"shape":"path","points":[[x,y],…],"closed"}`,
`{"shape":"text","x","y","text","size"}` (velikost 6–72). Kresba se škáluje s ovladačem velikosti písma okna.

**Ukotvení:** tlačítko vlevo od ovladače velikosti písma ukotví okno pluginu do hlavního okna, pod panel zápisu
(plugin běží dál); panel má tlačítka zpět do samostatného okna a pro zavření. Ukotvená okna se
uchovávají v `plugin-settings.json` a při spuštění se vrátí.

Limity: 2 000 řádků na tabulku nebo položek na seznam (zbytek se ořízne s upozorněním), 2 000 prvků na obsah, limit
řádku 1 MiB pro celý `set`. Typ prvku, který tato verze nezná, se vynechá s upozorněním, zbytek se
zobrazí.

## Požadavky

### Čtení (`read`)

| Metoda | Parametry | Výsledek |
|---|---|---|
| `log.query` | `contest` (výchozí `active`, `none` = volné logování, `all`), `band` (`20m`), `mode` (`CW`), `call` (prefix), `callContains`, `since`, `until` (ISO 8601 UTC), `limit` (výchozí 500, max 10 000), `offset`, `order` (výchozí `asc`, `desc`) | `{"qsos":[…],"total":n}` — každé QSO v podobě `qso-logged`; `total` počítá všechny shody |
| `log.count` | jako `log.query` | `{"count":n}` |
| `log.get` | `uuid` | QSO nebo `null` |
| `contest.active` | — | `{"id","name"}` nebo `null` |
| `contest.score` | — | `{"contestId","qsos","dupes","qsoPoints","mults","bonusPoints","qtcPoints","total","bands":[{"band","qsos","dupes","points","mults"}],"modes":[…]}` — rozpad z okna Skóre; bez závodu `null` |
| `rig.state` | — | `{"radio","freqHz","band","mode","catConnected"}` aktivního zadávacího okna, nebo `null` |
| `spots.list` | `band` | `{"spots":[{"dxCall","freqHz","band","spotter","comment"}]}` od nejnovějších, nejvýš 2 000 |

| `contest.multipliers` | — | `{"contestId","multipliers":[{"id","label","worked","keys":[…],"needed":null}]}` — pracované násobiče podle vazby (přehrání deníku, jako u skóre); `needed` se zatím nepočítá; bez závodu `null` |

Databáze se čte mimo hlavní vlákno aplikace.

### Akce

Každá potřebuje své oprávnění ([Oprávnění](#oprávnění)); odpověď je `{"ok":true}` nebo chyba `refused` s
důvodem (žádné aktivní zadávací okno, v poli značky je příkaz, nepřipojeno, …).

| Metoda | Parametry | Dělá |
|---|---|---|
| `entry.getCall` | — | `{"call","exchange":{id: value},"freqHz","mode","radio"}` aktivního zadávacího okna |
| `entry.setCall` | `call` | napíše značku (jako při psaní): jen písmena, číslice a `/`; text, který by Enter spustil jako příkaz (`ESM`, `CW`, frekvence…), se odmítne |
| `entry.setExchange` | `fields`: `{id: value}` | vyplní pole výměny; odpoví `unknown` s id, která závod nemá |
| `entry.wipe` | — | vymaže zápis (jako Esc) |
| `entry.log` | — | zapíše QSO jako Enter bez ESM — nikdy nevysílá; odmítne se, když je v poli značky příkaz |
| `entry.status` | `text` | zobrazí text ve stavovém řádku |
| `rig.qsy` | `freqHz` (uvnitř radioamatérského pásma), `mode` (volitelné) | QSY aktivního zadávacího okna (jeho rig ho následuje přes CAT); fokus zůstane, kde je |
| `rig.setMode` | `mode` | mód aktivního zadávacího okna |
| `rig.split` | `txFreqHz`, nebo `off: true` | split jako příkaz `SPLIT` |
| `rig.rit` | `offsetHz` (±99 999) | RIT jako příkaz `RIT` |
| `rig.swap` | — | prohodí VFO |
| `rig.focusedRadio` | `radio` (0 nebo 1) | udělá z daného rádia / VFO aktivní |
| `spots.add` | `call`, `freqHz`, `comment` | lokální spot vaší stanice (bandmapa, dostupné násobiče) |
| `spots.remove` | `call`, `blacklist` | odstraní každý spot značky (volitelně na blacklist); `{"removed": bool}` |
| `spots.mark` | `freqHz` | spot `MARK` |
| `spots.blacklist` | `call` | dá značku na blacklist |
| `spots.send` | `call`, `freqHz`, `comment` | pošle spot do DX clusteru (jako Spot It s komentářem) — veřejně. Značka musí být volací značka, komentář prostý text (bez řídicích znaků, nejvýš 60) |
| `app.command` | `text` | spustí textový příkaz pole značky. Povoleno jen: QSY nebo frekvence, druhé VFO, `SPLIT`/`NOSPLIT`, `RIT`, `SWAP`, mód, `NOESM`, `NORPT`, `WORKDUPE`/`NOWORKDUPE`, `VERSION`, `RESCORE`, `REOPEN`, `DEBUGCAT`; vše ostatní (cokoli, co může vysílat, sáhnout do sítě, spouštět skripty, měnit konfiguraci, operátora, závod nebo deník, nebo otevřít dialog) se odmítne |

Chybové kódy: `unknown_method`, `permission`, `invalid_params`, `refused`, `unavailable` (není otevřený žádný deník), `busy`
(víc než 4 požadavky najednou), `failed`.

### Rig a vysílání (`cat`, `transmit`)

| Metoda | Parametry | Dělá |
|---|---|---|
| `cat.send` | `command` | pošle jeden příkaz `rigctld` aktivnímu rigu v rozšířené podobě; `{"lines":[…],"code":n}` (`code` 0 = OK). Přesná gramatika — příkaz a počet a tvar jeho argumentů: čtení `f m v s i x j z t y`, `l <level>`, `\get_freq|mode|vfo|split_vfo|split_freq|split_mode|rit|xit|ptt|ant`, `\get_level <level>`; nastavení `F <Hz>`/`I <Hz>` (uvnitř radioamatérského pásma; odmítne se při nastaveném transvertoru), `M`/`X <mode> <passband>`, `V <vfo>`, `S <0/1> <vfo>`, `J`/`Z <Hz ±99999>`, `L <AF/RF/SQL/NR 0–1, KEYSPD 10–60, CWPITCH 300–1000>` (nikdy `RFPOWER`), `Y <antenna> <option>` (ne během vysílání). Vše ostatní se odmítne: klíčování, surové bajty, tuner, výkon, vlastní příkazy démona, výpisy, oddělovače `;` `|` `\`, přebývající nebo chybějící slova, mezery na začátku, na konci nebo zdvojené, řídicí znaky. Nejvýš **10 za sekundu** na plugin a 15 pro všechny pluginy (`rate_limited`). Příkazy pluginů jdou vlastním spojením s `rigctld`, nikdy spojením operátora, takže nikdy nečekají ve vlastní frontě aplikace. `rigctld` sám ovšem serializuje přístup k rigu přes všechna svá spojení, takže pomalý příkaz pluginu může i tak zdržet příkazy aplikace nebo `T 0` na straně `rigctld`; proto je CAT pluginů omezen četností, časem (1 s na odpověď) a jen na krátké příkazy. Odpověď přes 16 KiB nebo jakákoli chyba čtení či timeout spojení pluginu zavře (odpověď se nikdy nenechá napůl přečtená); zavře se také, když už žádný běžící plugin nemá `cat`, když se rig odpojí a při ukončení aplikace, a s dalším příkazem se otevře znovu. Současně čeká nejvýš 16 příkazů pluginů (další dostanou `busy`). Příkazy CAT pluginů, které ještě čekají ve frontě, když operátor zastaví vysílání, uvolní se PTT pluginu, plugin ztratí `cat` nebo se zastaví, se zahodí dřív, než se zapíší. Každý příkaz a jeho odpověď se objeví v okně CAT log. |
| `tx.sendCw` | `text` (makra zpráv F-kláves povolena) | odvysílá CW klíčem aplikace (jen v módu CW) |
| `tx.fkey` | `key` 1–12, `opposite` | stiskne danou F-klávesu v aktivním zadávacím okně (CW, hlas nebo digitální podle módu, pravidla ESM) |
| `tx.voice` | `key` 1–12 | hlasová zpráva dané F-klávesy (jen ve fonii) |
| `tx.stop` | — | Esc: zastaví každé vysílání (i PTT pluginu); `{"stopped": bool}` |
| `tx.ptt` | `on` | klíčuje nebo uvolní PTT aktivního rigu |

Vše jde přesně cestami F-kláves, Esc a PTT nožního spínače: zámek simulátoru pileupu
odmítne, Esc ho zastaví (i vše ostatní, co vysílá), ukončení aplikace a odpojení rigu ho uvolní a plugin,
který se zastaví, spadne nebo ztratí udělení `transmit`, nikdy nenechá PTT sepnuté ani svou zprávu ve vysílání.
U `T 1` se nikdy nepředpokládá, že nic neklíčovalo, jakmile odešlo: ať ho `rigctld` odmítl (`RPRT -n`; hamlib hlásí
některé chyby až poté, co rig zareagoval), nebo je jeho výsledek neznámý (timeout, ztracené spojení), hned následuje `T 0` a
plugin dostane `refused`; pokud selže i tento `T 0`, uvolnění zůstává dlužné. `T 1` pluginu ani uvolňující `T 0` nikdy nejde
spojením s rigem, které může být rozladěné — takovým, na kterém něco selhalo po zapsání příkazu a před přečtením
celé jeho odpovědi (timeout, chyba zápisu nebo čtení, chyba CAT logu), takže nepřečtená nebo opožděná odpověď by mohla být
považována za jeho vlastní. Takové spojení se nejprve transparentně otevře znovu (rig zůstane připojený a dotazování pokračuje);
příkaz PTT pluginu, jehož vlastní odpověď selže, ho také hned otevře znovu (nové spojení se naváže dřív, než se staré
zavře). `T 1` pluginu, který odešel, ale nedostal odpověď, se může provést i později — `rigctld` může být zaneprázdněn jiným klientem
— dokonce i po `T 0` odeslaném jiným spojením. Proto jde `T 0` hned za ním stejným spojením (`rigctld`
provádí příkazy jednoho spojení v pořadí), toto spojení se ponechá a čte na pozadí, a dokud se čte, žádný
jiný `T 0` uvolnění nepotvrdí. Pokud je `T 0` za klíčováním přijat, uvolnění je potvrzeno. Pokud klíčování
odpovědělo, ale ten `T 0` ne, potvrdí to `T 0` odeslaný od té chvíle. Pokud neodpovědělo ani klíčování, nepotvrdí nic,
dokud operátor nezkontroluje rig a nezvolí **Uvolnit znovu**. Bez připojeného rigu se PTT odmítne. PTT pluginu se uvolní nejpozději po **30 s** (Nastavení → Pluginy, 5–300 s), počítáno od
okamžiku, kdy byl rig sepnut. Dokud jeden plugin drží PTT, žádný jiný plugin ho nemůže sepnout, a opětovné sepnutí
limit neprodlouží. Po vynuceném uvolnění nesmí žádný plugin klíčovat 10 s (po vlastním uvolnění pluginu 2 s). Uvolnění se nikdy
nedotkne operátorova vlastního spojení s rigem: `T 0` jde ven po něm (za příkazy, které tam už čekají) a zároveň
novým spojením k `rigctld`, ke kterému je rig připojen.

Každé uvolnění zvýší vlastní epochu uvolnění daného rigu; uvolnění jednoho rigu (SO2R) se nikdy nedotkne klíčování pluginů
na druhém. `T 1` pluginu, který ještě nebyl zapsán, když se epocha jeho rigu změní, se zahodí. Kontrola proběhne, dokud je
spojení s rigem drženo, těsně před zápisem. Odebrání `transmit`, zavření okna pluginu nebo konec pluginu
uvolní i klíčování, které je ještě na cestě. `T 1`, který už byl na cestě a rig přesto sepnul, okamžitě spustí
další uvolnění. Každý `T 0` nese epochu, pro kterou byl odeslán, a potvrzuje jen tuto epochu, a jen dokud je
stále aktuální epochou rigu. To je `T 0` na vlastním spojení rigu (který následuje každý dřívější `T 1`
pluginu), nebo ten nový, pokud v době jeho odeslání nečekal žádný `T 1` pluginu.

Dokud uvolnění není potvrzeno, ukazuje hlavní okno červené varování a žádný plugin nemůže klíčovat. Odmítnutý `T 0` se zkouší znovu
po 0,5, 1 a 1,5 s a pak každých 10 s, dokud rig zůstává připojený. Když se rig znovu připojí, dlužný `T 0`
odejde jednou (ne při každém dotazu). Po rychlých opakováních nabídne varování **Uvolnit znovu**. Ukončení aplikace čeká na
nové uvolnění.

Uvolnění pluginem nikdy nepřeruší operátorovo vlastní vysílání na stejném rigu (nožní spínač, hlas, CW, ladění):
`T 1` pluginu je bezpředmětný, dokud PTT drží operátor. Jeho `T 0` počká a odejde, jakmile toto vysílání
skončí (stav klíče, hlasového klíče a nožního spínače se sleduje přímo, nejen při příštím dotazu), a nejpozději
po časovém limitu PTT pluginu. Esc, Stop indikátoru, **Uvolnit znovu**, odpojení nebo ztráta rigu a
ukončení aplikace nikdy nečekají (uvolnění, které už čeká, odejde okamžitě).

PTT uvolňuje jen plugin, který ho drží (`off` jiného pluginu nic nezmění, operátorovo vlastní vysílání
plugin nikdy nepřeruší). Dokud plugin vysílá, ukazuje hlavní
okno **Plugin X vysílá** s tlačítkem pro zastavení.

- **Esc a Stop platí trvale:** když operátor stiskne Esc (nebo Stop indikátoru) během vysílání pluginu, vysílání
  pluginů zůstane zablokované — hlavní okno ukazuje *Vysílání pluginů zastaveno* s tlačítkem **Povolit** — dokud je
  operátor znovu nepovolí.
- **Rozpočet vysílání** (konzervativní výchozí hodnoty, které může vlastník změnit, Nastavení → Pluginy): vysílání pluginu
  (zprávy navazující těsně za sebou se počítají jako jedno) se přeruší po **60 s** (5–300 s); všechny pluginy dohromady smějí
  vysílat nejvýš **50 %** z libovolných 5 minut (10–100 %) — PTT ani zpráva nikdy nepřesáhne, co z toho zbývá; nejvýš dvě
  zprávy pluginů smějí být ve vysílání v jednom vysílání, ať je poslal kterýkoli plugin (`busy`), každý CW text nejvýš
  200 znaků.
- Esc během `T 1` pluginu, který je ještě na cestě, také zablokuje vysílání pluginů a toto klíčování se uvolní, jakmile
  se dokončí.

### Klávesy

```json
{"type":"key","action":"last-call","phase":"press"}
```
Nastavení → Klávesy vypisuje každou akci pluginu: **Změnit** zachytí klávesu, **Žádná** ji odebere a *Ponechat i původní
funkci klávesy* nechá klávese i její vlastní funkci v zadávacím okně (jinak ji klávesa pluginu nahradí; seznam
ukazuje konflikt s vlastní zkratkou aplikace). Esc, Enter, Tab, mezerník a samotné F1–F12 nikdy nepatří
pluginu — klávesy pro zastavení a vysílání zůstávají vždy aplikaci; klávesa se nikdy neváže na dvě akce pluginů. Klávesy působí,
dokud má fokus pole zápisu. Plugin, který opakovaně padá, jeho klávesy restartují nejvýš 3krát za minutu;
potom ho spustí jen Restart.

## Pomocník pro Python

[`docs/plugins/mcl.py`](../plugins/mcl.py) je jeden soubor, jen se standardní knihovnou. Zkopírujte ho vedle svého pluginu:

```python
#!/usr/bin/env python3
import mcl

plugin = mcl.Plugin()

def show(_=None):
    count = plugin.request("log.count")["count"]
    plugin.set_window("main", [mcl.text(f"{count} QSOs", style="title"), mcl.button("refresh", "Refresh")])

plugin.on_start(show)
plugin.on("qso-logged")(show)
plugin.on_click("refresh")(show)
plugin.run()
```

Obslužné funkce běží jedna po druhé v pořadí, v jakém aplikace zprávy poslala; `request` blokuje, dokud nepřijde odpověď
(odpovědi se čtou ve vlákně na pozadí; `_timeout=` nastaví čekání v sekundách, výchozí 30). `mcl.text`, `table`, `row`, `cell`, `column`, `list_`, `item`, `button`,
`toggle`, `progress`, `tabs`, `tab` a `canvas` (s `line`, `rect`, `circle`, `path`, `label`) sestavují prvky;
`@plugin.on_key("action")` obsluhuje klávesovou akci. Příklad
[`band-activity`](../plugins/examples/band-activity/) používá `entry`, `rig`, plátno a klávesovou akci.

## Webová okna

Okno s `"kind": "web"` ukazuje ve webovém zobrazení vlastní HTML stránku pluginu (`page`, uvnitř složky pluginu).
Stránka komunikuje s aplikací přes `window.mcl`:

```js
const score = await window.mcl.request("contest.score");   // a promise; rejected with {code, message}
window.mcl.on("qso-logged", (qso) => { … });                // the plugin's subscribed events
```

- Stejné metody, oprávnění, limity a pravidla vysílání jako u požadavků procesu; plugin může mít proces i
  webová okna, nebo (`"process": false`) jen webová okna — viz příklad
  [`web-score`](../plugins/examples/web-score/).
- Aplikace poskytuje soubory pluginu sama (`mcl-plugin://local/…`, jen ze složky pluginu) s přísnou
  **Content-Security-Policy**: skripty jen z vlastních souborů pluginu (dejte je do souborů `.js` — inline skripty
  jsou blokované, pokud manifest neuvádí `"webInlineScripts": true`, a nikdy pro plugin, jehož manifest žádá
  `transmit` nebo `cat`), žádné pluginy, `connect`/`img`/`frame` jen na samotný plugin a `https` na `webHosts`
  z manifestu.
- Stránka nikdy neodnaviguje pryč ze souborů pluginu (žádná vzdálená stránka, žádná navigace `data:`, `blob:`, `javascript:` ani
  `file:`, žádná vyskakovací ani nová okna); podrámce a podzdroje smějí načítat `https` z `webHosts`.
  Požadavky do aplikace může posílat jen hlavní rámec stránky pluginu. Mezi běhy se neuchovávají žádné cookies ani úložiště.
- **Escapujte nedůvěryhodná data.** Pole QSO, spoty a komentáře z clusteru pocházejí od jiných lidí: vkládejte je do stránky
  přes `textContent` (nebo je escapujte), nikdy přes `innerHTML`.
- Ovladač velikosti písma okna stránku zvětšuje.

## Pomocník pro Node.js

[`docs/plugins/mcl.js`](../plugins/mcl.js) je stejný pomocník pro Node.js (jeden soubor, žádné balíčky):
`new mcl.Plugin()`, `onStart`, `on(event)`, `onClick`, `onChange`, `onKey`, `request` (promise), `setWindow`,
`log`, `run` a stejné sestavovače prvků a plátna jako `mcl.py`.

## Plán dalšího vývoje

Pozdější verze mohou přidat počty `needed` do `contest.multipliers`, další typy prvků a další požadavky; nová
oprávnění se přidávají stejným způsobem — plugin, který žádá o oprávnění, které tato verze nezná, se nespustí, a tentýž
`plugin.json` se spustí, jakmile je nainstalovaná verze, která ho zná, a operátor ho povolí.
