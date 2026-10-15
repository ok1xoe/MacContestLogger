# Online scoreboard

Obdoba **Score Reporting** z N1MM / DXLogu. **„Nastavení → Score Reporting“**:

- **„Odesílat průběžné skóre na server“** — zapne odesílání (jen v závodě
  a jen po změně deníku).
- **Scoreboard**: předvolba nebo vlastní URL. Předvolby: contestonlinescore.com
  (výchozí), contest.run (`http://contest.run`), Score Distributor
  (`http://scoredistributor.net`, přeposílá skóre na online scoreboardy)
  a hamscore.com. contest.run a Score Distributor fungují jen přes prosté HTTP. Dříve
  uložená URL, která neodpovídá žádné předvolbě, se zachová a zobrazí jako vlastní URL.
  contest.run očekává v `<contest>` vlastní identifikátory závodů (např. `CQ-WW-RTTY`,
  `RDXC`); jeho odpověď „Contest or alias not found“ znamená, že se název závodu
  liší.
- **Interval** (nejméně 2 minuty, výchozí 5).
- **„Včetně rozpadu po pásmech a módech“** — QSO, body a násobiče
  pro každou kombinaci pásmo × mód.
- **„Odeslat teď“** uloží nastavení a skóre ihned odešle; pod tlačítkem je stav
  posledního odeslání (kód HTTP s důvodem, který server uvede při odmítnutí, např.
  „Contest not supported“, nebo srozumitelná chyba: server nedostupný, vypršel čas,
  neplatná adresa).

Odesílá se dokument XML `<dynamicresults>` (závod, značka, operátoři, kategorie z nastavení
závodu, zóny a lokátor, rozpad, skóre, čas UTC) jako formulář `xml=...` metodou POST. Skóre
se přepočítá z celého deníku (stejně jako v okně Skóre).

# Club Log Live Stream

Obdoba **Club Log real-time upload** z N1MM / DXLogu. **„Nastavení → Score Reporting →
Club Log Live Stream“**:

- **E-mail účtu**, **Heslo aplikace** (clublog.org → Settings → App Passwords), volací
  značka deníku (prázdné = značka stanice) a **API klíč** (vydává ho Club Log),
- po zapnutí se každé nově zapsané QSO (ne importovaná) odešle jako jeden záznam ADIF
  na `clublog.org/realtime.php`,
- když je Club Log nebo síť nedostupná, QSO zůstane ve frontě a odešle se
  po minutě; odmítnutí (špatné přihlášení / data) se ukáže ve stavu
  pod nastavením.

Vše odeslané do Club Logu se zaznamenává do `clublog.log` v datové složce (vedle
`cat.log`; vznikne při prvním nahrání): požadavek, pole formuláře, záznam ADIF,
stav HTTP s prvním řádkem odpovědi a co se se záznamem stalo
(`sent`, `retry in 60 s`, `dropped (rejected)`). Heslo aplikace a API klíč
se zapisují jako `***`, e-mailová adresa jako `t***@example.com`.

Fronta je v paměti — QSO neodeslaná do ukončení aplikace je nutné do Club Logu
nahrát ručně (export ADIF).

## Odeslání výsledku na 3830scores.com

Obdoba **Report Score to 3830** z N1MM. **„Soubor → Odeslat výsledek na 3830…“** (vyžaduje otevřený závod)
zobrazí údaje pro formulář výsledků [3830scores.com](https://www.3830scores.com/) za aktivní závod:

- značka, závod, kategorie (`OPERATOR: …, POWER: …` z nastavení závodu), operátoři, lokátor,
- QSO, body za QSO, násobiče (se skupinami, když jich závod má více), bonusové body a body za QTC, pokud se
  započítávají, a **deklarované skóre** celého deníku,
- pole **Soapbox**, které se předvyplní soapboxem z nastavení závodu a lze ho zde upravit (zpět se
  nezapisuje).

**Zkopírovat** dá řádky do schránky, **Otevřít 3830scores.com** otevře web v prohlížeči. Web má **pro každý
závod jeden formulář** (odkazy v levé navigaci) s adresou, kterou nelze sestavit, bez zdokumentovaného způsobu
předvyplnění a bez API, takže MacContestLogger **nic neodesílá a neukládá žádné přihlašovací údaje**: otevřete
web, vyberte formulář závodu a vložte zkopírované údaje. (Výše popsaný průběžný scoreboard je jiná služba.)
