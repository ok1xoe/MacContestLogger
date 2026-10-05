# Network logbook for multiple operators: a guide

This guide is for the **regular operator** (not a programmer). It explains how to set up a
shared logbook for several operating positions in one contest (multi-op / multi-multi),
similar to networking in N1MM+ or DXLog.

---

## 1. Do I need this at all?

- **Single-op (one operator, one computer):** **NO.** Ignore everything in this guide.
  You start MacContestLogger and log. The network logbook is off and nothing changes.
- **Multi-op / multi-multi (several positions in one team):** **YES.** You want all
  computers to see the contacts of the others, so that dupes, multipliers and the score
  apply to the whole team, not just to one position.

---

## 2. How it works, in plain words

Every computer has its **own full copy of the logbook** and computes dupes, multipliers and
the score **by itself**. The network only serves to let the stations **send each other new
contacts**.

Three important things follow from this:

1. **The dupe check is instant.** You type a callsign and see at once whether it is a dupe;
   it is computed locally and does not wait for the network.
2. **A network outage does not stop the contest.** If the network or the hub goes down, you
   keep logging. After it recovers, the logbooks catch up by themselves.
3. **The score cannot "drift apart".** Only bare facts about the contact (callsign, band,
   time, ...) travel over the network; each station computes the points itself from the same
   contest definition.

The network has one extra computer, the **hub**. It receives the contacts, reconciles them
and sends the canonical ("official") form to everyone. It can easily be an old laptop or a
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

## 3. What you need

- **At every operating position:** the **MacContestLogger** application (the client).
- **On one computer in the network (the hub):** two things:
  - **Mosquitto**, the message "postman" (an MQTT broker),
  - **the authority** (cluster-app), the brain that reconciles the contacts. It is a
    separate Java application (cluster-app, Java 21) that is not part of this repository.
- All computers must be on the **same network**, and the hub must have a **stable address**
  (a fixed IP or a hostname).

---

## 4. Setting up the hub

1. **Install and start Mosquitto** (on macOS via Homebrew):
   ```bash
   brew install mosquitto
   ```
   Create a simple `broker.conf` file:
   ```
   listener 1883 0.0.0.0
   allow_anonymous true
   persistence true
   ```
   and start it: `mosquitto -c broker.conf`
   (For real operation we recommend passwords; see section 7. A template is in
   `docs/cluster-mosquitto.conf`.)

2. **Start the authority** (the cluster-app Java application). Use the distribution and
   instructions that come with it; it connects to the broker as an ordinary MQTT client
   (by default `localhost:1883`) and serves the overview page on port `8080`.

When the authority is up, it prints something like:
`Cluster app běží. Broker localhost:1883, REST :8080, 0 událostí.`

---

## 5. Setting up an operating station

At **every** position in MacContestLogger:

1. Open **Nastavení → Připojení ke clusteru…** (Settings → Connection to the cluster).
2. Tick **"Zapnout síťový multi-op deník"** (Enable the network multi-op logbook).
3. Fill in:
   - **Broker**: the IP or hostname of the **hub** (for example `192.168.1.10`).
   - **Port**: `1883` (or `8883` if you use TLS; see section 7).
   - **ID stanice** (Station ID): a short unique name of the position, for example `OP1`,
     `OP2`, `RUN`, `MULT`. **Every position must have a different ID!**
   - **Uživatel / Heslo** (User / Password): only if the broker has authentication enabled
     (section 7); otherwise leave empty.
4. **Save.**

Tip: do not forget to fill in your own callsign in **Nastavení → Station data**; the score
is computed relative to it.

---

## 6. How do I know it works

- In the *Připojení ke clusteru* (Connection to the cluster) dialog the **Stav** (Status) is
  **připojeno** (connected).
- You log a contact at one position and within a few seconds it shows up in the logbooks of
  the others.
- Open **http://HUB-ADDRESS:8080/** in a browser: you will see the overview of the hub and
  a **table of all contacts** that arrived (callsign, band, mode, position, state).
- When you enter a callsign that the team has already worked on that band, it is shown as a
  dupe, even if another position logged it.

---

## 7. Security (for real operation)

For an isolated home network, the anonymous broker from section 4 is enough. If you want to
secure it:

- **Passwords**: create an account on the broker for each position:
  ```bash
  mosquitto_passwd -c /etc/mosquitto/passwd clusterserver   # the hub's account
  mosquitto_passwd    /etc/mosquitto/passwd OP1             # the account of position OP1
  ```
  and set `allow_anonymous false` + `password_file` in the broker. Then fill in
  **Uživatel/Heslo** (User/Password) in the application at each position. Templates:
  `docs/cluster-mosquitto.conf`, `docs/cluster-aclfile`.
- **TLS** (encryption, for an untrusted network): enable port `8883` with certificates in the
  broker, and in the application tick **TLS** and use port `8883`.

---

## 8. Common problems

| Symptom | Cause / solution |
|---|---|
| A station does not connect, "Connection refused" | The broker is not running on the hub, or the IP/port is wrong. Check that Mosquitto is running and that the address is correct. |
| It connects, but contacts are not transferred | Check that the hub also runs the **authority** (not just the broker). |
| Two positions "overwrite" each other's contacts | They have the **same station ID**. Every position must have a different one (OP1, OP2, ...). |
| Stations do not "see" each other on the network | A firewall blocks port `1883`. Allow it, or put everyone in the same subnet. |
| The network / the hub went down | No problem: you keep logging locally. After recovery the logbook catches up by itself. |

---

## 9. After the contest

You have the complete logbook at **every** position (a full copy), so you export (ADIF /
Cabrillo) from any station as usual. The hub additionally keeps the complete history of all
contacts (for audit and backups). Cleaning up the "tombstones" of deleted contacts is an
optional admin action on the hub; you normally do not need to deal with it.

---

### For technicians

The architecture and protocol belong to the separate Java authority and are documented with it.
Broker configuration: `docs/cluster-mosquitto.conf` + `docs/cluster-aclfile`.
