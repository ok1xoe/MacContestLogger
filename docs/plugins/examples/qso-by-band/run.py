#!/usr/bin/env python3
"""Example window plugin: the QSOs of the active contest (or of free logging) counted by band and mode.

Install: copy this directory and docs/plugins/mcl.py into <data directory>/plugins/qso-by-band/, then choose
Window -> Custom -> QSOs by band.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# mcl.py next to this file (installed), else the one in the repository's docs/plugins.
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..")]
import mcl  # noqa: E402

plugin = mcl.Plugin()
state = {"by_mode": True}


def refresh(_=None):
    result = plugin.request("log.query", limit=10000)
    counts = {}
    modes = []
    for qso in result["qsos"]:
        band = qso.get("band") or "?"
        mode = (qso.get("mode") or "?") if state["by_mode"] else "QSOs"
        if mode not in modes:
            modes.append(mode)
        counts.setdefault(band, {}).setdefault(mode, 0)
        counts[band][mode] += 1
    contest = plugin.request("contest.active")
    title = (contest["name"] or contest["id"]) if contest else "Free logging"
    rows = []
    for band in sorted(counts, key=band_order):
        cells = [band] + [counts[band].get(mode, 0) for mode in modes] + [sum(counts[band].values())]
        rows.append(mcl.row(cells, id=band))
    total = [mcl.cell("Total", "title")] + [
        mcl.cell(sum(counts[b].get(mode, 0) for b in counts), "title") for mode in modes
    ] + [mcl.cell(result["total"], "title")]
    rows.append(mcl.row(total))
    columns = [mcl.column("Band")] + [mcl.column(mode, "right") for mode in modes] + [mcl.column("All", "right")]
    plugin.set_window("main", [
        mcl.text(title, style="title"),
        mcl.toggle("by-mode", "Split by mode", state["by_mode"]),
        mcl.table(columns, rows, id="bands") if result["qsos"] else mcl.text("No QSOs yet", style="muted"),
        mcl.button("refresh", "Refresh"),
    ])


def band_order(band):
    # Longest wavelength first: 160m, 80m, ..., 10m, 6m, 2m, 70cm.
    try:
        number = float(band.rstrip("cm"))
        return -number * (0.01 if band.endswith("cm") else 1)
    except ValueError:
        return 0


@plugin.on_change("by-mode")
def by_mode(event):
    state["by_mode"] = bool(event.get("value"))
    refresh()


@plugin.on_click("bands")
def band_clicked(event):
    plugin.log(f"band {event.get('rowId')} clicked")


plugin.on_start(refresh)
plugin.on_click("refresh")(refresh)
for name in ("qso-logged", "qso-edited", "qso-deleted", "contest-opened", "contest-closed"):
    plugin.on(name)(refresh)

if __name__ == "__main__":
    plugin.run()
