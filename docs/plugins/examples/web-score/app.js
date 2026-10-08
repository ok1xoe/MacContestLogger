"use strict";
// window.mcl is the app's bridge: request(method, params) → Promise, on(event, handler).
// Texts from the log go in with textContent (never innerHTML): QSO and spot fields are untrusted data.
  async function refresh() {
    const score = await window.mcl.request("contest.score");
    const rig = await window.mcl.request("rig.state");
    document.getElementById("rig").textContent = rig ? `${rig.band || "?"} ${rig.mode || ""}` : "";
    const body = document.querySelector("#bands tbody");
    body.textContent = "";
    if (!score) {
      document.getElementById("title").textContent = "No contest";
      document.getElementById("total").textContent = "";
      return;
    }
    document.getElementById("title").textContent = score.contestId;
    for (const band of score.bands) {
      const row = body.insertRow();
      for (const value of [band.band, band.qsos, band.points, band.mults]) {
        row.insertCell().textContent = value;
      }
    }
    document.getElementById("total").textContent = `Total ${score.total} (${score.qsos} QSOs, ${score.mults} mults)`;
  }
  for (const event of ["qso-logged", "qso-edited", "qso-deleted", "contest-opened", "contest-closed", "band-changed"]) {
    window.mcl.on(event, refresh);
  }
  refresh().catch((error) => { document.getElementById("total").textContent = error.message || String(error); });
