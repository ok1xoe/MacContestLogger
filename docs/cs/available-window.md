# Okno Dostupné multiplikátory (N1MM Available)

*Okno → Dostupné multiplikátory* vypisuje spoty z paměti spotů (po [filtru spotů](dx-cluster.md#filtr-spotů-pásma-módy-původ-spotteru-pracovatelné))
tak, jak je hodnotí aktivní závod: nové násobiče červeně (dva a víc zeleně), obyčejná QSO modře, dupe šedě. Bez
aktivního závodu okno jen oznámí, že žádný není.

## Horní lišta

| Tlačítko | Co dělá |
|---|---|
| **Mults / Mults & Qs** | jen nové násobiče, nebo všechny pracovatelné spoty |
| **Pásma a režimy** | zobrazená pásma a kategorie provozu (výchozí jsou ty závodu; co závod nemá, je zašedlé) |
| **Fokus rig** | jen spoty na pásmu rádia (SO2R) nebo VFO (SO2V) s fokusem; s jedním rádiem pásmo naladěné frekvence |
| **Sloupce a souhrn** | sloupce, jejich pořadí, souhrnný panel a jeho pásma (níže) |

**Okno → Dostupné multiplikátory 2 (rádio 2)** (SO2V / SO2R, v N1MM okno Available druhého zadávacího okna) je
svázané s rádiem 2 / VFO B: jeho *Fokus rig* (výchozí zapnuto) ukazuje pásmo rádia 2 a klik na spot naladí rádio 2 a
vloží volačku do jeho okna — fokus zápisu, pokud je na rádiu 1, tam zůstane.

## Souhrnný panel

Pod titulkem ukazuje souhrn nové násobiče (*Mults*), nová QSO (*Qs*) a všechny spoty (*Total*) po pásmech.
Nejlepší pásmo — nejvíc nových násobičů, pak nejvíc nových QSO — je zvýrazněné. **Klik na pásmo** ukáže jen
spoty tohoto pásma; druhý klik vrátí pásma, která byla zobrazená předtím.

V *Sloupce a souhrn* lze panel skrýt (*Zobrazit souhrnný panel*) a vybrat jeho pásma — jakákoli pásma včetně
VKV, UKV a mikrovlnných. Když není nic zaškrtnuto, panel ukazuje pásma aktivního závodu (šest KV pásem z v1.1.1,
pokud závod žádná nemá). Volba se ukládá.

## Seznam spotů

Sloupce jsou *Call*, *Freq*, *Dir* (azimut od vašeho lokátoru), *Md* (mód), *Mlt* (✓ = nový násobič), *SN* (SNR
skimmeru), *Time* (stáří spotu v minutách), *Spotter* (★ = preferovaný spotter), *Pts* (body za QSO) a
*Sig*. **Každé záhlaví řadí** (znovu = opačný směr; *Time* vzestupně znamená nejnovější spot napřed). V
*Sloupce a souhrn* lze každý sloupec zobrazit nebo skrýt a posunout doleva či doprava (*Call* je vidět vždy); **tažením oddělovače
vpravo od záhlaví** se mění šířka sloupce. *Výchozí sloupce* obnoví sloupce, pořadí i šířky. Vše
se ukládá.

Značky za volačkou, stejně jako v bandmapě: **♥** speciální volačka, **#** spot ze skimmeru / RBN (**!** váš vlastní skimmer),
**¤** stanice má právě východ nebo západ slunce (šedá linie). Spot, jehož komentář žádá split (`UP 5`, `QSX 14025`),
ukazuje za frekvencí **QSX 027**. VoiceOver značky říká slovy.

Sloupec ***Sig*** (výchozí vypnutý) ukazuje **♪**, když je signál spotu právě vidět ve
[vodopádu](waterfall.md): frekvence spotu leží v audio propustném pásmu přijímače a nejnovější řádky vodopádu
tam mají signál aspoň ~14 dB nad šumem. Vyžaduje otevřené okno vodopádu (to okno drží
audio přijímače); když je zavřené, sloupec zůstává prázdný.

## Myš a klávesy

- **Klik** na spot: rádio se tam naladí a volačka jde do zadávacího okna (se zapnutým call-frame do
  call-frame). Se **dvěma rádii (SO2R) nebo dvěma VFO (SO2V)** spot na pásmu druhého rádia nejdřív přesune
  fokus do zadávacího okna toho rádia (N1MM *focus follows spot*).
- **Prostřední klik** (tlačítko kolečka myši) smaže spot pod ukazatelem.
- **Pravý klik**: odstranit spot, dát volačku nebo spottera na blacklist, QRZ.com / HamQTH, **Natočit rotátor** (rotátor
  na stanici, krátkou cestou, jako Alt+J; podle lokátoru spotu, je-li známý), **QSY druhého rádia / VFO** (SO2V / SO2R: druhé VFO nebo rádio
  přejde na spot a fokus zůstane, kde je), smazat všechny spoty.
- **Alt+A** / **Shift+Alt+A** v zadávacím okně: naladí a převezme další / předchozí spot seznamu (tak, jak je
  seřazený a filtrovaný), řádek se zvýrazní; seznam jde dokola. Obě klávesy lze přemapovat v Nastavení → Klávesy.

Nic v tomto okně nevysílá.
