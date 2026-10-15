# Hlasový klíč (DVK) pro SSB

Ve fonických módech (SSB, AM, FM) vysílají funkční klávesy F1–F12 nahrané hlasové
zprávy: klíč zaklíčuje vysílač, přehraje wav soubory do jeho vstupu a
odklíčuje. Chování odpovídá N1MM+
([Function Keys – SSB](https://n1mmwp.hamdocs.com/setup/function-keys/#Recording_on_the_Fly))
a DXLogu
([Digital Voice Keyer](https://dxlog.net/docs/index.php?title=Menu_Options#Digital_Voice_Keyer)).

## Nastavení

**„Nastavení → Audio"**
- **Výstup (vysílač):** zvukové zařízení vedoucí do vstupu vysílače,
  typicky „USB Audio CODEC" rigu nebo rozhraní.
- **Vstup (nahrávání):** mikrofon, kterým se nahrávají zprávy.
- **Výstup rádia 2 (SO2R):** v SO2R jdou zprávy rádia 2 do tohoto zařízení (obdoba
  zvukové karty pro každé rádio v N1MM); prázdné = stejný výstup jako rádio 1.
- **Levý / pravý kanál (SO2R, Nastavení → SO2R → Hlasové zprávy rádia 1 / 2):** zprávy rádia mohou hrát
  jen v levém nebo jen v pravém kanálu výstupu (druhý kanál je tichý), takže jedna stereo zvuková karta
  napájí oba rigy (směrování DVK jako v N1MM). Výchozí: oba kanály, tak jak bylo nahráno.
- **Hlasitost zpráv (%):** úroveň přehrávání zpráv (100 = tak, jak bylo nahráno).
- **Test výstupu (tón 1 kHz):** jednosekundový tón na výstupu v úrovni zpráv pro
  nastavení vybuzení vysílače. Jde jen do zvukové karty: PTT se nezaklíčuje.
- **Měřit úroveň vstupu** (skupina Příjem): měřič uloženého vstupu přijímače
  (zařízení vodopádu a CW dekodéru) v dBFS, dokud je zapnutý.
- **PTT přes CAT:** klíčuje se příkazem rigctld `T 1` / `T 0`; transceiver
  musí být připojený. Bez CAT nebo s vypnutou volbou klíčuje
  VOX vysílače.
- **Prodleva PTT:** kolik milisekund po zaklíčování začne zvuk, aby relé
  stihlo přepnout. Výchozí je 150 ms.
- **Max. délka nahrávky:** pojistka, která zapomenutou nahrávku ukončí sama.
- **Adresář wav:** prázdné pole znamená `~/Library/Application Support/MacContestLogger/wav`.
- **Písmena a číslice:** podadresář pro hlášení volačky a čísel,
  výchozí je `LettersFiles/{OPERATOR}`.
- **Pokročilé hlášení pořadových čísel** (N1MM): když adresář písmen obsahuje
  `0.wav`…`19.wav`, `20.wav`, `30.wav`…`90.wav`, `HUNDRED.wav` a `THOUSAND.wav`, `#` se
  hlásí slovy (123 = „one hundred twenty three": `1`, `HUNDRED`, `20`, `3`). Chybí-li kterýkoli
  z nich, hlásí se jako dřív po číslicích; záložka Audio ukáže, co platí.

**„Nastavení → Function Keys"**: zprávy F1–F12, zvláštní
sada pro **Run** a pro **S&P**. Která sada se použije, určuje přepínač
Run/S&P v zadávacím okně. Tlačítko „Výchozí zprávy"
obnoví sadu podle N1MM „SSB Default Messages".

## Formát zprávy

Zpráva je seznam položek oddělených čárkou (stejně jako v souborech `.mc` z N1MM):

| Položka | Význam |
|---|---|
| `{OPERATOR}/CQ.wav` | wav soubor relativně k adresáři wav. `{OPERATOR}` (také `{WAVDIR}`) se nahradí volačkou operátora u klíče, takže po `OPON` hrají nahrávky jeho hlasem |
| `a.wav,b.wav` | více souborů za sebou |
| `!` | volačka protistanice z pole volačky |
| `#` | odesílané pořadové číslo |
| `*` nebo `{MYCALL}` | moje volačka |
| `@` | frekvence v kHz |
| prázdná zpráva / `empty.wav` | nic nevysílá |

Příklad výměny pro CQ WPX: `{OPERATOR}/59.wav,#`, tedy nahrané „five
nine" a za ním hlášené pořadové číslo.

U maker `!`, `#`, `*` a `@` se volačka a čísla skládají z
nahrávek v adresáři písmen:
- `A.wav`...`Z.wav` a `0.wav`...`9.wav` pro jednotlivá písmena a číslice;
- `stroke.wav` pro „/", `query.wav` pro „?", `point.wav` pro desetinnou tečku;
- `strokep.wav` pro „/P" (volitelně).

Nahraný úsek má přednost před jednotlivými písmeny, například
`DL1.wav` + A + B + C pro volačku DL1ABC. Wav soubory zpráv proto nepojmenovávej
tak, aby se název mohl objevit uvnitř volačky. Dobře funguje třeba `CQ_RUN.wav`
místo `CQ.wav`.

Pokud ve zprávě chybí soubor, klíč ji přesto odvysílá bez chybějících
částí. Chybějící soubory se vypíší ve stavovém řádku.

## Řídicí makra

Stejně jako v N1MM+ může zpráva mezi wav soubory obsahovat i řídicí makra. Ta se
provedou, nikdy se nepřehrávají jako soubory (stejná sada a význam jako v
[cw-keyer.md](cw-keyer.md)):

| Makro | Akce |
|---|---|
| `{LOG}` | zaloguje QSO |
| `{WIPE}` | vymaže pole |
| `{RUN}` / `{S&P}` | přepne režim |
| `{CLEARRIT}` / `{RITCLEAR}` | vynuluje RIT |
| `{CQFREQ}` | skok na CQ frekvenci (a vymazání polí) |
| `{NOSPLIT}` | vypne split |
| `{SPOTME}` | spotne vlastní stanici do DX clusteru na frekvenci zadávacího okna, s [komentářem spotu](dx-cluster.md#spot-comment-spotting-sp-qsos-and-special-calls) (`CQ`, když je prázdný); ověř, že pravidla závodu vlastní spoty dovolují |
| `{F1}`...`{F12}` | vloží zprávu jiné F-klávesy ze stejné sady (řetězení, nejvýš 3 úrovně) |
| `{CQ}`, `{QSYCQ}`, `{EXCHSENT}`, `{CTRLHOME}`, `{FORCELOG}`, `{FORCELOGNOTE}`, `{SPACE}` | jako v [cw-keyer.md](cw-keyer.md#more-macros-n1mm) |
| `{COMMENT text}` | přidá text do poznámky QSO; provede se při startu zprávy |
| `{VARYMSG1&a.wav&b.wav&N&}` | střídavá zpráva jako v CW (`{VARYMSG2 &TU.wav&TUMYCALL.wav&2&}` přehraje delší poděkování po každém druhém QSO) |
| `{END}` | ukončí zprávu: žádný soubor za ním se nepřehraje; jeho makra se provedou, jakmile zpráva dohraje do konce (ne po Esc nebo chybě) |
| `{PGUP}`, `{PGDN}`, `{FREQUP}`, `{FREQDN}`, `{TURNROTOR}`, `{LONGPATH}`, `{STOPROTOR}`, `{DIGQTCR}`, `{DIGQTCS}`, `{CAT…}`, `{CATDELAY n}`, `{ANTRXnTOGGLE}`, `{AUXANTSEL nn}`, `{TELNET cmd}` | jako v [cw-keyer.md](cw-keyer.md#actions-after-the-message-rig-and-station-macros) |
| `{TX}` | PTT rigu zapnuté až do Esc (ruční PTT s pojistkou 30 s) |
| `{SETWAVDIR text}` | `{WAVDIR}` cest, použije se dřív, než se vyhledají soubory této zprávy |
| `{LOGTHENPOP}`, `{LOGTHENNEXT}`, `{SOCALLSTACK}`, `{STACKANOTHER}`, `{CLRSTACK}` | [zásobník volaček](call-stacking.md); provede se **před** přehráním zprávy, takže `!` a `{F5}` už znamenají další volačku |

Pořadí: položky se provádějí zleva doprava. Makro se provede, jakmile dohraje zvuk před
ním (vysílač zůstává zaklíčovaný), takže `tu.wav,{LOG}` zaloguje až po odvysílání
„thank you". Makra před prvním wav souborem se provedou hned, ještě než se vysílač
zaklíčuje; zpráva jen z maker (`{WIPE}`) vysílač vůbec nezaklíčuje.
Esc zprávu zastaví a makra za místem, kde se zastavila, se neprovedou
(po přerušené zprávě žádný `{LOG}`); totéž platí po chybě zvuku.

Jakákoli jiná položka `{...}` (například `{KEYBOARD}`) se neprovede a nehledá
se jako soubor; stavový řádek na ni upozorní.

## Nahrávání a výběr zpráv v Nastavení

V **„Nastavení → Function Keys"** se zobrazenou sadou **SSB** má každá klávesa, jejíž zpráva je přesně jeden wav soubor
(například `cq.wav` nebo `{OPERATOR}/CQ.wav`), řádek se souborem, který přehrává (název a délka, nebo „soubor
chybí"), a tato tlačítka:

- **Nahrát**: nahrává ze vstupního zařízení nastaveného v Nastavení → Audio, téhož, které používá Ctrl+Shift+F;
  tlačítko se změní na **● Stop** s uplynulými sekundami. Nahrávání skončí samo po „Max. délka nahrávky"
  ze záložky Audio, nejvýš po 60 s. Ukládá se jako 16bitové mono 22 050 Hz a soubor nahradí, jen když
  skončí úspěšně. Poprvé si macOS vyžádá přístup k mikrofonu; pokud ho odmítneš, povol ho v Nastavení
  systému → Soukromí a zabezpečení → Mikrofon.
- **Přehrát**: přehraje soubor na výchozím výstupu počítače, abys ho mohl zkontrolovat. Nikdy nezaklíčuje rig
  a nikdy nepoužije výstupní zařízení klíče.
- **Vybrat WAV…**: zkopíruje zvukový soubor z disku do souboru klávesy (na originál se neodkazuje,
  takže přesun nebo záloha složky wav dál funguje). Wav, který klíč umí přehrát (PCM, float, A-law nebo μ-law,
  mono nebo stereo, 4–192 kHz), se zkopíruje beze změny; AIFF, CAF, MP3, M4A a ostatní wav soubory se převedou na
  16bitový mono wav 22 050 Hz. Soubory nad 64 MB, delší než 5 minut, tiché nebo v neznámém formátu se odmítnou
  se zprávou.
- **Smazat**: po potvrzení soubor smaže.

Nahrání nebo kopírování přes existující soubor si nejdřív vyžádá potvrzení. Všechna tlačítka jsou odmítnuta, dokud
hlasový klíč přehrává nebo nahrává nebo se vysílá CW či digitální zpráva, a F-klávesy klíče jsou odmítnuty, dokud
se v Nastavení nahrává zpráva.

**Kam se soubory ukládají:** přesně tam, kde je hlasový klíč hledá. Cesta je text zprávy vyhodnocený
vůči adresáři wav (`{OPERATOR}` nahrazený volačkou operátora, relativní cesta pod adresářem
wav, chybějící složka se vytvoří), podle stejného pravidla jako u Ctrl+Shift+F. Bere se z textů a
z „Adresář wav" zobrazeného v dialogu, takže soubor nahraný před stiskem „Použít" už leží tam, kde ho klíč
potom bude hledat. **Otevřít složku ve Finderu** otevře adresář wav.

Zpráva může kombinovat jeden zvukový soubor s řídicími makry (`cq.wav,{LOG}`, `{WIPE},cq.wav,{RUN}`; také `{S&P}`,
`{END}`, `{F1}`…`{F12}`, `{CLEARRIT}`, `{RITCLEAR}`, `{CQFREQ}`, `{NOSPLIT}`): nahrává se ten jeden soubor. Klávesa se
k nahrávání nenabídne, když je její zpráva prázdná, má více zvukových položek (`a.wav,b.wav`), je to řeč (`[text]`)
nebo obsahuje jen makra (`!`, `#`, `*`, `@`, `{MYCALL}`, samotná řídicí makra); řádek uvede proč. `{OPERATOR}` potřebuje volačku operátora (příkaz `OPON`).

## Ovládání

| Klávesa | Akce |
|---|---|
| **F1–F12** nebo klik na tlačítko | odešle zprávu. Nové stisknutí přeruší běžící zprávu |
| **Esc** | zastaví vysílání. Až další Esc vymaže pole (jako v N1MM) |
| **Ctrl+Shift+F1...F12** | spustí nahrávání zprávy klávesy do jejího wav souboru; další stisk nebo Esc nahrávku uloží |

Nahrát jde jen zprávu s jedním wav souborem („Recording on the Fly" v
N1MM). Nahrávka se ukládá jako 16bitové mono 22 050 Hz a přepíše původní
soubor až po úspěšném dokončení.

Tlačítko právě vysílané zprávy se v mřížce rozsvítí a
nahrávaná zpráva ukazuje ●. V CW vysílají F-klávesy CW klíčem (viz
[cw-keyer.md](cw-keyer.md)); v digitálních módech jsou zatím vypnuté.

**macOS:** když F-klávesy ovládají jas nebo hlasitost, drž **fn**, nebo zapni
Nastavení systému → Klávesnice → „Používat klávesy F1, F2 atd. jako standardní funkční klávesy".

## Zatím není k dispozici

- automatické opakování CQ (N1MM Alt+R),
- hlasový klíč vestavěný v rigu nebo v microHAMu,
- nahrávání celého závodu,
- převod textu na řeč.

## Syntéza řeči (TTS)

Obdoba **Text-to-speech** v N1MM (Piper / SAPI) — na Macu přes
vestavěný `say`. Položka v **hranatých závorkách** ve zprávě F-klávesy se namluví:

```
[CQ contest *], cq-end.wav
[! five nine #]
```

- `*` moje volačka, `!` volačka z pole, `#` pořadové číslo, `@` frekvence —
  volačky a čísla se hláskují hláskovací abecedou NATO (Oscar Kilo One...),
- hlas se volí v **„Nastavení → Audio → Syntéza řeči (TTS)"**, např. `Daniel`, `Samantha`, česká `Zuzana`; seznam vypíše
  `say -v ?` v Terminálu,
- namluvené zprávy se ukládají do `.tts-cache` v adresáři wav — první
  přehrání trvá asi sekundu, další jdou z cache,
- uvnitř `[...]` nepoužívej čárku (odděluje položky zprávy); TTS lze
  kombinovat s nahranými wav soubory.
