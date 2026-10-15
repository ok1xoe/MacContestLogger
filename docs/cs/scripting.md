# Skripty a pluginy

Obdoba **Scripts** z DXLogu a externích aplikací v N1MM.

## Makroskripty

Textový soubor `~/Library/Application Support/MacContestLogger/scripts/<name>.txt`,
každý řádek jeden **textový příkaz pole značky** (viz [text-commands.md](text-commands.md)),
`#` = komentář. Spuštění: do pole značky napište `SCRIPT name` a stiskněte Enter.

```
# scripts/run20.txt — přechod na Run na 20 m CW
CW
14025
NOSPLIT
RIT 0
RUNSP
```

Příkazy se provedou postupně, jako by je operátor psal; vnořený
`SCRIPT` se nespustí, aby nevznikaly smyčky.

## Pluginy

Pluginy, které zobrazují vlastní okna a za běhu čtou deník, popisuje stránka
[Okna pluginů](plugin-windows.md); na níže popsané pluginy událostí nemají vliv.

Spustitelný soubor (skript s `#!`, program) v podadresáři podle
události:

| Adresář `.../MacContestLogger/plugins/` | Kdy se spouští | JSON na stdin |
|---|---|---|
| `qso-logged/` | po zapsání QSO (ne při importu) | čas, značka, pásmo, frekvence, mód, reporty, výměny, operátor, závod, uuid |
| `contest-opened/` | po otevření závodu | id a název závodu, značka |
| `spot-received/` | u každého spotu z DX clusteru | značka, frekvence, spotter, komentář |
| `qso-edited/` | operátor upravil QSO této stanice (ne import, ne příchod přes synchronizaci clusteru, ne simulované QSO) | `old` a `new`, každé s poli z `qso-logged` |
| `qso-deleted/` | operátor smazal QSO této stanice (stejné výjimky) | pole z `qso-logged` |
| `contest-closed/` | operátor přepnul na jiný závod nebo zvolil Závod, Žádný | `contestId`, `name` |
| `app-started/` | jakmile je start dokončen | `version`, `contestId`, `name` (poslední dvě `null` bez závodu) |
| `app-quitting/` | první krok ukončení, před vypnutím | `version`, `contestId`, `name` |
| `band-changed/` | změnilo se pásmo aktivního okna zápisu | `radio`, `oldBand`, `newBand` (ADIF, např. `20m`) |
| `mode-changed/` | změnil se mód aktivního okna zápisu | `radio`, `oldMode`, `newMode` |
| `frequency-changed/` | frekvence se ustálila na nové hodnotě (viz níže) | `radio`, `oldFreqHz`, `newFreqHz` |
| `self-spotted/` | někdo spotnul vaši značku („Byl jsi spotnut“, RBN) | `spotter`, `freqHz`, `source` (`skimmer` nebo `human`), `snr`, `wpm` (`null`, když nejsou známé) |
| `new-multiplier/` | QSO zapsané zde přineslo aspoň jeden nový násobič (aktivní závod, ne dupe) | `contestId`, `call`, `band`, `mode`, `multipliers` (seznam `{set, key}`) |
| `score-changed/` | změnilo se skóre aktivního závodu (viz níže) | `contestId`, `qsos`, `qsoPoints`, `mults`, `bonusPoints`, `qtcPoints`, `total` |
| `score-reported/` | po odeslání na scoreboard | `host`, `status` (stav HTTP, 0 = bez odpovědi), `accepted`, `message` |
| `clublog-upload/` | po každém pokusu o nahrání do Club Logu | `outcome` (`ok`, `rejected`, `retry`), `call`, `status` (text stavu) |

- Proměnná prostředí `MCL_EVENT` nese název události ve tvaru adresáře (`qso-logged`,
  `frequency-changed`, ...).
- Co plugin vypíše na stdout (nejvýše 50 řádků), objeví se v okně zpráv
  pod názvem pluginu; nenulový návratový kód se ohlásí.
- Plugin, který běží déle než 10 s, se ukončí. Více pluginů pro jednu událost
  běží postupně v abecedním pořadí.

### Omezení četnosti a rozsah

- `radio` je index rádia / VFO od 0 (druhé okno zápisu v SO2V a SO2R je `1`). Události pásma, módu a frekvence
  pocházejí z aktivního okna zápisu, s rigem i bez něj; první zjištěná hodnota jen nastaví výchozí stav. Při
  ručním zadávání frekvence se cestou může projít i jinými pásmy.
- `band-changed` a `mode-changed` se spouštějí hned při změně. `frequency-changed` se spustí až poté, co se
  frekvence 1 s nemění, takže ladění VFO spustí plugin jednou, ne při každém dotazu; dvě spuštění jsou od sebe
  vždy aspoň 1 s a návrat na naposledy ohlášenou frekvenci během té sekundy nespustí nic.
- `score-changed` se slučuje: spustí se jednou, 3 s po poslední změně, s nejnovějším skóre, takže přepočet nebo
  série QSO dá jedno spuštění; nezměněné skóre se neopakuje. Vyžaduje aktivní závod.
- `qso-edited`, `qso-deleted`, `new-multiplier`, `score-changed` a události pásma, módu a frekvence se pro
  simulátor pileupu nikdy nespouštějí.
- `app-quitting` odstartuje lhůtu pluginů při ukončení (10 s): další pluginy se už nespustí a běžící se po lhůtě
  ukončí, takže ukončení se nikdy nezdrží déle.
- Žádná data nenesou lokální cestu, heslo, API klíč ani URL scoreboardu (jen jeho host).

Příklad — každé QSO do vlastního souboru:

```sh
#!/bin/sh
# plugins/qso-logged/append.sh
python3 -c 'import json,sys; q=json.load(sys.stdin); print(q["time"], q["call"], q["band"])' >> ~/qso.txt
echo "zapsáno"
```
