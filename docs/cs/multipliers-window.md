# Okna násobičů

![Okno násobičů DXCC — pracované a chybějící země podle pásem](../img/multipliers.png)

Obdoba **okna Multipliers** v N1MM+
([Key Common Features](https://n1mmwp.hamdocs.com/manual-windows/multipliers-window/#Key_Common_Features))
a DXLog **Worked DXCC**. Otevírají se z menu **Multiplikátory**.

| Okno | Co ukazuje |
|---|---|
| **DXCC** | země (množina typu DXCC), filtr kontinentů |
| **Velké čtverce** | lokátorová pole Maidenhead (`grid_fields`) |
| **ITU / CQ** | zóny |
| **Okresy** | násobiče z přijímaného pole typu `DISTRICT` (např. OK-OM DX) |
| **Section/States** | násobiče z pole `STATE` / `PROVINCE` (státy W, provincie VE, sekce ARRL) |
| **Ostatní** | první dodatečný násobič závodu: IARU HQ, prefixy WPX... |

Každý řádek = jedna hodnota násobiče, sloupce = pásma 160–10 m: **pracováno**,
**spotováno** (nový násobič v clusteru, dvojitý násobič zvlášť), prázdné. Klik na
spotovanou buňku naladí spot. U výčtových množin (země, zóny, okresy, státy) se
zobrazují i nepracované hodnoty, spolu s počtem „pracováno z možných“; u otevřených množin
(prefixy, čtverce) jen pracované.

Klik na spotovanou buňku přepne i mód spotu (N1MM: rádio přejde na pásmo a mód
násobiče), i když je volba *Always use packet spot mode* vypnutá; v závodě s jedním módem mód zůstane.

**Najetí myší na prefix** ukáže zemi, kontinent, zónu CQ a ITU, azimuty krátkou a dlouhou cestou a
vzdálenost (azimut a vzdálenost potřebují zeměpisnou šířku a délku stanice v Nastavení); v okně velkých
čtverců azimut a vzdálenost pole.

**Pravý klik na násobič** (jeho prefix nebo kteroukoli jeho buňku):

- **Pracované stanice a spoty** — každé QSO, které ho započítalo, na všech pásmech, a jeho
  aktuální spoty.
- **Země v zóně** — v oknech zón CQ a ITU země dané zóny.
- **Natočit anténu** — natočí rotátor na azimut krátkou cestou k zemi nebo poli.
- **Nastavit rover QTH** — v oknech okresů a velkých čtverců v závodě s
  rover QTH udělá z násobiče polohu roveru (jako příkaz `ROVERQTH`).

**Menu ⋯** vpravo od legendy:

- **Zobrazená pásma** — které sloupce pásem okno ukazuje, od 160 m až po mikrovlnná
  pásma (výchozí 160–10 m). Pamatuje se pro každé okno.
- **Zobrazené módy** — v závodě s více módy, které z jeho módů okno
  ukazuje. Tam, kde se násobiče počítají podle pásma a módu (například Russian DX), je buňka pracovaná, když
  byl násobič pracován v jednom ze zaškrtnutých módů, a kreslí se jen spoty těchto módů (CW, fonie, digitální
  módy). Výchozí je první mód závodu, jako dříve. Pamatuje se pro každé okno.
- **Zobrazit všechny možné násobiče** — každý násobič množiny; vypnuto
  (výchozí, N1MM *Show only worked & expected*) jen pracované, spotované a očekávané.
- **Očekávané násobiče…** — seznam násobičů, které očekáváte, že uděláte, jeden na řádek
  velkými písmeny tak, jak je okno ukazuje (`CE0X`, ne `CE0/X`; cokoli za prvním slovem, například
  pásmo v MHz z N1MM, se ignoruje). Očekávané násobiče se zobrazují i nepracované, jejich prefix tučně.
  **Importovat… / Exportovat…** čtou a zapisují seznam jako prostý textový soubor; **Exportovat pracované
  násobiče…** uloží násobiče pracované v tomto závodě s jejich pásmy, připravené k pozdějšímu importu.

O tom, do které kategorie násobič patří, rozhoduje typ množiny a typ pole výměny v
definici závodu — nový závod s okresy nebo státy se v oknech objeví sám. Spotované buňky
jsou podporované jen pro DXCC, zóny a čtverce (okres ani stát nelze ze spotu odvodit).

## Mapa lokátorových čtverců (VKV a výš)

Obdoba **Grid Square Map** v N1MM
([VHF and up](https://n1mmwp.hamdocs.com/manual-operating/vhf-and-up-contesting/)). Otevírá se přes
**Multiplikátory → Mapa lokátorových čtverců**.

Okno je matice čtyřznakových čtverců Maidenhead (`JN79`), sever nahoře, se středem ve vlastním
čtverci stanice (Nastavení → Stanice → lokátor); zobrazí se tolik čtverců, kolik se do okna vejde, zeměpisná délka
se ovíjí kolem zeměkoule. Čtverec je **modrý**, když je pracovaný (přijatý lokátor QSO v deníku, nesmazaného, ne
X-QSO), **červený**, když je spotovaný a nepracovaný (lokátor spotu se bere z jeho komentáře, z databáze lokátorů nebo
z callbooku), **hnědý**, když je na seznamu očekávaných a není ani jedno, jinak prázdný. **Pásmo** ukazuje
jen jedno pásmo; výchozí je *Všechna pásma*. Nadpis počítá pracované čtverce,
najetí myší na čtverec ukáže jeho azimut a vzdálenost a počet QSO v něm.

**Pravý klik na čtverec**:

- **Pracované stanice a spoty** — QSO ve čtverci na všech pásmech a jeho spoty.
- **Natočit anténu** — natočí rotátor na azimut ke středu čtverce (potřebuje
  rotátor nastavený v Nastavení; bez něj se nic neotočí).
- **Nastavit rover QTH** — v závodě s rover QTH udělá ze čtverce polohu roveru.
- **Nastavit střed mapy sem** — čtverec se stane středem;
  **Střed na vlastní čtverec** nad mapou se vrátí zpět.
- **Azimut ke středu čtverce** — azimut a vzdálenost od vašeho lokátoru.

**Menu ⋯** obsahuje **Očekávané násobiče…** (očekávané čtverce, jeden na řádek; import a export prostého
textového souboru), **Vymazat očekávané násobiče** (smaže seznam) a **Exportovat pracované násobiče…** — pracované
čtverce s jejich pásmy v MHz (`JN79 144 432`), zpětně čitelné jako seznam očekávaných.

## Přesun násobičů

![Přesun násobičů — kam pozvat stanici](../img/move-multipliers.png)

Obdoba N1MM **Move Multipliers**
([doc](https://n1mmwp.hamdocs.com/manual-windows/the-move-multipliers-window/)) a
DXLog **QSY wizard**. Otevírá se přes **Okno → Přesun násobičů**.

- Projde posledních 25 QSO a u každé stanice ukáže pásma závodu, kde by byla
  **novým násobičem** a nebyla by dupe (`40m +2` = dva nové násobiče).
- **QSY?** požádá o přesun: v CW odvysílá `PSE QSY 7025` — frekvence je moje CQ
  frekvence na cílovém pásmu, jinak poslední frekvence, na které jsem tam byl
  (bez ní jen `PSE QSY 40M`). Ve fonii napoví ve stavovém řádku, co říct.
- **→** naladí rig na tuto frekvenci.
- Vyhodnocuje se jako náhled podle pravidel závodu (dupe, rozsah násobiče), nic se
  nezapisuje.

### Spotované stanice

Zobrazení **Spotované stanice** v témže okně je Move Multipliers z N1MM nad tabulkou
spotů: jeden řádek na spotovanou značku a mód (ne vaše vlastní značka ani vaše vlastní spoty), sloupec na pásmo.
Spotovaná pásma jsou podbarvená. **Zobrazit** volí, co uvádějí buňky pásem:

- **Násobiče** (výchozí) — `M1` jeden nový násobič, pokud se stanice udělá na tomto pásmu, `M2` dva a více,
  prázdné žádný (dupe se nikdy nepočítá). Vypisují se jen stanice s novým násobičem někde.
- **Body QSO** — body, které by QSO přineslo (0 za dupe), stejné v každém sloupci.
- **Počty QSO** — kolikrát už byla značka pracována v tomto módu na každém pásmu (`-` tam,
  kde ne).

S body nebo počty skryje **Rozsah** stanice mimo rozsah jako `0-6` (výchozí),
`3-5` nebo `5`. **Módy** (módy závodu, všechny, CW, fonie, digitální) a **Pásma** (ve výchozím stavu pásma
závodu) volí, co se vypisuje. Volby se pamatují.

Jako v N1MM seznam nesleduje každý spot: sestaví se při otevření zobrazení, při změně volby a
po **Aktualizovat**. Klik na podbarvenou buňku naladí daný spot (frekvenci a mód); klik na
značku přejde na její první spotované pásmo a každý další klik na další. **Shift+klik** dá frekvenci
spotu místo toho do VFO B. **Skrýt řádek** (pravý klik) skryje stanici až do příští aktualizace.
