# Propojení WSJT-X ⇄ RUMlogNG ⇄ MacContestLogger přes UDP

Návod, jak nastavit tři aplikace tak, aby si přes UDP předávaly zapsaná QSO.
Pokrývá 4 hlavní scénáře (případy užití); třetí má tři podvarianty.

Všechny příklady předpokládají **jeden počítač** (adresy `127.0.0.1`). Na více počítačích nahraďte
loopback skutečnými IP adresami.

---

## 1. Kdo mluví kterým protokolem na kterém portu

Existují **dva různé síťové protokoly**, které spolu přímo nekomunikují:

| Protokol | Přenáší | Výchozí port | Formát |
|---|---|---|---|
| **WSJT-X** | zapsané QSO z WSJT-X | 2237 | binární (QSO Logged + Logged ADIF) |
| **N1MM contactinfo** | zapsané QSO z deníku | 12060 | textové XML `<contactinfo>` |

Schopnosti jednotlivých aplikací (co **přijímá** = na čem naslouchá, co **posílá**):

| Aplikace | Přijímá (naslouchá) | Posílá (při zápisu) |
|---|---|---|
| **WSJT-X** | nic (jen zdroj) | **protokol WSJT-X** na 1 cíl (UDP Server), výchozí `:2237` |
| **RUMlogNG** | **protokol WSJT-X** na `:2237` | **N1MM contactinfo** na nastavitelný cíl (výchozí `:12060`) |
| **MacContestLogger** | **protokol WSJT-X** (`wsjtx.receiveBind`, výchozí `:2237`, **jen unicast**) a **N1MM contactinfo** (`n1mmRecv.receiveBind`, výchozí `:12061`, unicast i multicast) | **protokol WSJT-X** (`wsjtx.sendTargets`) a **N1MM contactinfo** (`broadcast.contactsTargets`) |

### Propojení (kdo může krmit koho)

```
WSJT-X  ──WSJT-X proto (2237)──►  RUMlogNG
WSJT-X  ──WSJT-X proto (2237)──►  MacContestLogger
MacContestLogger  ──WSJT-X proto (2237)──►  RUMlogNG      (MCL emulates WSJT-X)
RUMlogNG  ──N1MM contactinfo (12061)──►  MacContestLogger
```

**RUMlog importuje jen protokol WSJT-X**; cizí N1MM contactinfo do svého deníku
nepřebírá. Proto cesta „MacContestLogger → RUMlog“ vede **jen** přes emulaci WSJT-X
(MacContestLogger posílá protokol WSJT-X na port 2237 RUMlogu), ne přes N1MM.

---

## 2. Pravidla pro porty a omezení

1. **Port 2237 smí na jednom počítači obsadit jen jedna aplikace.** RUMlog i
   MacContestLogger chtějí přijímat protokol WSJT-X na 2237, takže to nemohou dělat oba
   současně. V každém scénáři jasně určete, kdo 2237 „vlastní“.
2. **WSJT-X má jen jeden cíl UDP Server.** Rozeslání více příjemcům funguje jen přes
   multicast, nebo přes řetězec (WSJT-X → RUMlog → N1MM → MacContestLogger).
3. **Příjem WSJT-X v MacContestLoggeru je jen unicast**; nemůže se připojit do multicastové skupiny.
   (Příjem N1MM multicast umí.) Proto se WSJT-X → oba deníky řeší
   **řetězcem přes RUMlog**, ne multicastem WSJT.
4. **Import do MacContestLoggeru vyžaduje aktivní závod.** Bez něj se přijaté QSO
   zahodí (jen stavová zpráva). Pro běžný provoz si definujte „klasický“ závod.
5. **Bez ozvěny + deduplikace:** QSO přijaté ze sítě MacContestLogger neposílá zpět
   (žádným odesílačem); dvojí příjem téhož QSO dvěma cestami (±120 s, stejná
   značka/pásmo) se uloží jen jednou.
6. **Přístup ke konfiguraci MacContestLoggeru:** nastavení je na záložce WSJT v
   okně Nastavení. Pokud ji nevidíte, přepněte `tab.wsjt` v `menu.json` z `"hidden"` na
   `"enable"`; soubor vytvoříte v Nastavení → Other → Menu aplikace;
   viz [settings.md](settings.md#menu-aplikace).

### MacContestLogger: kde se co nastavuje

| Funkce | UI (Nastavení) | config.json |
|---|---|---|
| Příjem z WSJT-X | WSJT → „Příjem z WSJT-X“ | `wsjtx.receiveEnabled` + `wsjtx.receiveBind` |
| Posílání do deníků přes WSJT-X | WSJT → „Vysílání do deníků“ | `wsjtx.sendEnabled` + `wsjtx.sendTargets` |
| Příjem N1MM / RUMlog | WSJT → „Příjem N1MM / RUMlog“ | `n1mmRecv.receiveEnabled` + `n1mmRecv.receiveBind` |

---

## 3. Případ 1: WSJT-X ⇄ RUMlogNG (samostatně)

WSJT-X zapisuje, RUMlog přijímá. MacContestLogger se neúčastní.

```
WSJT-X ──WSJT-X proto──► RUMlogNG (:2237)
```

| Aplikace | Nastavení |
|---|---|
| **WSJT-X** | Settings → Reporting → UDP Server = `127.0.0.1`, port `2237`, „Accept UDP requests“ zapnuto |
| **RUMlogNG** | příjem z WSJT-X zapnutý (naslouchá na `2237`) |
| **MacContestLogger** | není potřeba (neběží, nebo má příjem na 2237 vypnutý, jinak koliduje s RUMlogem) |

Směr: WSJT-X → RUMlog (jednosměrně).

---

## 4. Případ 2: WSJT-X → MacContestLogger

WSJT-X zapisuje, MacContestLogger přijímá (přebírá roli RUMlogu).

```
WSJT-X ──WSJT-X proto──► MacContestLogger (:2237)
```

| Aplikace | Nastavení |
|---|---|
| **WSJT-X** | UDP Server = `127.0.0.1:2237` |
| **MacContestLogger** | WSJT → „Příjem z WSJT-X“ **zapnuto**, bind `0.0.0.0:2237`; **aktivní závod** |
| **RUMlogNG** | nesmí obsadit `2237` (neběží, nebo má příjem z WSJT-X vypnutý), jinak nastane konflikt portů |

Směr: WSJT-X → MacContestLogger. V tomto scénáři RUMlog port 2237 nedrží.

---

## 5. Případ 3: MacContestLogger ⇄ RUMlogNG

Tři podvarianty. WSJT-X tu není potřeba (QSO vznikají v denících).

### 5a) RUMlog zapisuje, MacContestLogger naslouchá

```
RUMlogNG ──N1MM contactinfo──► MacContestLogger (:12061)
```

| Aplikace | Nastavení |
|---|---|
| **RUMlogNG** | cíl N1MM/UDP broadcastu = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT → „Příjem N1MM / RUMlog“ **zapnuto**, bind `0.0.0.0:12061`; **aktivní závod**. Příjem i vysílání WSJT vypnuté. |

Směr: RUMlog → MacContestLogger. (Výchozí broadcastový port RUMlogu 12060 přesměrujte na 12061, protože 12060 drží RUMlog sám.)

### 5b) MacContestLogger zapisuje, RUMlog naslouchá

RUMlog importuje jen protokol WSJT-X, takže ho MacContestLogger musí emulovat.

```
MacContestLogger ──WSJT-X proto──► RUMlogNG (:2237)
```

| Aplikace | Nastavení |
|---|---|
| **MacContestLogger** | WSJT → „Vysílání do deníků“ **zapnuto**, cíle = `127.0.0.1:2237`. Příjem WSJT i příjem N1MM vypnutý (2237 patří RUMlogu). |
| **RUMlogNG** | příjem z WSJT-X zapnutý (naslouchá na `2237`) |

Směr: MacContestLogger → RUMlog. RUMlog považuje MacContestLogger za WSJT-X.

### 5c) Oba zapisují, oba naslouchají (obousměrně)

Kombinace 5a + 5b. Žádný konflikt portů: RUMlog drží 2237, MacContestLogger drží 12061.

```
MacContestLogger ──WSJT-X proto (2237)──► RUMlogNG
RUMlogNG ──N1MM contactinfo (12061)──► MacContestLogger
```

| Aplikace | Nastavení |
|---|---|
| **RUMlogNG** | příjem z WSJT-X na `2237`; cíl N1MM broadcastu = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT „Vysílání“ **zapnuto** → `127.0.0.1:2237`; N1MM „Příjem“ **zapnuto**, bind `0.0.0.0:12061`; WSJT „Příjem“ **vypnuto** (2237 drží RUMlog); **aktivní závod** |

Tok v obou směrech. **Ošetření smyčky:** když MacContestLogger zapíše QSO, pošle ho
RUMlogu protokolem WSJT-X; RUMlog ho zapíše a rozešle zpět přes N1MM na 12061.
MacContestLogger tak dostane své vlastní QSO zpět, ale **deduplikace ±120 s** (stejná
značka/pásmo/čas) ho zahodí, takže se neuloží dvakrát. V opačném směru MacContestLogger QSO
přijaté z RUMlogu dál **neposílá** (bez ozvěny), takže nevznikne nekonečná
smyčka.

---

## 6. Případ 4: WSJT-X zapisuje, oba deníky naslouchají

WSJT-X má jen jeden cíl UDP a příjem WSJT v MacContestLoggeru je jen unicast, takže se to
řeší **řetězcem přes RUMlog** (ne multicastem WSJT):

```
WSJT-X ──WSJT-X proto (2237)──► RUMlogNG ──N1MM contactinfo (12061)──► MacContestLogger
                                    │
                                  (logs)                              (logs)
```

| Aplikace | Nastavení |
|---|---|
| **WSJT-X** | UDP Server = `127.0.0.1:2237` |
| **RUMlogNG** | příjem z WSJT-X na `2237`; cíl N1MM broadcastu = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT → „Příjem N1MM / RUMlog“ **zapnuto**, bind `0.0.0.0:12061`; příjem WSJT **vypnut** (2237 drží RUMlog); **aktivní závod** |

Tok: WSJT-X zapíše → RUMlog importuje a zapíše → RUMlog rozešle přes N1MM → MacContestLogger
importuje a zapíše. **QSO mají oba deníky.**

> **Poznámka / budoucí zlepšení:** přímé WSJT-X → oba deníky najednou (bez RUMlogu jako
> prostředníka) by fungovalo jen přes **multicastovou** skupinu, do které se připojí oba příjemci.
> Příjem WSJT-X v MacContestLoggeru je zatím **jen unicast**, takže tuto přímou
> variantu neumí; přidání podpory multicastu do příjmu WSJT je kandidátem na samostatnou funkci.
> Do té doby je doporučenou cestou řetězec přes RUMlog.

---

## 7. Rychlá tabulka portů (jeden počítač)

| Port | Kdo ho obsazuje (naslouchá) | Protokol |
|---|---|---|
| `2237` | RUMlog **nebo** MacContestLogger (příjem WSJT), vždy jen jeden | WSJT-X |
| `12061` | MacContestLogger (příjem N1MM) | N1MM contactinfo |
| `12060` | RUMlog (jeho vlastní N1MM broadcast/monitor) | N1MM contactinfo |

**Zlaté pravidlo:** v každém scénáři rozhodněte, kdo vlastní **2237**. Pokud ho má RUMlog,
MacContestLogger přijímá od RUMlogu přes **N1MM na 12061** a RUMlogu posílá přes
**protokol WSJT-X na 2237**.

## Dekódy WSJT-X (Decode List)

Když je zapnutý **příjem z WSJT-X**, zpracovává MCL kromě zapsaných QSO také dekódy
a stav WSJT-X. Okno **Okno → WSJT-X dekódy** je ukazuje
obarvené podle aktivního závodu (jako bandmapu):

- šedá = dupe, modrá = nové QSO, červená = nový násobič, zelená = více násobičů,
- filtry „Jen CQ“, „Skrýt dupe“, „Jen násobiče“,
- **dvojklik** na řádek pošle WSJT-X zprávu *Reply*: WSJT-X zavolá stanici, jako byste
  dvakrát klikli v jeho okně Band Activity (WSJT-X musí mít zapnuté „Accept UDP requests“).

Frekvence dekódu = frekvence VFO z WSJT-X + posun ve zvukovém pásmu; pásmo se
určí z ní.

---

## Pakety N1MM broadcastu (Nastavení → Broadcast Data)

Každý typ paketu je ve výchozím stavu vypnutý a posílá se jen na cíle `host:port`, které zadáte. Funguje i
broadcastová adresa podsítě, např. `192.168.1.255:12060` (socket má `SO_BROADCAST`).

| Paket | Posílá se | Obsah |
|---|---|---|
| `contactinfo` / `contactreplace` / `contactdelete` | QSO zapsáno, upraveno, smazáno | úplný seznam tagů N1MM: pásmo, frekvence, operátor, značka, země a prefix WPX, odeslané/přijaté RST a pořadové číslo, přijatá výměna (`exchange1`) a její části podle významu (`gridsquare`, `zone`, `section`, `qth`, `name`, `power`, `prec`, `ck`), body, příznak násobiče, `radionr` / `run1run2`, `IsRunQSO`, `IsOriginal`, název stanice, ID a `SentExchange` |
| `RadioInfo` | každých 10 s a při každé změně | číslo rádia, frekvence RX a TX (split), mód, vlastní značka, operátor, Run/S&P, vybraná anténa, fokus/aktivní rádio, stereo, split, vysílání, název rigu, pomocná anténa; v SO2R jeden paket na rádio (`RadioNr` 1 a 2) |
| `dynamicresults` | každých 10 s v závodě | závod, značka, operátoři, třída kategorie, klub, QTH (země, zóny, sekce, stát, lokátor), rozpad QSO a bodů podle pásem a módů se součty QSO/bodů/násobičů, skóre |
| `AppInfo` | při startu broadcastu | databáze, závod, stanice |
| `spot` (Spots) | spot se objeví v bandmapě nebo z ní zmizí | DX značka, frekvence (kHz), spotter, `add`/`delete`, mód, komentář, stav pro tuto stanici (`dupe`, `single`/`double`/`triple mult`, `new qso`) a seznam stavů (přidává `cq`) |
| `lookupinfo` (Lookup) | mezerník v poli značky, před zápisem | seznam tagů `contactinfo` pro napsanou značku (prefixy, frekvence, mód, operátor) |

Části výměny pocházejí z přijímaných polí definice závodu: pole `LOCATOR` jde do
`gridsquare`, zóna CQ/ITU do `zone`, stát, provincie, okres, HQ nebo reference IOTA do `qth` a
pole s id `sec`/`section`, `name`, `power`/`pwr`, `prec` nebo `ck`/`check` do odpovídajících tagů.

**All QSOs** (zaškrtávátko pod řádky paketů) přeposílá spojení, která tato stanice nezapsala, na
cíle Contacts s `IsOriginal` nastaveným na `False`: QSO, která přinese síť stanic (MQTT cluster) od
ostatních stanic, a pakety `contactinfo` přijaté od jiných deníků (příjem N1MM). Paket, který už
uvádí `IsOriginal False`, se nikdy znovu nepřeposílá, takže dvě stanice, které obě přeposílají, nemohou spustit
bouři paketů.

**Sdílený přijímací port.** Přijímače N1MM a ADIF (záložka WSJT/JTDX) mají přepínač *Sdílet port s dalšími
aplikacemi*: socket se otevře s `SO_REUSEADDR`/`SO_REUSEPORT`, takže na stejném portu může naslouchat i jiný
program. Broadcastové datagramy (na `x.x.x.255`) dorazí ke všem posluchačům; unicastový datagram jen k jednomu
z nich, proto když port sdílí více programů, posílejte na broadcastovou adresu podsítě.
