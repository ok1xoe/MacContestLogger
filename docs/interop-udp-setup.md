# Connecting WSJT-X ⇄ RUMlogNG ⇄ MacContestLogger over UDP

A guide to setting up three applications so that they pass logged QSOs to each other over UDP.
It covers 4 main scenarios (use cases); the third has three sub-variants.

All examples assume **one computer** (addresses `127.0.0.1`). On several machines, replace
the loopback with real IPs.

---

## 1. Who talks which protocol on which port

There are **two different wire protocols** that do not talk to each other directly:

| Protocol | Carries | Default port | Format |
|---|---|---|---|
| **WSJT-X** | a logged QSO from WSJT-X | 2237 | binary (QSO Logged + Logged ADIF) |
| **N1MM contactinfo** | a logged QSO from a logbook | 12060 | text XML `<contactinfo>` |

Capabilities of each application (what it **receives** = listens to, what it **sends**):

| Application | Receives (listens) | Sends (on logging) |
|---|---|---|
| **WSJT-X** | none (only a source) | **WSJT-X protocol** to 1 target (UDP Server), default `:2237` |
| **RUMlogNG** | **WSJT-X protocol** on `:2237` | **N1MM contactinfo** to a configurable target (default `:12060`) |
| **MacContestLogger** | **WSJT-X protocol** (`wsjtx.receiveBind`, default `:2237`, **unicast only**) and **N1MM contactinfo** (`n1mmRecv.receiveBind`, default `:12061`, unicast and multicast) | **WSJT-X protocol** (`wsjtx.sendTargets`) and **N1MM contactinfo** (`broadcast.contactsTargets`) |

### Interop edges (who can feed whom)

```
WSJT-X  ──WSJT-X proto (2237)──►  RUMlogNG
WSJT-X  ──WSJT-X proto (2237)──►  MacContestLogger
MacContestLogger  ──WSJT-X proto (2237)──►  RUMlogNG      (MCL emulates WSJT-X)
RUMlogNG  ──N1MM contactinfo (12061)──►  MacContestLogger
```

**RUMlog imports only the WSJT-X protocol**; it does not take foreign N1MM contactinfo into
its logbook. That is why "MacContestLogger → RUMlog" goes **only** through WSJT-X emulation
(MacContestLogger sends the WSJT-X protocol to RUMlog's port 2237), not through N1MM.

---

## 2. Binding rules and limitations

1. **Only one application may bind port 2237 on one machine.** Both RUMlog and
   MacContestLogger want to receive the WSJT-X protocol on 2237, so they cannot both do it at
   once. In every scenario, state clearly who "owns" 2237.
2. **WSJT-X has only one UDP Server target.** Fan-out to several recipients works only with
   multicast, or through a chain (WSJT-X → RUMlog → N1MM → MacContestLogger).
3. **MacContestLogger's WSJT-X reception is unicast-only**; it cannot join a multicast group.
   (N1MM reception can do multicast.) That is why WSJT-X → both logbooks is solved by a
   **chain through RUMlog**, not by WSJT multicast.
4. **Importing into MacContestLogger requires an active contest.** Without one, a received QSO
   is discarded (only a status message). For ordinary operation, define a "classic" contest.
5. **No-echo + dedup:** a QSO received from the network is not sent back by MacContestLogger
   (by any sender); a duplicate reception of the same QSO by two paths (±120 s, same
   callsign/band) is stored only once.
6. **Accessing the MacContestLogger configuration:** the tab is in the WSJT tab of the
   Configurer. If you do not see it, switch `tab.wsjt` in `menu.json` from `"hidden"` to
   `"enable"`; you create the file in Nastavení → Other → Menu aplikace (Settings → Other →
   Application menu); see [settings.md](settings.md#menu-aplikace).

### MacContestLogger: where to set what

| Function | UI (Configurer) | config.json |
|---|---|---|
| Receiving from WSJT-X | WSJT → "Příjem z WSJT-X" (Receive from WSJT-X) | `wsjtx.receiveEnabled` + `wsjtx.receiveBind` |
| Sending to WSJT-X logbooks | WSJT → "Vysílání do deníků" (Send to logbooks) | `wsjtx.sendEnabled` + `wsjtx.sendTargets` |
| Receiving N1MM / RUMlog | WSJT → "Příjem N1MM / RUMlog" (Receive N1MM / RUMlog) | `n1mmRecv.receiveEnabled` + `n1mmRecv.receiveBind` |

---

## 3. Use case 1: WSJT-X ⇄ RUMlogNG (alone)

WSJT-X logs, RUMlog receives. MacContestLogger does not take part.

```
WSJT-X ──WSJT-X proto──► RUMlogNG (:2237)
```

| Application | Setup |
|---|---|
| **WSJT-X** | Settings → Reporting → UDP Server = `127.0.0.1`, port `2237`, "Accept UDP requests" on |
| **RUMlogNG** | reception from WSJT-X on (listens on `2237`) |
| **MacContestLogger** | not required (not running, or 2237 reception off, otherwise it collides with RUMlog) |

Direction: WSJT-X → RUMlog (one way).

---

## 4. Use case 2: WSJT-X → MacContestLogger

WSJT-X logs, MacContestLogger receives (taking over the role of RUMlog).

```
WSJT-X ──WSJT-X proto──► MacContestLogger (:2237)
```

| Application | Setup |
|---|---|
| **WSJT-X** | UDP Server = `127.0.0.1:2237` |
| **MacContestLogger** | WSJT → "Příjem z WSJT-X" **on**, bind `0.0.0.0:2237`; **an active contest** |
| **RUMlogNG** | must not bind `2237` (not running, or reception from WSJT-X off), otherwise a port conflict |

Direction: WSJT-X → MacContestLogger. In this scenario RUMlog does not hold port 2237.

---

## 5. Use case 3: MacContestLogger ⇄ RUMlogNG

Three sub-variants. WSJT-X is not needed here (QSOs originate in the logbooks).

### 5a) RUMlog logs, MacContestLogger listens

```
RUMlogNG ──N1MM contactinfo──► MacContestLogger (:12061)
```

| Application | Setup |
|---|---|
| **RUMlogNG** | N1MM/UDP broadcast target = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT → "Příjem N1MM / RUMlog" **on**, bind `0.0.0.0:12061`; **an active contest**. WSJT reception and sending off. |

Direction: RUMlog → MacContestLogger. (Redirect RUMlog's default broadcast port 12060 to 12061, because RUMlog holds 12060 itself.)

### 5b) MacContestLogger logs, RUMlog listens

RUMlog imports only the WSJT-X protocol, so MacContestLogger has to emulate it.

```
MacContestLogger ──WSJT-X proto──► RUMlogNG (:2237)
```

| Application | Setup |
|---|---|
| **MacContestLogger** | WSJT → "Vysílání do deníků" **on**, targets = `127.0.0.1:2237`. WSJT reception and N1MM reception off (2237 belongs to RUMlog). |
| **RUMlogNG** | reception from WSJT-X on (listens on `2237`) |

Direction: MacContestLogger → RUMlog. RUMlog treats MacContestLogger as if it were WSJT-X.

### 5c) Both log, both listen (two-way)

A combination of 5a + 5b. No port conflict: RUMlog holds 2237, MacContestLogger holds 12061.

```
MacContestLogger ──WSJT-X proto (2237)──► RUMlogNG
RUMlogNG ──N1MM contactinfo (12061)──► MacContestLogger
```

| Application | Setup |
|---|---|
| **RUMlogNG** | reception from WSJT-X on `2237`; N1MM broadcast target = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT "Vysílání" (Send) **on** → `127.0.0.1:2237`; N1MM "Příjem" (Receive) **on**, bind `0.0.0.0:12061`; WSJT "Příjem" **off** (2237 is held by RUMlog); **an active contest** |

Flows in both directions. **Loop handling:** when MacContestLogger logs a QSO, it sends it to
RUMlog over the WSJT-X protocol; RUMlog logs it and broadcasts it back over N1MM to 12061.
MacContestLogger thus receives its own QSO back, but **dedup ±120 s** (same
callsign/band/time) discards it, so it is not stored twice. In the other direction, a QSO
received from RUMlog is **not** sent on by MacContestLogger (no-echo), so no endless loop
arises.

---

## 6. Use case 4: WSJT-X logs, both logbooks listen

WSJT-X has only one UDP target and MacContestLogger's WSJT reception is unicast-only, so this
is solved by a **chain through RUMlog** (not by WSJT multicast):

```
WSJT-X ──WSJT-X proto (2237)──► RUMlogNG ──N1MM contactinfo (12061)──► MacContestLogger
                                    │
                                  (logs)                              (logs)
```

| Application | Setup |
|---|---|
| **WSJT-X** | UDP Server = `127.0.0.1:2237` |
| **RUMlogNG** | reception from WSJT-X on `2237`; N1MM broadcast target = `127.0.0.1:12061` |
| **MacContestLogger** | WSJT → "Příjem N1MM / RUMlog" **on**, bind `0.0.0.0:12061`; WSJT reception **off** (2237 is held by RUMlog); **an active contest** |

Flow: WSJT-X logs → RUMlog imports and logs → RUMlog broadcasts over N1MM → MacContestLogger
imports and logs. **Both logbooks have the QSO.**

> **Note / future improvement:** direct WSJT-X → both logbooks at once (without RUMlog as an
> intermediary) would work only through a **multicast** group that both recipients join.
> MacContestLogger's WSJT-X reception is so far **unicast-only**, so it cannot do this direct
> variant; adding multicast support to WSJT reception is a candidate for a separate feature.
> Until then, the chain through RUMlog is the recommended way.

---

## 7. Quick port table (one machine)

| Port | Who binds (listens) | Protocol |
|---|---|---|
| `2237` | RUMlog **or** MacContestLogger (WSJT reception), only one at a time | WSJT-X |
| `12061` | MacContestLogger (N1MM reception) | N1MM contactinfo |
| `12060` | RUMlog (its own N1MM broadcast/monitor) | N1MM contactinfo |

**Golden rule:** decide in every scenario who owns **2237**. If RUMlog has it,
MacContestLogger receives from RUMlog over **N1MM on 12061** and sends to RUMlog over the
**WSJT-X protocol on 2237**.

## WSJT-X decodes (Decode List)

When **reception from WSJT-X** is on, MCL processes decodes and the WSJT-X state in addition
to logged QSOs. The window **Okna → WSJT-X dekódy** (Windows → WSJT-X decodes) shows them
colored by the active contest (like the bandmap):

- grey = dupe, blue = new QSO, red = new multiplier, green = multiple multipliers,
- filters "Jen CQ" (CQ only), "Skrýt dupe" (Hide dupes), "Jen násobiče" (Multipliers only),
- **double-click** on a row sends WSJT-X a *Reply* message: WSJT-X calls the station as if you
  double-clicked in its Band Activity window (WSJT-X must have "Accept UDP requests" enabled).

The decode frequency = the VFO frequency from WSJT-X + the audio offset; the band is
determined from it.

---

## N1MM broadcast packets (Settings → Broadcast Data)

Every packet type is off by default and is sent only to the `host:port` targets you enter. A subnet
broadcast address such as `192.168.1.255:12060` works (the socket has `SO_BROADCAST`).

| Packet | Sent | Contents |
|---|---|---|
| `contactinfo` / `contactreplace` / `contactdelete` | a QSO logged, edited, deleted | N1MM's full tag list: band, frequencies, operator, call, country and WPX prefix, sent/received RST and serial, the received exchange (`exchange1`) and its parts by meaning (`gridsquare`, `zone`, `section`, `qth`, `name`, `power`, `prec`, `ck`), points, multiplier flag, `radionr` / `run1run2`, `IsRunQSO`, `IsOriginal`, station name, ID and `SentExchange` |
| `RadioInfo` | every 10 s and on every change | radio number, RX and TX frequency (split), mode, own call, operator, Run/S&P, selected antenna, focus/active radio, stereo, split, transmitting, rig name, aux antenna; in SO2R one packet per radio (`RadioNr` 1 and 2) |
| `dynamicresults` | every 10 s in a contest | contest, call, operators, the category class, club, QTH (country, zones, section, state, grid), a breakdown of QSOs and points per band and mode with QSO/point/multiplier totals, score |
| `AppInfo` | when the broadcast starts | database, contest, station |
| `spot` (Spots) | a spot appears in or leaves the band map | DX call, frequency (kHz), spotter, `add`/`delete`, mode, comment, status for this station (`dupe`, `single`/`double`/`triple mult`, `new qso`) and the status list (adds `cq`) |
| `lookupinfo` (Lookup) | Space in the call field, before logging | the `contactinfo` tag list for the typed call (prefixes, frequency, mode, operator) |

The exchange parts come from the contest definition's received fields: a `LOCATOR` field goes to
`gridsquare`, a CQ/ITU zone to `zone`, a state, province, district, HQ or IOTA reference to `qth`, and
fields whose id is `sec`/`section`, `name`, `power`/`pwr`, `prec` or `ck`/`check` to those tags.

**All QSOs** (a check box under the packet rows) forwards contacts this station did not log to the
Contacts targets with `IsOriginal` set to `False`: QSOs the station network (MQTT cluster) brings in from
other stations, and `contactinfo` packets received from other loggers (N1MM receive). A packet that already
says `IsOriginal False` is never forwarded again, so two stations that both forward cannot start a packet
storm.

**Shared receive port.** The N1MM and ADIF receivers (WSJT/JTDX tab) have a *Share the port with other
applications* switch: the socket is bound with `SO_REUSEADDR`/`SO_REUSEPORT`, so another program can listen
on the same port. Broadcast datagrams (to `x.x.x.255`) reach every listener; a unicast datagram reaches only
one of them, so send to the subnet broadcast address when several programs share a port.
