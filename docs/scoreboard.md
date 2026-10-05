# Online scoreboard

Equivalent of N1MM / DXLog **Score Reporting**. **"Nastavení → Score Reporting"**
(Settings → Score Reporting):

- **"Odesílat průběžné skóre"** (Send running score) — turns sending on (only in a
  contest, only after the log changes).
- **Scoreboard**: contestonlinescore.com or cqcontest.net, or a custom URL.
- **Interval** (minimum 2 minutes, default 5).
- **"Rozpad po pásmech a módech"** (Breakdown by bands and modes) — QSOs, points
  and multipliers for each band × mode.
- **"Odeslat teď"** (Send now) saves the settings and sends the score immediately;
  below the button is the status of the last send (HTTP code or error).

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

The queue is in memory — QSOs not sent by the time the application quits must be
uploaded to Club Log manually (ADIF export).
