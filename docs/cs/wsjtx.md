# WSJT-X a JTDX

MacContestLogger spolupracuje s WSJT-X a JTDX podobně jako N1MM Logger+: přijímá jejich UDP zprávy (dekódy,
stav, zalogovaná QSO), zobrazuje dekódy ve vlastním seznamu, barví volající stanice v okně Band Activity
ve WSJT-X a umí program spustit. Samotné nastavení UDP popisuje stránka
[Propojení WSJT-X ⇄ RUMlogNG ⇄ MacContestLogger přes UDP](interop-udp-setup.md).

## Nastavení → WSJT/JTDX

- **Příjem z WSJT-X**: adresa, na kterou míří *UDP Server* ve WSJT-X (výchozí `0.0.0.0:2237`).
- **Barvit volačky v Band Activity** (výchozí zapnuto): každá dekódovaná volající stanice se v okně Band
  Activity ve WSJT-X obarví podle stavu v závodě — násobič červeným pozadím, více násobičů zeleným, nové
  QSO modrým textem, dupe šedým textem (zpráva WSJT-X *HighlightCallsign*, posílá se zpět té instanci, která
  dekód poslala, a jen při změně barvy).
- **DX Call z WSJT-X do pole volačky** (výchozí zapnuto): volačka z pole *DX Call* ve WSJT-X se objeví
  v poli volačky zadávacího okna, takže kontrola dupe a násobiče funguje, i když stanici voláš
  ve WSJT-X. Fokus zůstává, kde byl.
- **Změna pásma vymaže seznam dekódů** (výchozí zapnuto): když WSJT-X přejde na jiné pásmo, seznam
  dekódů se vymaže.

## Seznam dekódů (Okno → WSJT-X dekódy)

Obdoba *Decode List* z N1MM: dekódy obarvené jako v bandmapě, nejnovější nahoře.

- filtry **Jen CQ**, **Skrýt dupe**, **Jen násobiče** a **textový filtr** (libovolná část zprávy,
  např. `73` nebo prefix),
- **řazení** podle času (výchozí), SNR (nejsilnější nahoře), zvukové frekvence nebo volačky,
- sloupec **pásmo / mód** (`20m FT8`; při dvou instancích i instance),
- dvojklik zavolá stanici ve WSJT-X (Reply).

## Spuštění WSJT-X / JTDX (Okno → Spustit WSJT-X / JTDX)

V Nastavení → WSJT/JTDX nastav **Program (.app)** (a volitelně **Parametry**). Položka menu spustí novou
instanci programu, otevře seznam dekódů (*Po spuštění otevřít seznam dekódů*) a spustí příjem
UDP.

### Dvě instance pro SO2R

**Okno → Spustit WSJT-X / JTDX (rádio 2)** spustí druhou instanci s `--rig-name=<name>`, kde jméno
je z pole **Jméno instance pro rádio 2** (například `Radio2`; WSJT-X se pak hlásí jako
`WSJT-X - Radio2`). Tuto instanci nastav pro rig 2 a jiný UDP port jen tehdy, když ho potřebuješ —
obě mohou posílat na stejný příjem, MacContestLogger je rozliší podle jejich Id. DX Call druhé
instance jde do zadávacího okna **VFO B / rig 2**; její dekódy nesou v seznamu její frekvenci
a instanci.

## Ovládání rigu

N1MM umí pro WSJT-X fungovat jako server rigu (emulace DXLab Commander). MacContestLogger sdílí rig
jinak: oba programy mluví s **jedním `rigctld`**. Ve WSJT-X zvol *Rig: Hamlib NET rigctl*, *Network
Server* `localhost:4532` (démon, který používá MacContestLogger, viz
[Digitální módy → sdílení CAT](digital-modes.md#sharing-cat-with-fldigi)), *PTT: CAT* a *Split: Rig* nebo
*Fake It* podle libosti. Frekvence, mód, PTT i split pak fungují z obou programů bez
emulace Commanderu.

## JTDX: logování přes TCP

JTDX umí posílat každé zalogované QSO do *External logbook* přes TCP (N1MM používá port 52001). Zapni **JTDX:
logování přes TCP** a nastav adresu (výchozí `127.0.0.1:52001`); v JTDX zapni TCP deník a
nasměruj ho sem. Každý záznam ADIF (až po `<eor>`) se zaloguje jako QSO z WSJT-X.

## Módy

Q65 a FT2 se logují jako samostatné módy (digitální: Cabrillo `DG`, datový režim rigu `PKTUSB`); napsáním `Q65` nebo
`FT2` do pole volačky se mód přepne.
