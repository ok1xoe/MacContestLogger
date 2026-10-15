# Multi-op and the network

The network logbook (an MQTT broker plus the authority, a separate Java application
(cluster-app, Java 21) that is not part of this repository) shares operating information between the
stations in addition to QSOs.

## Network Status

![Network status: stations, their bands and contacts](img/network-status.png)

**Okna → Stav sítě** (Windows → Network Status) shows all stations of the network logbook:
station ID, operator, station type (RUN, RUN1, RUN2, MULT), band, mode, frequency, Run/S&P,
pass frequency (Alt+Z), QSO count, the rate of the last 10 and last 100 QSOs, the last QSO
(call and UTC time) and state. The rates and the last QSO are computed from the shared log
(every QSO carries the ID of the station that logged it).

**Sloupce** (Columns) at the top of the window shows or hides columns, moves them left or right
(*Pořadí sloupců*, Column order) and returns to the default set (N1MM: right-click on the
header). The choice is saved.

The state column says:

- **online**: the station reports in (a heartbeat every 30 s, immediately on a change),
- **vysílá** (transmitting): the station is transmitting right now (shown in red),
- **neaktivní N s** (inactive N s): no heartbeat for more than 90 s,
- **offline**: the station disconnected or lost its connection (MQTT Last Will).

The state is retained on the broker (`station/status/<stationId>`), so a newly connected
station sees the others immediately. The broker ACL lets a station write only its own state
(see `docs/cluster-aclfile`).

### Messages tab

**Zprávy** (Messages; N1MM Messages tab) lists every network message this station sent (→) or
received (←) with its UTC time, station, type and content — a trace for finding network
problems; **Vymazat** (Clear) empties it.

On connecting, each station sends its **setup** to the others: program version, the open
contest and the operator/transmitter category of the contest setup (and again whenever it
changes). When another online station differs, the Messages tab shows a red warning (and the
tab label a ⚠), and the status line announces each new difference once (N1MM configuration
mismatch warnings).

### Actions tab

**Akce** (Actions; N1MM Actions tab):

- **Volat o pomoc** (Call for Help): all stations or one station hear an alert sound and see
  "POMOC: stanice OP1 volá o pomoc" (HELP: station OP1 is calling for help) in the status line.
- **Pass frekvence** (Pass frequency): the same as Alt+Z (see below).
- **Resetovat pořadová čísla na všech stanicích** (Reset serial numbers at all stations): every
  station continues after the highest serial number sent in the log (never lower than its own
  next number).
- **Synchronizovat čas z master stanice** (Synchronise the time from the master station), see
  below.

### Master station and time

N1MM keeps the clocks of all computers in sync from the **master** station. In MCL,
**Nastavení → Cluster** (Settings → Cluster) has:

- **Master stanice** (Master station): this station answers the others' time requests with its
  clock (corrected by its own NTP check when *QSO time correction* is on).
- **Čas QSO podle hodin master stanice** (QSO time from the master station's clock): this
  station asks the master for its time when it appears and then every 10 minutes, measures the
  difference NTP-style (half of the round trip) and corrects the time of new QSOs by it, the same
  way the NTP correction does. The computer's clock itself is not changed (that would need
  administrator rights); the NTP check keeps measuring but its offset is not applied while the
  master's time is in use.

## Chat

![Chat between stations](img/chat.png)

**Okna → Chat** (N1MM Messaging, DXLog Gab): messages to all stations or to one
(selected above the message line; it offers the stations from Network Status). Enter sends.
An incoming message also appears in the status line. Messages go through the broker on
`station/msg` (QoS 1, not retained, so offline stations do not receive them).

## Passing stations (pass)

A station you cannot work yourself (for example a multiplier on another band) is passed to a
station that is on the right band:

1. type the callsign into the callsign field,
2. press **Ctrl+Alt+P**. If exactly one other station is online, the callsign goes straight to
   it; otherwise **Stav sítě** opens and you click **Předat** (Pass) at the target station.

The recipient gets the callsign in its **bandmap** at its own frequency (spotter
`PASS-<station>`), in the chat and in the status line; the text also contains the frequency
of the passing station.

**Pass frequency (Alt+Z).** A station can announce where it takes passed stations: **Alt+Z**
asks for the frequency in kHz (the current one is offered; empty = clear) and sends it to all
stations. A call passed to that station then lands in its bandmap on the pass frequency instead
of its current one. Older versions only show the announcement as a line in the chat.

## Partner and call stacking

![Partner window with the call stack](img/partner.png)

**Okna → Partner** (DXLog Partner, N1MM call stacking) is for the second operator who
listens to the pileup on the same rig or on a second receiver:

- selects a runner (an online station) and sees its band, mode, frequency and **what the
  runner is currently typing into the callsign field**,
- types a callsign and sends it with Enter to the **runner's stack**.

The runner sees the stack in the entry window ("ZÁSOBNÍK DL1ABC K1ZZ (Alt+G)", that is, "STACK ...")
and **Alt+G** (or **Ctrl+Alt+K**) puts the next callsign into the field. The partner's calls join
the runner's own [call stack](call-stacking.md) — one stack of at most 10 callsigns without
duplicates and without dupes, in the order chosen in Settings → Function Keys → Call stacking; with
the Next Call key, ESM works them one after the other (`{LOGTHENPOP}`).

When the runner logs a callsign the partner put on its stack, the callsign is wiped from the
partner's entry windows (N1MM: wipe the callsign when it is logged by the stack target).

## Log and export

While the network logbook is in use, the Log window shows two more columns: **Op** (the operator
of the QSO) and **Stn** (the station ID that logged it; N1MM's Op and R# columns).

**Soubor → Export → ADIF podle data…** (File → Export → ADIF by date) has a **Stanice sítě** (Network station) choice
when the log holds QSOs of several stations: the ADIF then contains only the QSOs of that
station (N1MM *Export ADIF by multi-user station name*).

## Multi-user macros

The function key messages can use N1MM's multi-user macros `{MESSAGE}`, `{PASS …}`,
`{PASSMSG …}` and `{LASTPASSEDFREQ}` (see [CW keyer → macros](cw-keyer.md)). They work only
while the network logbook is connected; the text after `{MESSAGE}` is never transmitted.

## Interlock / TX lockout

**Nastavení → Cluster → TX interlock** (Settings → Cluster → TX interlock):

- **Kdekoli (jeden signál)** (Anywhere, one signal): for categories with one signal at a time
  (M/S, M/2): when any other station transmits, this one does not transmit,
- **Na stejném pásmu** (On the same band): inband operation (DXLog "Interlock and inband
  operation"): only stations on the same band are blocked.

CW (function keys, ESM, CW from the keyboard), the voice keyer, digital transmission and
tuning with a carrier are blocked; the status line shows "TX LOCKOUT: vysílá STN2"
(transmitting). The start of a transmission is announced to the others immediately, the end
within 1 s. The interlock goes over the network (the broker), so it has a latency of tens of
ms. It does not replace a hardware lock (for example a switch with a PTT interlock) when two
stations press the key at the same moment.

## Serial number server

When several stations send serial numbers from a **common series** (M/S, M/2), two stations
could send the same number at the same time. **Nastavení → Cluster → Pořadová čísla ze serial
number serveru** (Settings → Cluster → Serial numbers from the serial number server) solves
this the way N1MM/DXLog do:

- the authority issues numbers from one series: 1 + max(the highest sent number in the log,
  the last issued one),
- the station has the number for the next QSO **reserved in advance** (request
  `serial/request`, reply `serial/reply/<stationId>`); after a QSO is written it asks for the
  next one immediately,
- until the reservation arrives (the authority is not running, a network outage), the station
  counts locally (local-first) and the entry window shows "SNS: čekám na číslo" (waiting for
  a number).

An issued but unused number (a reservation at the end of the contest) stays as a gap in the
series, as in N1MM. After the authority restarts, the series continues from the highest
logged number.

## Station type (RUN / MULT) and band change rules

**Nastavení → Cluster** (Settings → Cluster):

- **Typ stanice** (Station type; DXLog Station type): *RUN* or *MULT*. A MULT station may only
  log a QSO that brings a new multiplier. The others see the type in Network Status.
  In Multi-two a RUN station can be numbered **Run1** or **Run2** (N1MM Run1/Run2); the others
  then see *RUN1* / *RUN2*.
  **Ctrl+Alt+M** switches between RUN and MULT from the keyboard (N1MM Run/Mult). The Info window shows the type
  below its timers (N1MM's MULT/RUN indicator).
- **Pravidla provozu při zápisu** (Operating rules on write): *Nehlídat* (Do not check) /
  *Upozornit* (Warn, the default) / *Nezapsat* (Do not log). The tool checks the N-minutes-on-a-band
  rule (for example CQ WW M/S 10 min) and the limit of band changes per hour (for example
  CQ WPX M/S 10/h) according to the rules of the **selected category** in the contest
  definition. With *Nezapsat*, a write goes through only with **Ctrl+Alt+Enter**.

Only the QSOs of **this station** are counted (in the network logbook not the QSOs of the
others), so the run and mult stations each have the rule separately. The timer of time on a
band and the counter of changes stay in the Rate window.
