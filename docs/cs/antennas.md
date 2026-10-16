# Antény a band decoder

Obdoba N1MM+ **Configurer → Antennas** a band decoderu.

## Tabulka antén

**„Nastavení → Antennas“**: každá anténa má

| Sloupec | Význam |
|---|---|
| **Kód** | hodnota pro anténní přepínač / band decoder (0–15) |
| **Anténa** | název (v zadávacím okně se zobrazuje jako `ANT ...`) |
| **Pásma** | `20m,15m` nebo v MHz `14, 21` |
| **Sektor** | kam anténa míří, `270-360`, přes sever `300-60`; prázdné = všesměrová |
| **Rotátory** | N1MM *Rotor Description*: rotátor(y), které anténou otáčejí, podle jména; víc oddělených čárkou otáčí společně **stackem**; prázdné = výchozí rotátor |
| **Offset** | o kolik stupňů hlavní lalok míří vedle směru rotátoru (rotátor se natočí na směr − offset) |
| **Obousm.** | SteppIR nebo dipól: rotátor použije ten konec antény, který je blíž, takže se otočí nejvýš o 180° |

Jméno rotátoru, které nastavení nezná (viz [Více rotátorů](#více-rotátorů-předvolby-a-meze)), je rotátor
rotátorového programu: Alt+J mu pošle UDP zprávu N1MM Rotor s tímto jménem, offsetem a příznakem obousměrnosti.

## Přepínání

- Po **změně pásma** se vybere anténa pro toto pásmo; má-li pásmo
  více antén, rozhodne **azimut** k právě psané volací značce (anténa,
  do jejíhož sektoru míří), jinak první v tabulce.
- Sektor **obousměrné** antény pokrývá i její zadní konec (pevný dipól s hlavním směrem `30-90` slouží i pro 210–270).
- **Automatická volba podle směru** (N1MM *Auto-select antenna based on azimuth*, výchozí vypnuto): se
  zaškrtnutým **„Vybírat anténu podle směru ke stanici i po zadání volačky“** pod tabulkou Mezerník v poli volačky
  znovu vybere anténu pásma podle směru k zadané stanici — šikovné u pevných směrovek.
- **Ctrl+Alt+A** přepne na další anténu pásma (lze přemapovat).
- Výstupy:
  - **OTRSP řadič** (SO2R box) — `AUX<rig><code>`, BCD pro band decoder,
  - volitelně **konektor rigu** přes hamlib (`Y`), kódy 1–4 = ANT1–ANT4
    (zaškrtávátko pod tabulkou).

## Rotátor

Obdoba programu N1MM **Rotor**, přes hamlib **rotctld**:

1. spusťte `rotctld -m <model> -r /dev/cu.usbserial-… -t 4533` (model z `rotctl -l`),
2. **„Nastavení → Antennas → Rotátor“**: host a
   port (prázdný host = bez rotátoru),
3. **„Okno → Rotátor“** ukazuje aktuální azimut (ručička,
   čtená každé 2 s) a azimut k volací značce z pole (druhá ručička).

| Ovládání | Akce |
|---|---|
| **Alt+J** / tlačítko **„Na volačku“** | natočit na volací značku z pole (jinak na poslední QSO) |
| **Alt+L** / **„Dlouhá cesta“** | opačný směr |
| azimut + **„Natočit“** | na zadaný azimut |
| **Ctrl+Alt+J** / **„Stop“** | zastavit |

Azimut k volací značce se počítá z lokátoru stanice („Nastavení →
Stanice“) a polohy země podle DXCC. Je-li známý **lokátor** (grid)
stanice — z pole lokátoru v závodě (VKV) nebo z call history —, počítá se
směr místo toho od vašeho lokátoru k tomuto lokátoru.

- **Směr v poli volačky**: napište do pole volačky číslo 0–360 a stiskněte
  **Alt+J** — rotátor se natočí na tento směr (klávesa dlouhé cesty přičte 180°).
- **Bandmapa a Dostupné multiplikátory**: pravý klik na spot → **„Natočit rotátor na …“**
  (N1MM *Turn Rotor*); je-li známý lokátor spotu, použije se (komentář spotu, databáze
  lokátorů, callbook).
- Je-li vybraná anténa, natočení použije její rotátor(y), offset a příznak obousměrnosti
  (viz tabulka antén výše).

### Více rotátorů, předvolby a meze

Obdoba nastavení programu **N1MM Rotor**: **„Nastavení rotátoru…“** v horní liště
okna Rotátor.

| Část | Význam |
|---|---|
| **Rotátory** | až 16 pojmenovaných rotátorů: jméno, host a port rotctld (prázdný host = jen UDP zpráva s tímto jménem), **kalibrace** (stupně přičtené ke čtené poloze; z odesílané se odečtou) a **meze** řadiče (Min/Max: `0–360`; `0–450` pro rotátor s přesahem, který pak volí kratší otočení; `-180–180` pro doraz na jihu; omezený rozsah natočí na bližší mez a oznámí to) |
| **Předvolby F1–F10** | směry deseti tlačítek předvoleb; je-li okno Rotátor aktivní, stiskne je **F1–F10** |
| **Rotátory ze sítě** | výchozí vypnuto; zobrazuje směry, které v síti vysílá N1MM Rotor (UDP port 13010, řádky `<rotor> @ <desetiny stupně>`); jen přijímá |

S pojmenovanými rotátory dostane okno Rotátor **výběr rotátoru**: kompas, pole,
předvolby i Stop pracují s vybraným rotátorem. Stop zastaví i rotátory aktuální antény.

## Transvertory

Obdoba N1MM **transverter offset**. **„Nastavení → Hardware →
Transvertory“**: název, rozsah mezifrekvence (IF) rigu
(kHz) a offset (kHz); zaškrtávátko ho zapne.

- Příklad: 2 m přes rig na 10 m: IF 28000–30000, offset 116000 → rig na
  28,300 kHz = 144,300 kHz v deníku, bandmapě, Cabrillu i ve spotech.
- Ladění (klik na spot, QSY, pásmo, split, VFO B) na 144,300 pošle do rigu 28,300.
- Frekvence mimo rozsah IF zapnutých transvertorů projdou beze změny; vypnutý
  transvertor = rig se chová normálně (10 m jsou zase 10 m).

## Nožní spínač

Obdoba N1MM **Footswitch**. Spínač se připojí na převodník USB-RS232
mezi výstupní a vstupní řídicí linku: **RTS→CTS** (nebo DTR→DSR,
DCD). **„Nastavení → Hardware → Nožní spínač“**:
port, linka a akce:

| Akce | Co dělá |
|---|---|
| **PTT** | drží vysílač (CAT PTT), dokud je stisknutý — fone bez VOX |
| **ENTER** | jako Enter v aktivním zadávacím okně (s ESM pošle zprávu podle stavu) |
| **F1** | pošle CQ (F1) |
| **F2**, **F3**, **F4**, **F11**, **F12** | pošle zprávu dané funkční klávesy |
| **ESC** | zastaví vysílání, jako Esc (vypne se i opakování CQ) |
| **SWITCH_RADIOS** | SO2V / SO2R: přesune fokus zápisu (RX) do druhého zadávacího okna, jako `\` (N1MM „Typing Focus“; v SO2R se fokus vysílání přesune s další zprávou odeslanou z toho okna) |

Vstup se čte každých 20 ms s ošetřením zákmitů. V multi-op síti se PTT nožního spínače řídí
[interlockem](multi-op.md) jako každé jiné vysílání, což pokrývá N1MM „First One Wins“
(výchozí) a „Band lockout“ (rozsah interlocku „stejné pásmo“); hardwarová blokovací linka zapojená
na vstup nožního spínače podporovaná není.

### Rotátor přes UDP

Pro rotátorové programy s protokolem **N1MM Rotor** (PstRotator, ARSVCOM, N1MM
Rotor) — **„Nastavení → Antennas → Rotátor přes UDP“**: host, port (výchozí 12040) a jméno rotátoru. Alt+J / Alt+L /
Ctrl+Alt+J a tlačítka okna Rotátor pak posílají

```
<N1MMRotor><rotor>Yagi 20</rotor><goazi>330.0</goazi><offset>0</offset><bidirectional>0</bidirectional><freqband>14</freqband></N1MMRotor>
<N1MMRotor><stop>Yagi 20</stop></N1MMRotor>
```

UDP může běžet souběžně s rotctld; bez rotctld se aktuální poloha nečte
(okno ukazuje jen směr k volací značce).
