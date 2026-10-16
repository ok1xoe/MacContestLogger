# ESM – Enter Sends Message

S ESM lze celé spojení odvysílat klávesou **Enter**: podle obsahu
zadávacího okna program pozná, ve které fázi QSO jste, odvysílá
správnou zprávu F-klávesy a ve správnou chvíli QSO zapíše. Chování přesně odpovídá
tabulce z manuálu N1MM+
([ESM Overview](https://n1mmwp.hamdocs.com/setup/function-keys/#ESM_Overview));
DXLog má totéž ([ESM](https://dxlog.net/docs/index.php?title=Getting_started#ESM)).

Funguje v CW (CW klíč, viz [cw-keyer.md](cw-keyer.md)) i ve fonii (hlasový klíč,
viz [voice-keyer.md](voice-keyer.md)).

## Zapnutí

- zaškrtávátko **ESM** vedle Run / S&P v zadávacím okně,
- textový příkaz `ESM` / `NOESM` (také `ESMON` / `ESMOFF`),
- nebo Nastavení → Function Keys → ESM.

Klávesy, které odvysílá příští Enter, mají v mřížce F-kláves **výrazný rámeček**.
Když Enter zároveň zapíše QSO, má rámeček i tlačítko **Log It**.

## Co Enter odvysílá

Předpokládá se obvyklé rozložení zpráv (mají ho výchozí sady): F1 CQ, F2 výměna,
F3 TU, F4 moje značka, F5 jeho značka, F6 QSO B4, F8 again? Jiné rozložení se nastavuje
v **Přiřazení F-kláves pro ESM** (N1MM „Function Key Assignments for ESM“, Nastavení → Function
Keys → ESM): po jedné klávese pro CQ, výměnu, konec QSO, moji značku, jeho značku, QSO B4 a
again. Tabulka níže pak znamená přiřazené klávesy; klávesa CQ je ta zvláštní a
opakování CQ (Alt+R) i zkratky pro vysílání také používají přiřazení.

| Volací značka | Výměna | Run | S&P |
|---|---|---|---|
| prázdná | – | F1 (CQ) | F4 (moje značka) |
| nová, poprvé | prázdná / neplatná | F5 + F2, kurzor do výměny | F4 |
| nová, znovu | prázdná / neplatná | F8 (again?) | F4 |
| nová | platná, výměna ještě neodeslaná | F5 + F2 | F2 + zápis |
| nová | platná, výměna už odeslaná | F3 + zápis | zápis |
| dupe | prázdná / neplatná | F6 (QSO B4) | nic |
| dupe | platná | jako nová | jako nová |

- **Platná výměna** = QSO lze zapsat (v závodě úplná a platná výměna
  podle definice, mimo závod stačí volací značka).
- V režimu Run se **opravená volací značka** (změněná po odeslání F5) odvysílá znovu před TU
  (N1MM „Send corrected call“).
- **F1 přepne na Run** (N1MM: klávesa CQ je zvláštní), i když ji stisknete ručně.
- Smazání volací značky nebo **Wipe** začne QSO znovu od začátku.

## Volby (Nastavení → Function Keys → ESM)

- **S&P: poslat volačku jen jednou** („Big Gun“): první Enter odvysílá F4 a kurzor
  skočí do výměny, další Enter bez výměny odvysílá F8.
- **Run: dupe dělat jako nové QSO** (Work dupes, ve výchozím stavu zapnuto): s dupe se pracuje
  jako s novým QSO místo F6.
- **Opravenou volačku poslat jen v části, která se změnila** (Send partial calls): opravená značka se znovu
  odvysílá jen v části, která se změnila — sufix, když je prefix (až po číslici) stejný (`OK1XOF` → `OK1XOE`
  odvysílá `XOE`), prefix, když je stejný sufix; jinak, nebo s `/`, celá značka.
- **Mezi jeho volačkou a výměnou (CW)** (N1MM „String between his call and exchange“):
  text, který spojí F5 a F2 vysílané společně; ve výchozím stavu mezera.
- **Řazení F-kláves do fronty**: klávesa stisknutá během vysílání zprávy (CW, SSB) se zařadí do fronty a odvysílá se
  celá po ní, jako v N1MM; její tlačítko se rozsvítí, když na ni přijde řada. Esc zastaví vše
  včetně fronty. Vypnuto = nová klávesa zprávu přeruší (dřívější chování).

## AutoSend (CW)

N1MM **CW/PH AutoSend Threshold** (v N1MM Ctrl+Shift+M): **Nastavení → Práh AutoSend (CW)…** nebo Nastavení → Other →
Kroky. V režimu Run a v CW se po napsání zadaného počtu znaků za poslední číslicí značky začne značka
vysílat už během psaní; znaky, které připíšete na její konec, následují jeden po druhém. Další Enter pak odvysílá výměnu
bez značky (značka, kterou jste mezitím opravili, se jako obvykle nejdřív odvysílá znovu). 0 = vypnuto (výchozí). Příklad s 2:
napsání `DL1ABC` odvysílá `DL1AB` po `B`, pak `C`. Fonie podporována není (nahraný hlasový klíč nedokáže
vyslovovat značku písmeno po písmenu během jejího psaní).

## Zásobník volaček

Se [zásobníkem volaček](call-stacking.md) a **klávesou další volačky** (Nastavení → Function Keys → Zásobník
volaček) pokračuje konec QSO v režimu Run další značkou ze zásobníku: tam, kde tabulka uvádí
„F3 + zápis“, odvysílá Enter místo toho klávesu další volačky (opravená značka se i tak odvysílá nejdřív) a její
`{LOGTHENPOP}` zapíše QSO, vezme do pole další značku a odvysílá jí výměnu. Mřížka
F-kláves orámuje klávesu další volačky. S prázdným zásobníkem Enter odvysílá TU a zapíše jako obvykle.

## Klávesy

| Klávesa | Akce |
|---|---|
| **Enter** | krok ESM podle tabulky |
| **mezerník** ve volací značce | skok do výměny (do prvního pole, které není report) |
| **=** | zopakuje naposledy odvysílané zprávy |
| **Esc** | zastaví vysílání, další Esc vymaže pole |

**Trik pro fonii (N2IC):** v režimu Run řeknete značku a výměnu živě a pak místo Enteru stisknete
**mezerník**. Program bere výměnu jako odeslanou, takže po zadání přijaté
výměny Enter rovnou odvysílá TU (F3) a zapíše QSO.

## Limit opakování CQ

Nastavení → Function Keys → Run / S&P → **Nejdelší opakování CQ (min)** (N1MM „Max Repeat /
Dueling CQ duration“): opakování CQ (Alt+R) se samo vypne po tolika minutách
opakování; 0 = bez limitu (výchozí).
