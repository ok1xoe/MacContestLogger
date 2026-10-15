# QTC (WAE DX Contest)

![Okno QTC pro WAE](../img/qtc.png)

Obdoba **okna QTC** z N1MM pro [WAE DX Contest](https://www.darc.de/der-club/referate/conteste/wae-dx-contest/en/).
Závody `wae-cw`, `wae-ssb` a `wae-rtty` jsou v datech závodů.

## Pravidla v definici

```yaml
scoring:
  qtc: { points: 1, maxPerStation: 10, groupSize: 10 }
  total: "(qsoPoints + qtcPoints) * multTotal"
multipliers:
  - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND,
      bandWeights: { 80m: 4, 40m: 3, 20m: 2, 15m: 2, 10m: 2 } }
```

- Každé QTC = 1 bod, s jednou stanicí nejvýše 10 QTC.
- Násobiče po pásmech s **váhou pásma** (`bandWeights`, 80 m ×4, 40 m ×3,
  vyšší ×2) — obecná vlastnost DSL, použitelná i jinde.

## Okno QTC

**„Okno → QTC (WAE)“**:

- **„Přijmout QTC“** (evropská stanice): stanice, série (`3/10`)
  a řádky `čas značka číslo` (`1234 DL1ABC 56`). Nečitelné řádky se zobrazí
  červeně.
- **„Poslat QTC“** (mimoevropská stanice): série z vlastního deníku
  — chronologicky, jen dosud nenahlášená QSO a ne QSO se stejnou
  stanicí, nejvýše volný počet. **„Odvysílat CW“** odvysílá
  `QTC 3/10 1234 DL1ABC 56 ...` klíčovačem, **„Potvrzeno — uložit“**
  sérii zapíše.
- Limit 10 QTC na stanici se hlídá a seznam vyměněných QTC lze
  smazat.
- Body za QTC jsou ve skóre okamžitě (i po přepočtu) a v Cabrillu
  jako řádky `QTC:` za QSO:
  `QTC: freq mo date time sender series/count recipient time callsign number`.

**WAE RTTY** (`wae-rtty`): každý pracuje s každým a QTC jdou oběma směry mezi stanicemi z různých
kontinentů — každá stanice používá **Přijmout QTC** i **Poslat QTC**. Limit 10 počítá odeslaná i přijatá
QTC s jednou stanicí dohromady, jak vyžadují pravidla RTTY.

QTC se ukládají do deníku (tabulka `qtc`); synchronizace clusteru je mezi
stanicemi nepřenáší.

## Režim QTC (Ctrl+Z)

Jako v N1MM přepíná **Ctrl+Z** v okně zápisu režim QTC: otevře okno QTC — pro **příjem** u evropské stanice,
pro **vysílání** u stanice odjinud — a zase ho zavře. Protistanicí je značka v okně zápisu (jinak značka
posledního QSO). Mimo Evropu se úplné QSO, které je ještě v okně zápisu, nejdřív zapíše (N1MM: „if you've
forgotten to log the QSO, Ctrl+Z will do it for you“); dupe se takto nikdy nezapíše. Závod bez QTC to oznámí
ve stavovém řádku.

Makra F-kláves `{DIGQTCR}` a `{DIGQTCS}` otevřou okno pro příjem / vysílání a `{QTC}` je hlavička série
v otevřeném okně (`26/10`; hlavička zadaná jen jako `12` znamená `12/10`), např. ve zprávě TU.

## Tlačítka zpráv

Řádek pod polem stanice obsahuje zprávy QTC z N1MM pro vaši stranu a mód okna zápisu. Vysílají se klíčovačem
okna zápisu — CW klíčovačem, hlasovým klíčovačem (SSB: soubory wav, `[text]`), fldigi (RTTY) — jen když je
stisknete; simulátor a brána vysílání platí stejně jako u F-kláves.

| Strana | CW | SSB | RTTY |
|---|---|---|---|
| Příjem | **QTC?**, **QRV**, **Cfm**, **Agn n**, **TU** | **QRV**, **Cfm**, **Agn n**, **TU** | **QRV**, **All Agn**, **Agn n**, **Save QTC** |
| Vysílání | **TU** | **TU** | **RU QRV?**, **Save QTC** a **Odvysílat sérii (digi)** |

**Agn n** žádá o QTC následující po dosud zachycených řádcích (`$` ve zprávě je jeho číslo). Prázdná zpráva TU
odvysílá běžnou klávesu TU (F3). V RTTY odvysílá **Odvysílat sérii (digi)** „Send All“ z N1MM: záhlaví, všechny
řádky a zakončení, spojené oddělovačem QTC.

## Nastavení QTC

**„Nastavení QTC…“** v horní liště okna odpovídá Config → WAE v N1MM (každá změna se ukládá hned):

- **Ctrl+Z pošle QTC? automaticky** — Ctrl+Z v Runu a CW u evropské stanice nejdřív odvysílá žádost
  (výchozí vypnuto).
- **Enter v hlavičce série pošle QRV (CW)** — Return v poli série odvysílá QRV.
- **QTC v jedné sérii** — „Default Number of QTCs to Send“ z N1MM (1–10).
- **Max. QTC pro barvy v bandmapě** — „Max QTC Number for callsign colors in Band Map“ z N1MM.
- Zprávy: CW (QTC?, QRV, Cfm, Agn, TU), SSB (soubory wav pro QRV, Cfm, Agn, TU, dohledávané stejně jako wav
  soubory F-kláves), RTTY (RQTC: RX Ready, All Agn, Agn, Save QTC; SQTC: RU QRV, Send All Heading, Send All Ending,
  Save QTC; oddělovač QTC, výchozí `{ENTER}`). Fungují v nich makra F-kláves a navíc `{QTC}` a `$`.

## Barvy v bandmapě

V závodě s QTC používá bandmapa barvy N1MM: **červená** nový násobič, **zelená** nová stanice, se kterou ještě
můžete vyměnit QTC, **modrá** nová stanice, se kterou už QTC nezbývají, **černá** (v tmavém vzhledu světle šedá)
dupe, se kterým ještě můžete vyměnit QTC, **šedá** dupe, u kterého už nic nezbývá. QTC zbývají, dokud jich se
stanicí bylo vyměněno méně, než je barevný limit, a kontinenty je dovolují (Evropa ↔ jinde; ve WAE RTTY
libovolné dva kontinenty).

Z N1MM se nepřebírá: tlačítka Agn u jednotlivých řádků a mřížka příjmu po polích s vlastními klávesami
(Shift+1…3, Alt+A / Ctrl+A pro změnu počtu) — přijaté řádky se zde píší do jednoho textového pole, takže volby
CW vázané na ta pole („send CFM when leaving the serial field“, „Hdr Agn / Agn clear the fields“) nemají
obdobu.
