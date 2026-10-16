# Statistiky

![Statistiky: kontingenční tabulka podle hodin a pásem](../img/statistics.png)

## Kontingenční statistiky

Obdoba N1MM+ **Statistics** a DXLog **Summary / Statistics**. Otevírá se přes
**Okno → Statistiky**.

- Nahoře graf **QSO za hodinu** (s maximem).
- Tabulka: **Řádky** × **Sloupce** z dimenzí hodina UTC, den, pásmo, mód, kontinent,
  země, operátor, Run / S&P (u sloupců také „—“ = jen součet). Hodiny a dny jsou
  chronologicky, pásma podle frekvence, ostatní podle počtu QSO.
- Součty řádků, součty sloupců a celkový počet; smazaná QSO se nepočítají.
- Další dimenze jako v N1MM: řádky **po 5, 10 nebo 15 minutách**, **pásmo a mód** dohromady (`20m CW`) a
  **stanice** při multi-op. S otevřeným závodem i jeho vlastní: **body** QSO, **nový násobič** (MULT / —),
  každé přijaté **pole výměny** (zóna, sekce, lokátor, okres v QSO party, …) a každý **násobič**
  závodu. Ty pocházejí z přehrání deníku podle pravidel závodu, takže odpovídají skóre.
- **Včetně dupů a X-QSO** — vypnuto vynechá dupy a X-QSO z tabulky, grafu
  a přehledů.
- **Tabulka / Graf** — stejná kontingenční tabulka jako skládané sloupce, jeden sloupec na řádek, barva na sloupec tabulky.
- **Kopírovat vše** vloží tabulku do schránky jako text oddělený tabulátory (vloží se do
  tabulkového procesoru), **Uložit…** ji zapíše do textového souboru, **Tisk…** ji vytiskne.
- Psaní písmen nebo číslic, když je okno Statistiky vpředu, pokračuje v poli volačky zadávacího okna,
  jako v N1MM.

Typické pohledy: hodina × pásmo (kdy a kde), kontinent × pásmo (podmínky šíření), operátor ×
mód (multi-op), 10 minut × stanice (rate při multi-op), násobič × pásmo.

## Rate, přestávky, běhy

Obdoba přehledů **Rate** v N1MM a statistik DXLogu. V okně Statistiky přepněte na
**Rate, přestávky, běhy**:

- **Nejlepší rate** za 10 a 60 minut (počet QSO, přepočet na hodinu, začátek okna).
- **Přestávky** alespoň 30 minut mezi QSO a jejich součet (kontrola pravidel off-time).
- **Run série** — po sobě jdoucí Run QSO na jednom pásmu a frekvenci (±2 kHz, mezera
  nejvýš 10 min, alespoň 5 QSO): začátek, pásmo, frekvence, počet, délka, rate.
