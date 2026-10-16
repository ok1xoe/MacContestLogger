# Zásobník volaček (call stacking)

Když na CQ odpoví více stanic, zásobník volaček vám dovolí poznamenat si další volačky a pracovat je jednu po
druhé, aniž byste je psali znovu — N1MM Logger+ „Single Operator Call Stacking“, „Digital Call
Stacking“ a partnerský call stacking. MacContestLogger má pro všechny **jeden zásobník**: volačky, které
si uložíte sami, volačky naklikané v Digitálním rozhraní i volačky, které pošle partner po
síti, čekají ve stejném seznamu.

## Řádek zásobníku

Jakmile je nějaká volačka v zásobníku, informační proužek zadávacího okna ukazuje **„ZÁSOBNÍK K1ZZ JA1ABC
(Alt+G)“** — volačky v pořadí, v jakém budou ze zásobníku odebírány.

- Nejvýš **10** volaček; když přijde jedenáctá, nejstarší vypadne.
- **Dupe se do zásobníku nikdy nedávají** („… je dupe — do zásobníku nejde“) a volačka, která se stane dupem,
  zatímco čeká (mezitím jste ji udělali), se přeskočí.
- Volačka, která už v zásobníku je, se nepřidá podruhé.
- **Změna pásma zásobník vymaže** (volačky, které odpověděly na staré run frekvenci). Volba je
  v **Nastavení → Function Keys → Zásobník volaček (call stacking)** a je ve výchozím stavu zapnutá.

## Pořadí

**Nastavení → Function Keys → Zásobník volaček (call stacking) → Pořadí ze zásobníku**:

| Pořadí | Další volačka |
|---|---|
| **FIFO, násobiče napřed** (výchozí) | volačka, která přinese nejvíc nových násobičů; mezi stejnými ta, která byla uložena první. N1MM to dělá v CW a SSB. |
| **FIFO** | volačka uložená jako první |
| **LIFO** | volačka uložená jako poslední |

Hodnota násobičů se vyhodnocuje na frekvenci a módu aktivního zadávacího okna v okamžiku, kdy se
bere další volačka, takže zohledňuje QSO zapsaná mezitím.

## Ukládání volaček do zásobníku

| Klávesa / makro | Akce |
|---|---|
| **Ctrl+Alt+G** nebo `{STACKANOTHER}` | volačka z pole volačky jde do zásobníku a zadávací okno se vymaže pro další volačku (`{STACKANOTHER}` jen v Run) |
| `{SOCALLSTACK}` (jen Run) | jednoúrovňový zásobník: s prázdným zásobníkem se volačka uloží a pole vymaže; s uloženou volačkou se pole a zásobník **prohodí**; s prázdným polem se uložená volačka vrátí. S prázdným zásobníkem dupe nedělá nic. |
| **Option+klik** na volačku v Digitálním rozhraní | kliknutá volačka jde do zásobníku, pole volačky zůstane (N1MM Alt+klik) |
| **Ctrl+Alt+G** v digitálním módu s Digital Call Stacking | zvýrazněná volačka okna Grab jde do zásobníku, pole volačky zůstane |
| partnerovo **Do zásobníku** | viz [Multi-op a síť](multi-op.md#partner-a-zásobník-volaček) |

## Odebírání volaček ze zásobníku

| Klávesa / makro | Akce |
|---|---|
| **Alt+G** (také Ctrl+Alt+K) | zadávací okno se vymaže a do pole volačky přijde další volačka (žádné QSO se nezapíše) |
| **Alt+D** s prázdným polem volačky | smaže další volačku, aniž by se pracovala (s volačkou v poli Alt+D odstraní její spot jako dřív) |
| `{CLRSTACK}` | vymaže zásobník |
| `{LOGTHENPOP}` / `{LOGTHENNEXT}` (jen Run) | zapíše QSO a začne další, viz níže |

## {LOGTHENPOP}: zapsat a pokračovat

`{LOGTHENPOP}` ve zprávě F-klávesy zprávu rozdělí:

- text **před** makrem se pošle zapisované stanici,
- QSO se zapíše,
- další volačka přijde ze zásobníku do pole volačky,
- text **za** makrem se pošle **další** stanici — `!`, `#`, `{F5}` a `{F2}` už
  znamenají nové QSO.

Doporučená zpráva Next Call (N1MM): **`! {LOGTHENPOP} TU {F5}{F2}`** — v CW pošle „DL1ABC TU
K1ZZ 5NN 15“ jedním vrzem, takže pileup nezačne znovu. Používejte `{F5}{F2}` místo `!` a
samotného textu výměny; průběh ESM dalšího QSO se řídí klávesami, na které zpráva odkazuje
(`{F2}` = výměna byla odeslána), takže další Enter v ESM už je TU nového QSO.

- Když **v zásobníku nic není**, QSO se zapíše a místo zbytku zprávy se pošle **zpráva TU (F3)**.
- `{LOGTHENPOP}` nikdy nezapíše neúplné QSO: **mimo Run**, **před odesláním výměny**
  (F2) nebo s **neúplnou přijatou výměnou** klávesa nic nepošle a stavový řádek řekne
  proč.
- `{LOGTHENNEXT}` dělá totéž, ale ESM ho nikdy samo nevybere.
- V **SSB** (hlasový klíč) se makra zásobníku provedou **před** přehráním zprávy, ať jsou v ní
  kdekoli: `{LOGTHENPOP},tu.wav,{F5},{F2}` zapíše, vezme další volačku a pak jí přehraje celou
  zprávu.

## ESM: klávesa Next Call

**Nastavení → Function Keys → Zásobník volaček (call stacking) → Klávesa další volačky (ESM)** vybírá F-klávesu,
která obsahuje `{LOGTHENPOP}` (například F12; „Žádná“ automatiku vypne). Když by v Run další Enter
poslal TU (F3) a zapsal a v zásobníku čeká volačka, ESM místo toho pošle tuto klávesu — zapíše, poděkuje
a pošle výměnu další volačce. Když je zásobník prázdný, Enter zase pošle normální TU.
Klávesa musí obsahovat `{LOGTHENPOP}` v sadě zpráv aktuálního módu (CW, SSB nebo digi); klávesa
s `{LOGTHENNEXT}` se nikdy nevybere. Viz [ESM](esm.md#zásobník-volaček).

Příklad (CW, Run, ESM zapnuté, F12 = `! {LOGTHENPOP} TU {F5}{F2}`, klávesa Next Call F12):

1. Volají K3CT a N2IC. Napište K3CT, stiskněte **Ctrl+Alt+G**, napište N2IC a stiskněte **Enter** (F5+F2).
2. Zapište výměnu N2IC a stiskněte **Enter**: N2IC se zapíše, odejde „N2IC TU K3CT 5NN 15“, K3CT je
   v poli volačky.
3. Zapište výměnu K3CT a stiskněte **Enter**: TU, zapsáno — zásobník je prázdný.

## Digitální rozhraní

V okně Digitální rozhraní **Option+klik** na volačku uloží ji do zásobníku. **Nastavení → Digitální
zásobník volaček** (také v Nastavení → Function Keys) zapne N1MM
Digital Call Stacking: v **Run**, když už je v poli volačky nějaká volačka, obyčejný klik na jinou
volačku

- **FIFO / FIFO, násobiče napřed**: dá kliknutou volačku do zásobníku (pole volačky zůstane),
- **LIFO**: dá volačku z pole do zásobníku a kliknutou volačku do pole.

Pořadí vybrané tam je pořadím zásobníku pro všechny módy. Viz
[Digitální módy](digital-modes.md#zásobník-volaček-call-stacking).
