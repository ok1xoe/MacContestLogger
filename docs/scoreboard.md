# Online scoreboard

Equivalent of N1MM / DXLog **Score Reporting**. **"Nastavení → Score Reporting"**
(Settings → Score Reporting):

- **"Odesílat průběžné skóre"** (Send running score) — turns sending on (only in a
  contest, only after the log changes).
- **Scoreboard**: a preset or a custom URL. Presets: contestonlinescore.com
  (default), contest.run (`http://contest.run`), Score Distributor
  (`http://scoredistributor.net`, forwards the score to the online scoreboards)
  and hamscore.com. contest.run and Score Distributor are plain HTTP only. A
  previously saved URL that matches no preset is kept and shown as a custom URL.
  contest.run expects its own contest ids (e.g. `CQ-WW-RTTY`, `RDXC`) in
  `<contest>`; its answer "Contest or alias not found" means the contest name
  differs.
- **Interval** (minimum 2 minutes, default 5).
- **"Rozpad po pásmech a módech"** (Breakdown by bands and modes) — QSOs, points
  and multipliers for each band × mode.
- **"Odeslat teď"** (Send now) saves the settings and sends the score immediately;
  below the button is the status of the last send (HTTP code, with the reason the
  server gives for a rejection such as "Contest not supported", or a readable
  error: server unreachable, timed out, invalid address).

An XML `<dynamicresults>` document (contest, callsign, operators, categories from
the contest setup, zones and locator, breakdown, score, UTC time) is sent as the
form `xml=...` with the POST method. The score is recalculated from the whole log
(same as the Score window).

# Club Log Live Stream

Equivalent of N1MM / DXLog **Club Log real-time upload**. **"Nastavení → Score
Reporting → Club Log Live Stream"** (Settings → Score Reporting → Club Log Live
Stream):

- account e-mail, **application password** (clublog.org → Settings → App
  Passwords), log callsign (empty = station callsign) and **API key** (issued by
  Club Log),
- once enabled, each newly logged QSO (not imported ones) is sent as a single ADIF
  record to `clublog.org/realtime.php`,
- when Club Log or the network is unavailable, the QSO stays in the queue and is
  sent after a minute; a rejection (bad login / data) is shown in the status
  below the settings.

Everything sent to Club Log is recorded in `clublog.log` in the data folder (next to
`cat.log`; created by the first upload): the request, the form fields, the ADIF record,
the HTTP status with the first line of the answer, and what happened to the record
(`sent`, `retry in 60 s`, `dropped (rejected)`). The application password and the API
key are written as `***`, the e-mail address as `t***@example.com`.

The queue is in memory — QSOs not sent by the time the application quits must be
uploaded to Club Log manually (ADIF export).

## Posting the result to 3830scores.com

Equivalent of N1MM **Report Score to 3830**. **"Soubor → Odeslat výsledek na 3830…"** (File → Post result to 3830...;
needs an open contest) shows the data of the [3830scores.com](https://www.3830scores.com/) score form for the active
contest:

- call, contest, category (`OPERATOR: …, POWER: …` from the contest setup), operators, locator,
- QSOs, QSO points, multipliers (with the groups when the contest has several), bonus and QTC points when they
  score, and the **claimed score** of the whole log,
- a **Soapbox** field, which starts as the soapbox of the contest setup and can be edited here (it is not written
  back).

**Zkopírovat** (Copy) puts the lines on the clipboard, **Otevřít 3830scores.com** (Open 3830scores.com) opens the
site in the browser. The site has **one form per contest** (linked in its left navigation) with an address that cannot
be built, no documented way to prefill it and no API, so MacContestLogger **posts nothing and stores no credentials**:
open the site, pick the contest's form and paste the copied data. (The real-time scoreboard above is another service.)
