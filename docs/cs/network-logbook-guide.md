# Síťový deník pro více operátorů: průvodce

Tento průvodce je pro **běžného operátora** (ne programátora). Vysvětluje, jak nastavit
společný deník pro více pracovišť v jednom závodě (multi-op / multi-multi),
podobně jako síťový provoz v N1MM+ nebo DXLogu.

---

## 1. Potřebuji to vůbec?

- **Single-op (jeden operátor, jeden počítač):** **NE.** Celého průvodce si nevšímejte.
  Spustíte MacContestLogger a zapisujete. Síťový deník je vypnutý a nic se nemění.
- **Multi-op / multi-multi (více pracovišť v jednom týmu):** **ANO.** Chcete, aby všechny
  počítače viděly spojení ostatních, takže dupe, násobiče a skóre
  platí pro celý tým, ne jen pro jedno pracoviště.

---

## 2. Jak to funguje, jednoduše řečeno

Každý počítač má **vlastní úplnou kopii deníku** a dupe, násobiče a
skóre si počítá **sám**. Síť slouží jen k tomu, aby si stanice **posílaly nová
spojení**.

Z toho plynou tři důležité věci:

1. **Kontrola dupe je okamžitá.** Napíšete značku a hned vidíte, jestli je dupe;
   počítá se lokálně a na síť se nečeká.
2. **Výpadek sítě závod nezastaví.** Když spadne síť nebo hub,
   zapisujete dál. Po obnovení se deníky samy dorovnají.
3. **Skóre se nemůže „rozejít“.** Po síti putují jen holá fakta o spojení (značka, pásmo,
   čas, ...); body si každá stanice počítá sama ze stejné
   definice závodu.

Upravené spojení putuje celé: ostatní stanice jím nahradí svou kopii, takže pole,
které úprava vymazala (komentář, operátor, přijaté číslo), se vymaže na každém počítači
také. Run / S&P se po síti neposílá; každá stanice si ponechává hodnotu spojení, která
sama zapsala, i když je upraví jiná stanice.

Síť má jeden počítač navíc, **hub**. Přijímá spojení, sjednocuje je
a všem rozesílá kanonickou („oficiální“) podobu. Klidně to může být starý notebook nebo
Raspberry Pi.

```
  Position OP1          Position OP2          Position OP3
  (MacContestLogger)    (MacContestLogger)    (MacContestLogger)
        \                     |                     /
         \____________________|____________________/
                              |   home network (LAN)
                       ┌──────┴───────────────────┐
                       │  Hub (1 computer)         │
                       │  • broker (Mosquitto)     │
                       │  • authority (cluster-app) │
                       └───────────────────────────┘
```

---

## 3. Co potřebujete

- **Na každém pracovišti:** aplikaci **MacContestLogger** (klienta).
- **Na jednom počítači v síti (hubu):** dvě věci:
  - **Mosquitto**, „pošťáka“ zpráv (MQTT broker),
  - **autoritu** (cluster-app), mozek, který sjednocuje spojení. Je to
    samostatná aplikace v Javě (cluster-app, Java 21), která není součástí tohoto repozitáře.
- Všechny počítače musí být ve **stejné síti** a hub musí mít **stálou adresu**
  (pevnou IP nebo hostname).

---

## 4. Nastavení hubu

1. **Nainstalujte a spusťte Mosquitto** (na macOS přes Homebrew):
   ```bash
   brew install mosquitto
   ```
   Vytvořte jednoduchý soubor `broker.conf`:
   ```
   listener 1883 0.0.0.0
   allow_anonymous true
   persistence true
   ```
   a spusťte ho: `mosquitto -c broker.conf`
   (Pro ostrý provoz doporučujeme hesla; viz oddíl 7. Šablona je v
   `docs/cluster-mosquitto.conf`.)

2. **Spusťte autoritu** (aplikaci cluster-app v Javě). Použijte distribuci a
   návod, které k ní patří; k brokeru se připojuje jako běžný MQTT klient
   (ve výchozím stavu `localhost:1883`) a na portu `8080` poskytuje přehledovou stránku.

Když autorita naběhne, vypíše něco jako:
`Cluster app běží. Broker localhost:1883, REST :8080, 0 událostí.`

3. **Volitelně: ohlaste broker v LAN (Bonjour)**, aby ho stanice našly
   bez zadávání adresy (zero-config networking jako v N1MM). Na hubu s Macem nechte vedle
   Mosquitta běžet:
   ```bash
   dns-sd -R "MCL broker" _mqtt._tcp local 1883
   ```
   (s TLS: `dns-sd -R "MCL broker" _secure-mqtt._tcp local 8883`). Na Linuxu / Raspberry Pi
   udělá totéž soubor služby Avahi `/etc/avahi/services/mqtt.service` s typem `_mqtt._tcp` a
   portem `1883`.

---

## 5. Nastavení operátorské stanice

Na **každém** pracovišti v MacContestLoggeru:

1. Otevřete **Nastavení → Připojení ke clusteru…**.
2. Zaškrtněte **„Zapnout síťový multi-op deník“**.
3. Vyplňte:
   - **Broker**: IP nebo hostname **hubu** (například `192.168.1.10`). Pokud se hub
     ohlašuje (oddíl 4, krok 3), **Najít broker v LAN (Bonjour)** ho po několika sekundách
     vypíše; klik vyplní broker, port a TLS. Hledání
     proběhne jen po stisku tlačítka. Bonjour neprojde přes VPN jako Tailscale; pro
     vzdálenou stanici na Tailscale použijte místo toho **Najít cluster přes Tailscale**,
     viz níže, nebo napište tailnetovou adresu hubu či jeho jméno MagicDNS.
   - **Najít cluster přes Tailscale**: pro stanice propojené přes [Tailscale](https://tailscale.com/).
     Zeptá se klienta Tailscale na tomto Macu na počítače vašeho tailnetu
     (`tailscale status --json`; aplikace Tailscale z App Storu nebo z webu, nebo příkaz `tailscale`
     z Homebrew). Pak zkusí každý počítač, který je **online**, na MQTT portu `1883`
     a na portu zadaném v poli **Port** (s nastavením **TLS**). Test je žádost o MQTT
     připojení s jednorázovým client ID, bez uživatelského jména a bez dat, okamžitě zase uzavřená.
     Vypíšou se počítače, jejichž broker odpoví (`hub — 100.64.0.2:1883`); klik vyplní
     broker, port a TLS. Pro TLS se použije jméno MagicDNS počítače, takže certifikát brokeru
     musí být vystaven na toto jméno (například pomocí `tailscale cert`). Kontaktují se jen počítače ze seznamu
     vašeho tailnetu, nikdy žádná jiná adresa, a jen po stisku tlačítka. Pokud Tailscale
     není nainstalovaný, neběží nebo není přihlášený, oznámí to stavový řádek.
     S `MCL_INERT_NETWORK` se nic nespouští ani nekontaktuje.
   - **Port**: `1883` (nebo `8883`, pokud používáte TLS; viz oddíl 7).
   - **ID stanice**: krátký jedinečný název pracoviště, například `OP1`,
     `OP2`, `RUN`, `MULT`. **Každé pracoviště musí mít jiné ID!**
   - **Uživatel / Heslo**: jen pokud má broker zapnuté ověřování
     (oddíl 7); jinak nechte prázdné.
4. **Uložte.**

Tip: nezapomeňte vyplnit vlastní volací značku v **Nastavení → Station data**; skóre
se počítá vzhledem k ní.

---

## 6. Jak poznám, že to funguje

- V dialogu *Připojení ke clusteru* je **Stav**
  **připojeno**.
- Zapíšete spojení na jednom pracovišti a během několika sekund se objeví v denících
  ostatních.
- Otevřete v prohlížeči **http://HUB-ADDRESS:8080/**: uvidíte přehled hubu a
  **tabulku všech spojení**, která dorazila (značka, pásmo, mód, pracoviště, stav).
- Když zadáte značku, kterou tým už na tomto pásmu udělal, zobrazí se jako
  dupe, i když ji zapsalo jiné pracoviště.

---

## 7. Zabezpečení (pro ostrý provoz)

Pro izolovanou domácí síť stačí anonymní broker z oddílu 4. Pokud ho chcete
zabezpečit:

- **Hesla**: vytvořte na brokeru účet pro každé pracoviště:
  ```bash
  mosquitto_passwd -c /etc/mosquitto/passwd clusterserver   # the hub's account
  mosquitto_passwd    /etc/mosquitto/passwd OP1             # the account of position OP1
  ```
  a v brokeru nastavte `allow_anonymous false` + `password_file`. Pak na každém pracovišti vyplňte
  v aplikaci **Uživatel/Heslo**. Šablony:
  `docs/cluster-mosquitto.conf`, `docs/cluster-aclfile`.
- **TLS** (šifrování, pro nedůvěryhodnou síť): v brokeru zapněte port `8883` s certifikáty
  a v aplikaci zaškrtněte **TLS** a použijte port `8883`.

---

## 8. Časté problémy

| Příznak | Příčina / řešení |
|---|---|
| Stanice se nepřipojí, „Connection refused“ | Na hubu neběží broker, nebo je chybná IP/port. Zkontrolujte, že Mosquitto běží a adresa je správná. |
| Připojí se, ale spojení se nepřenášejí | Zkontrolujte, že na hubu běží i **autorita** (nejen broker). |
| Dvě pracoviště si navzájem „přepisují“ spojení | Mají **stejné ID stanice**. Každé pracoviště musí mít jiné (OP1, OP2, ...). |
| Stanice se v síti „nevidí“ | Port `1883` blokuje firewall. Povolte ho, nebo dejte všechny do stejné podsítě. |
| Spadla síť / hub | Žádný problém: zapisujete dál lokálně. Po obnovení se deník sám dorovná. |

---

## 9. Po závodě

Úplný deník máte na **každém** pracovišti (úplná kopie), takže exportujete (ADIF /
Cabrillo) z kterékoli stanice jako obvykle. Hub navíc uchovává úplnou historii všech
spojení (pro audit a zálohy). Úklid „tombstones“ smazaných spojení je
volitelná administrátorská akce na hubu; obvykle se jí nemusíte zabývat.

---

### Pro techniky

Architektura a protokol patří k samostatné autoritě v Javě a jsou zdokumentovány u ní.
Konfigurace brokeru: `docs/cluster-mosquitto.conf` + `docs/cluster-aclfile`.
