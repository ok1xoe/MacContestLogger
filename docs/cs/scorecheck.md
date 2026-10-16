# mcl-scorecheck: ověření skóre proti deklarovaným výsledkům

`mcl-scorecheck` je nástroj pro příkazovou řádku, který načte deníky Cabrillo, vyhodnotí QSO
jádrem závodů MacContestLoggeru a zapíše **referenci** (soubor TSV) s vypočteným skóre vedle
hodnoty **`CLAIMED-SCORE`** ze záhlaví deníku. Je to regresní a ověřovací nástroj pro skutečné
deníky: referenci jednoho sestavení lze porovnat s referencí jiného.

## Co dělá

1. U každého deníku přečte ze záhlaví `CONTEST:` (závod), `CALLSIGN:` (vlastní stanice, potřebná
   pro body podle kontinentu) a `CLAIMED-SCORE:` (deklarované skóre).
2. Přiřadí závodu definici (`cabrillo.contestName` v YAML), rozebere řádky `QSO:`
   a vyhodnotí body a násobiče.
   Frekvence na řádku `QSO:` je buď v kHz, nebo od 50 MHz výš označení pásma podle Cabrilla
   (`50`, `144`, `222`, `432`, `902`, `1.2G`, `2.3G` … `241G`).
3. Za každý deník zapíše jeden řádek TSV se stavem, počtem QSO, body, násobiči,
   vypočteným a deklarovaným skóre.

Nástroj záměrně deníky neklasifikuje (OK / těsně / selhalo) ani nekreslí histogramy. Jen
vyrábí data; vypočtený a deklarovaný sloupec porovnejte nástrojem podle svého výběru
(tabulkový procesor, `awk`, ...).

## Předpoklady

- Definice závodů: adresář s `contests/*.yaml` a `multipliers/*.yaml`
  (repozitář obsahuje `contest-data/` jako výchozí základ).
- Data DXCC v `~/dxcc-json/`:
  - **`cty.dat`** (výchozí, doporučené: přesné, zvládá speciální prefixy a výjimky značek),
  - případně **`dxcc.json`** (méně přesné).
- Umístění souboru DXCC lze změnit přepínačem `--dxcc-file`.

## Sestavení a spuštění

Nástroj je spustitelný cíl SwiftPM (`mcl-scorecheck`):

```bash
swift build -c release

# a single log
swift run -c release mcl-scorecheck /path/to/log.cbr --contest-data contest-data

# a directory (recursive; only .log / .cbr / .cabrillo files)
swift run -c release mcl-scorecheck /path/to/directory --contest-data contest-data

# a large batch: 8 threads, output to a file
swift run -c release mcl-scorecheck /path/to/logs --contest-data contest-data --jobs 8 --out reference.tsv
```

## Volby

| Volba | Význam | Výchozí |
|---|---|---|
| `<file\|directory>` | vstup: jeden deník (libovolná přípona), nebo adresář zpracovaný rekurzivně | povinné |
| `--contest-data <dir>` | adresář s `contests/` a `multipliers/` | povinné |
| `--dxcc cty\|json` | zdroj DXCC: `cty.dat` nebo `dxcc.json` | `cty` |
| `--dxcc-file <path>` | cesta k `cty.dat` nebo `dxcc.json` | `~/dxcc-json/cty.dat` nebo `~/dxcc-json/dxcc.json` |
| `--jobs N` | počet vláken; pořadí výstupu je vždy stejné | `1` |
| `--set <name>` | hodnota řádku záhlaví `set` | název vstupu |
| `--out <file>` | zapisovat do souboru místo na standardní výstup | standardní výstup |
| `-h`, `--help` | vypíše nápovědu | |

Po dokončení nástroj vypíše na standardní chybový výstup jednořádkové shrnutí, například
`1234 logů (ERR=3 OK=1229 UNREADABLE=2) za 4.1 s` (počty deníků podle stavu a uplynulý čas).

## Výstup: reference TSV

Výstup začíná řádky záhlaví `# key: value`, po nichž následuje jeden datový řádek na deník
v pořadí podle cesty k souboru:

```
# format: scorecheck-reference 1
# set: logs-2025
# implementation: mcl-scorecheck (swift)
# contest-data-sha256: ...
# dxcc-source: cty
# cty.dat-sha256: ...
# logs: 1234
# columns: key file status contest qsoCount qsoPoints multTotal multByGroup computed claimed unresolvedCount skipReason errorClass error
```

Záhlaví přesně zaznamenává, z čeho byl výsledek spočten (hashe dat závodů a souboru DXCC,
počet deníků), takže dvě reference jsou srovnatelné jen tehdy, když se tyto řádky shodují.

Datové řádky jsou oddělené tabulátory, se sloupci uvedenými v řádku `columns`:

| Sloupec | Význam |
|---|---|
| `key` | prvních 16 hexadecimálních znaků SHA-256 obsahu deníku (identifikuje deník bez ohledu na jeho název) |
| `file` | název souboru |
| `status` | `OK` (vyhodnoceno), `ERR` (deník nešlo vyhodnotit, např. neznámý závod), `EXC` (výjimka během vyhodnocení), `UNREADABLE` (soubor nešel přečíst) |
| `contest` | závod ze záhlaví |
| `qsoCount`, `qsoPoints` | počet QSO a body za QSO |
| `multTotal` | celkový počet násobičů |
| `multByGroup` | násobiče po skupinách, `group=count` oddělené čárkami |
| `computed` | vypočtené skóre |
| `claimed` | `CLAIMED-SCORE` ze záhlaví (`\N`, když chybí) |
| `unresolvedCount` | počet značek, které nešlo přiřadit k entitě DXCC |
| `skipReason` | proč deník vynechat ze statistik (`checklog`, chybí `CLAIMED-SCORE`), jinak `\N` |
| `errorClass`, `error` | třída výjimky a chybová zpráva (`\N`, když žádná není) |

Textové hodnoty jsou escapované: zpětné lomítko se stane `\\`, znaky mimo tisknutelné ASCII
`\uXXXX` a chybějící hodnota je `\N`. Volný text z deníku delší než 80 znaků se nahradí
`#sha256:` a hashem, takže reference nenese text z deníků.

## Poznámky

- Deníky bez `CLAIMED-SCORE` i checklogy se přesto vyhodnotí; sloupec `skipReason` říká,
  že je máte z jakéhokoli porovnání vynechat.
- Zbytková odchylka kolem 1 % od deklarovaného skóre se dá čekat (hraniční kontinenty a zóny,
  maritime mobile, drobné chyby v deníku protistanic). V CQ WW se vlastní entita DXCC
  počítá jako násobič (0 bodů).
