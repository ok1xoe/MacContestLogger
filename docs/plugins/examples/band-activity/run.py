#!/usr/bin/env python3
"""Example window plugin using the acting permissions: QSOs per band as a bar chart (click a bar: QSY to the band),
the last calls (double-click: into the entry window), and a key action that puts the last call into the entry.

Install: copy this directory and docs/plugins/mcl.py into <data directory>/plugins/band-activity/, choose
Window -> Custom -> Band activity and allow "entry" and "rig" when asked. Bind the action in Settings -> Keys.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..")]
import mcl  # noqa: E402

BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
# Where a click on a bar tunes (the CW end of the band).
QSY = {"160m": 1_830_000, "80m": 3_530_000, "40m": 7_030_000, "20m": 14_030_000, "15m": 21_030_000,
       "10m": 28_030_000}
WIDTH, HEIGHT, BAR = 420, 160, 60

plugin = mcl.Plugin()
state = {"recent": []}


def refresh(_=None):
    result = plugin.request("log.query", limit=10000, order="desc")
    counts = {band: 0 for band in BANDS}
    for qso in result["qsos"]:
        if qso.get("band") in counts:
            counts[qso["band"]] += 1
    state["recent"] = [qso["call"] for qso in result["qsos"][:10]]
    top = max(counts.values()) or 1
    shapes = []
    for index, band in enumerate(BANDS):
        height = (HEIGHT - 40) * counts[band] / top
        x = 10 + index * (BAR + 8)
        shapes.append(mcl.rect(x, HEIGHT - 20 - height, BAR, height, style="mult", fill=True))
        shapes.append(mcl.label(x + 4, HEIGHT - 18, band, style="muted", size=11))
        shapes.append(mcl.label(x + 4, HEIGHT - 36 - height, counts[band], size=11))
    plugin.set_window("main", [
        mcl.text("QSOs per band — click a bar to QSY", style="title"),
        mcl.canvas(shapes, width=WIDTH, height=HEIGHT, id="bands",
                   label=", ".join(f"{band} {counts[band]}" for band in BANDS)),
        mcl.text("Last calls (double-click: into the entry)", style="muted"),
        mcl.list_([mcl.item(call, id=call) for call in state["recent"]], id="recent"),
    ])


@plugin.on_click("bands")
def bar_clicked(event):
    x = (event.get("value") or {}).get("x", -1)
    index = int((x - 10) // (BAR + 8))
    if 0 <= index < len(BANDS):
        try:
            plugin.request("rig.qsy", freqHz=QSY[BANDS[index]])
        except mcl.PluginError as error:
            plugin.log(f"QSY refused: {error.message}")


@plugin.on_click("recent", double=True)
def call_clicked(event):
    if event.get("rowId"):
        plugin.request("entry.setCall", call=event["rowId"])


@plugin.on_key("last-call")
def last_call(_):
    if state["recent"]:
        plugin.request("entry.setCall", call=state["recent"][0])


plugin.on_start(refresh)
for name in ("qso-logged", "qso-edited", "qso-deleted", "contest-opened", "contest-closed"):
    plugin.on(name)(refresh)

if __name__ == "__main__":
    plugin.run()
