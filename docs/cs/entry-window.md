# Zadávací okno

Zadávací okno je hlavní okno: pruh s frekvencí, tlačítka pásmo × mód, pole QSO, nápovědy, zprávy F-kláves
a akční tlačítka. Klávesy jsou uvedeny v [klávesových zkratkách](keyboard-shortcuts.md).

## Kontextové menu (pravé tlačítko)

Klik pravým tlačítkem kamkoli do zadávacího okna (mimo textová pole) otevře menu zobrazení jako v N1MM:

- **zobrazené části** — **Tlačítka pásem**, **Nápovědy u frekvence (callbook, call history…)** (call history,
  worked before…), **Azimut a vzdálenost**, **Řádek Run/S&P a ESM**, **Rychlost CW**, **Tlačítka F1–F12**
  a **Tlačítka Wipe, Log It, Edit…**. Skrytá část okno zmenší.
- **Klik na tlačítko pásma mění pásmo** (N1MM *Band Button Left Click Enabled*): vypnuto = tlačítka pásem jen ukazují
  pásma a jejich barvy, klik nic nedělá.
- **Zobrazená pásma** — která pásma mají tlačítko.
- **Hodiny UTC** (N1MM *Show GMT Time*) — hodiny UTC v pruhu s frekvencí.
- **Informace uživatele (call history)** (N1MM *Show User Information*) — řádek call history pro napsanou značku
  (také Nastavení → Závod).

Volby se ukládají s nastavením.

## 222 MHz a 902 MHz

Pásma Regionu 2 222 MHz (1,25 m, 222–225 MHz) a 902 MHz (33 cm, 902–928 MHz) jsou samostatná pásma,
v pořadí frekvencí mezi 2 m a 70 cm a mezi 70 cm a 23 cm (ADIF `1.25m` a `33cm`; Cabrillo `222` a
`902`; EDI `222 MHz` a `902 MHz`; `{OTHERBAND}` a pásmo N1MM UDP `222`/`902`). Jejich tlačítka pásem (`1.25m`,
`33cm`) se objeví v závodech, jejichž definice je uvádí, například v závodech ARRL VHF, a filtr spotů DX clusteru
je má ve skupinách VHF a UHF. Kontrola skóre (`mcl-scorecheck`) čte označení pásem Cabrilla
od `50` výš (`50`, `144`, `222`, `432`, `902`, `1.2G` … `241G`).

## Pásma nad 10 GHz

Kromě 23 cm – 3 cm zná MCL stejně jako N1MM milimetrová pásma až do 241 GHz: 24, 47, 76, 122, 134 a 241 GHz
(ADIF `1.25cm`, `6mm`, `4mm`, `2.5mm`, `2mm`, `1mm`; Cabrillo `24G` … `241G`; EDI `24 GHz` … `248 GHz`). Jejich tlačítka
pásem (s popisky `24G` … `241G`) se objeví v závodech, jejichž definice je uvádí — přidejte je do definice
v editoru definic (`bands: [..., 3cm, 1.25cm, 6mm]`); dodávané definice se nemění.

## Pravý klik na tlačítko pásma

Jako v N1MM působí pravý klik (nebo Control+klik) na tlačítko pásma/módu okamžitě:

- **bez síťového deníku** nebo s prázdným polem značky: rig přejde na toto pásmo a mód — na poslední frekvenci
  použitou na pásmu, jinak na začátek segmentu módu — a značka **naposledy zapsané stanice** se tam uloží
  do bandmapy (lokální spot, do clusteru se nic neposílá). Určeno pro VKV závody, kde se jedna stanice
  posouvá postupně přes mnoho pásem.
- **v síťovém deníku s napsanou značkou**: značka se **předá** síťové stanici, která pracuje na tomto pásmu (na její
  pass frekvenci z Alt+Z, jinak na její vlastní frekvenci), jako Ctrl+Alt+P. Není-li na pásmu žádná stanice, oznámí to stavový řádek.

Pravý klik funguje i tehdy, když je *Klik na tlačítko pásma mění pásmo* vypnuté (tato volba se týká jen levého kliku).
VoiceOver jej nabízí jako akci *Poslední stanici na toto pásmo*.

## Barvy napsané značky

V závodě se napsaná značka kontroluje na aktuálním pásmu a na každém tlačítku pásma:

| Barva | Význam |
|---|---|
| zelená | dvojitý (nebo vyšší) násobič |
| červená | násobič |
| modrá | nové QSO bez násobiče |
| šedá | dupe |

Text volací značky má barvu aktuálního pásma (dupe si ponechá červený rámeček a štítek DUPE); tlačítka pásem
dostanou rámeček v barvě značky na daném pásmu. Pod frekvencí ukazuje řádek azimutu zemi značky
a stejně jako stavový řádek N1MM azimuty krátkou a dlouhou cestou a vzdálenost krátkou cestou
(Nastavení → Stanice: vaše zeměpisná šířka a délka; bez nich jen země).

## Úprava QSO

- **Ctrl+Y**, tlačítko **Edit** nebo **Úpravy → Upravit poslední spojení…** (N1MM *Edit Last Contact*) otevřou
  naposledy zapsané QSO v dialogu úprav: čas (UTC, `yyyy-mm-dd hh:mm:ss`), volací značka, frekvence v kHz (pásmo
  se podle ní řídí), mód, reporty, pořadová čísla, výměna, poznámka, operátor a X-QSO. **Uložit** (nebo Enter) QSO
  uloží a skóre se přepočítá; Esc nebo **Zrušit** zavře dialog beze změny. Pole, které nelze přečíst
  (neznámý mód, chybný čas), se vypíše pod poli a dialog zůstane otevřený.
- **Úpravy → Upravit rozpracované spojení…** (N1MM *Edit Current Contact*) otevře QSO, které právě píšete: volací značku,
  frekvenci, mód, odeslaný report, přijímaná pole závodu (nebo RST a výměnu při volném logování) a poznámku.
  **Uložit** vrátí hodnoty do zadávacího okna; nic se nezapíše.
- Starší QSO se upravují v [okně Přehled spojení](log-window.md) nebo pomocí QuickEdit.

## QuickEdit

QuickEdit z N1MM upravuje zapsaná QSO přímo v zadávacím okně, bez dialogu:

- **Ctrl+Q** vloží do polí naposledy zapsané QSO; každé další **Ctrl+Q** jde o jedno QSO zpět, **Ctrl+A** o jedno
  QSO vpřed. Pole zesvětle zmodrají a pruh nápověd ukazuje *QuickEdit n/m* (n = o kolik QSO zpět).
- Opravte volací značku, frekvenci, mód, reporty nebo výměnu a stiskněte **Enter** (nebo **Log It**);
  QSO se uloží a skóre se přepočítá. Nic se nezapíše jako nové QSO.
- **Esc** (nebo **Wipe**) ponechá QSO beze změny.
- V obou případech se do zadávacího okna vrátí to, co jste psali před Ctrl+Q. Dokud je QuickEdit zapnutý, pole
  frekvence nesleduje rig a pípnutí dupe je ztlumené.
- Položky menu jsou **Úpravy → QuickEdit (o QSO zpět / vpřed)**.

## Hledání volací značky

**Ctrl+F** otevře okno Přehled spojení s QSO volací značky napsané v poli značky. Další stisk **Ctrl+F**
se stejnou značkou (N1MM *Find Again*) vybere v okně Přehled spojení další z těchto QSO a po
posledním začne znovu od prvního.

## Při psaní a zápisu

- **`?` ve značce** — když se kurzor vrátí do pole značky (mezerník, Tab, Esc…), `?` se označí, takže
  ho další klávesa nahradí; při dvou a více `?` se označí text od prvního do posledního (`DL?K?A`).
  Každé jiné pole se při vstupu kurzoru označí celé, takže pořadové číslo prostě přepíšete.
- **Mazání automaticky doplněné výměny** — s *Nastavení → Závod → Při změně volačky smazat výměnu doplněnou
  z call history nebo spotu* změna značky smaže hodnoty výměny, které doplnila call history nebo spot
  (hodnoty, které jste napsali, zůstanou).
- **Varování k pořadovému číslu** — když byla pro QSO odeslána zpráva s pořadovým číslem (`#`, `{NR}`, `{EXCH}`)
  a QSO se zapíše s jiným číslem (mezitím si ho vzala jiná stanice sítě), stavový řádek
  ohlásí *Pozor: odesláno číslo …, zapsáno …*.
- **Odladění před zápisem** — napsaná volací značka se při odladění uloží do bandmapy
  ([self-spot](dx-cluster.md)) a stavový řádek upozorní, že QSO nebylo zapsáno.
- **Odeslané CW** — s *Nastavení → CW klíč → Zobrazovat odesílané CW ve stavovém řádku* ukazuje stavový řádek
  text každé CW zprávy při jejím odesílání (`CW: 5NN 001`).

## Hlášení pro nevidomé operátory (VoiceOver)

Obdoba programových hlášení N1MM pro nevidomé operátory. **Nastavení → Hlášení pro nevidomé (VoiceOver)**
(zaškrtávací položka, ve výchozím stavu vypnutá, ukládá se) způsobí, že deník oznamuje
prostřednictvím VoiceOveru, jeho vlastním hlasem a v jazyce uživatelského rozhraní:

- napsaná značka se stane **dupe** („Dupe“) nebo **novým / dvojitým násobičem** („Nový násobič“, „Dvojitý
  násobič“) — jednou při každé změně, ne při každém stisku klávesy;
- QSO, které ještě **nelze zapsat**: neúplná výměna („Neúplná výměna, QSO nezapsáno“) nebo chybějící čas
  při dodatečném zadání („Chybí čas QSO“);
- zapnutí nebo vypnutí **splitu** rigu („Split zapnut“ / „Split vypnut“).

Hlášení jsou oznámení zpřístupnění: aby byla slyšet, musí běžet VoiceOver, a samotný deník
pro ně nikdy neotevírá zvukové zařízení.
