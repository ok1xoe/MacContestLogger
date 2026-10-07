#!/usr/bin/env python3
"""End-to-end quit check of the real app bundle (debug build: it needs the quit trace, see QuitTrace.swift).

    scripts/quit-e2e.py [--app build/app/MacContestLogger.app] [--only NAME ...] [--keep]

Launches the app as a child of this script, never through LaunchServices, and signals only that child's pid.
Every launch is inert: MCL_INERT_HARDWARE=1, MCL_INERT_NETWORK=1 (no rig, serial port, audio device or network
service is touched) and a temporary MCL_DATA_DIR. The bundle is copied and re-signed under its own bundle
identifier, so whatever AppKit writes into the defaults domain or the saved application state lands in a
throwaway domain that is removed at the end; the real `cz.ok1xoe.maccontestlogger` domain is checked before and
after. Before each launch the throwaway domain gets a frame record, as AppKit leaves it; every exit path must remove
it (`defaults read` then finds no domain). No input event of any kind is sent. The script refuses to run while the screen is locked.

Scenarios:
- sigterm: one SIGTERM runs the regular quit: the transmit release (milestone), the quit sequence, a normal exit.
- second-signal: a second SIGTERM shortly after the first exits with 143, never before the transmit release.
- coalesced: three SIGTERMs sent at once (coalesced into one or more requests) still end the app.
- stalled-quit: the quit sequence is held before the transmit release (MCL_DEBUG_STALL_QUIT=1); a second SIGTERM
  is deferred and the 5 s deadline ends the process.
- spot-windows: as sigterm, with the DX cluster, band map, available multipliers and blacklist windows open.
- wedged-single-signal: one SIGTERM only (launchd, a logout) with the quit held before the transmit release: the
  15 s release deadline ends the process through the forced exit, which runs the shutdown hooks and the cleanup.
- terminate: `terminate:` from a run-loop timer (the context of Cmd-Q, MCL_SMOKE_QUIT) runs the quit and exits 0.
- all-windows (sigterm, terminate): every persistent window id of the app in `openWindows` (the tool, radio, spot,
  network and info windows, the world map in its DXCC mode and the seven `mult:<kind>` grids). The regular quit
  must release the transmit, exit 0 and leave `openWindows` and the logbook as they were (windows closing during
  the quit are not the user's; no QSO appears or vanishes).
- all-windows-vfob (sigterm, terminate): as above in SO2V, so the second entry window (VFO B) is open too.
- sheet-open: a fresh data directory (the first-start sheet is attached, so AppKit refuses `terminate:`); one
  SIGTERM still runs the quit sequence and ends the process.
"""
import argparse
import json
import os
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # no __pycache__ next to the scripts
from mcl_launch import (REAL_DOMAIN, clean_domain, preferences_file, prepare_bundle, screen_locked,
                        signal_child)

TEST_DOMAIN = "cz.ok1xoe.maccontestlogger.quit-e2e"
READY_TIMEOUT = 90.0
EXIT_BOUND = 10.0
DEADLINE = 5.0
RELEASE_DEADLINE = 15.0


class Run:
    def __init__(self, executable, work, name, extra_env, config):
        self.config = config or {}
        self.dir = os.path.join(work, name)
        data = os.path.join(self.dir, "data")
        os.makedirs(data)
        if config is not None:
            # An existing databases directory: no first-start sheet (the choice of that directory) is shown.
            databases = os.path.join(data, "databases")
            os.makedirs(databases)
            with open(os.path.join(data, "config.json"), "w", encoding="utf-8") as handle:
                json.dump(dict(config, databasesDir=databases), handle)
        self.trace_path = os.path.join(self.dir, "quit-trace.txt")
        env = dict(os.environ)
        env.update({
            "MCL_INERT_HARDWARE": "1",
            "MCL_INERT_NETWORK": "1",
            "MCL_DATA_DIR": os.path.join(self.dir, "data"),
            "MCL_QUIT_TRACE": self.trace_path,
        })
        env.update(extra_env)
        self.log = open(os.path.join(self.dir, "app.log"), "w")
        self.process = subprocess.Popen([executable], env=env, stdout=self.log, stderr=subprocess.STDOUT,
                                        cwd=self.dir)

    def trace(self):
        try:
            with open(self.trace_path, encoding="utf-8") as handle:
                return [line.rstrip("\n") for line in handle]
        except FileNotFoundError:
            return []

    def wait_for(self, line, timeout):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if line in self.trace():
                return True
            if self.process.poll() is not None:
                return False
            time.sleep(0.1)
        return False

    def signal(self, signo):
        # Only the child this run started, and only while it is unreaped (its pid cannot belong to anyone else).
        signal_child(self.process, signo)

    def wait_exit(self, timeout):
        try:
            return self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

    def finish(self):
        if self.process.poll() is None:
            # Still our unreaped child: sample it (read-only), then kill it.
            subprocess.run(["sample", str(self.process.pid), "1", "-file", os.path.join(self.dir, "sample.txt")],
                           capture_output=True)
            signal_child(self.process, signal.SIGKILL)
            self.process.wait()
        self.log.close()


def index(lines, prefix):
    for number, line in enumerate(lines):
        if line.startswith(prefix):
            return number
    return None


def check_regular_quit(lines, code, problems):
    if code != 0:
        problems.append(f"exit code {code}, expected 0")
    for needed in ("milestone transmitReleased=true", "shutdown finished", "will terminate"):
        if needed not in lines:
            problems.append(f"trace lacks '{needed}'")


def scenario_sigterm(run, problems):
    run.signal(signal.SIGTERM)
    code = run.wait_exit(EXIT_BOUND)
    if code is None:
        problems.append(f"still running {EXIT_BOUND:.0f} s after SIGTERM")
        return
    check_regular_quit(run.trace(), code, problems)


def check_forced_after_release(lines, code, problems):
    if code == 0:
        check_regular_quit(lines, code, problems)
        return
    if code != 128 + signal.SIGTERM:
        problems.append(f"exit code {code}, expected 143 (or 0)")
    released = index(lines, "milestone transmitReleased=true")
    forced = index(lines, "force exit")
    if released is None:
        problems.append("trace lacks the transmit release milestone")
    if forced is None:
        problems.append("trace lacks 'force exit'")
    if released is not None and forced is not None and forced < released:
        problems.append("forced exit before the transmit release")
    if "cleanup done" not in lines:
        problems.append("trace lacks 'cleanup done' (shutdown hooks, frame records)")


def scenario_second_signal(run, problems):
    run.signal(signal.SIGTERM)
    time.sleep(0.05)
    run.signal(signal.SIGTERM)
    code = run.wait_exit(EXIT_BOUND)
    if code is None:
        problems.append(f"still running {EXIT_BOUND:.0f} s after the second SIGTERM")
        return
    check_forced_after_release(run.trace(), code, problems)


def scenario_coalesced(run, problems):
    for _ in range(3):
        run.signal(signal.SIGTERM)
    code = run.wait_exit(EXIT_BOUND)
    if code is None:
        problems.append(f"still running {EXIT_BOUND:.0f} s after three SIGTERMs")
        return
    lines = run.trace()
    if code < 0:
        problems.append(f"killed by signal {-code} (the signal was not handled)")
    elif code == 128 + signal.SIGTERM and index(lines, "force exit") is None:
        problems.append("exit 143 without the forced exit in the trace")


def scenario_stalled_quit(run, problems):
    run.signal(signal.SIGTERM)
    if not run.wait_for("quit stalled", EXIT_BOUND):
        problems.append("the quit did not reach the stall")
        return
    second = time.monotonic()
    run.signal(signal.SIGTERM)
    code = run.wait_exit(DEADLINE + EXIT_BOUND)
    elapsed = time.monotonic() - second
    if code is None:
        problems.append(f"still running {DEADLINE + EXIT_BOUND:.0f} s after the second SIGTERM")
        return
    lines = run.trace()
    if code != 128 + signal.SIGTERM:
        problems.append(f"exit code {code}, expected 143")
    for needed in ("deadline armed 5 s", "deadline expired", "force exit 143", "cleanup done"):
        if needed not in lines:
            problems.append(f"trace lacks '{needed}'")
    if elapsed < DEADLINE - 0.5:
        problems.append(f"exited {elapsed:.1f} s after the second signal, before the deadline")
    if index(lines, "milestone") is not None:
        problems.append("a milestone in a stalled quit")


def scenario_wedged_single_signal(run, problems):
    # launchd / a logout: one SIGTERM only. The quit is held before the transmit release; the release deadline of the
    # first signal still ends the process through the forced exit (shutdown hooks, frame cleanup).
    start = time.monotonic()
    run.signal(signal.SIGTERM)
    code = run.wait_exit(RELEASE_DEADLINE + EXIT_BOUND)
    elapsed = time.monotonic() - start
    if code is None:
        problems.append(f"still running {RELEASE_DEADLINE + EXIT_BOUND:.0f} s after a single SIGTERM")
        return
    lines = run.trace()
    if code != 128 + signal.SIGTERM:
        problems.append(f"exit code {code}, expected 143")
    for needed in ("quit stalled", "deadline armed 15 s", "deadline expired", "force exit 143", "cleanup done"):
        if needed not in lines:
            problems.append(f"trace lacks '{needed}'")
    if elapsed < RELEASE_DEADLINE - 0.5:
        problems.append(f"exited {elapsed:.1f} s after the signal, before the release deadline")


def scenario_terminate(run, problems):
    code = run.wait_exit(EXIT_BOUND + 2)
    if code is None:
        problems.append(f"still running {EXIT_BOUND:.0f} s after terminate:")
        return
    check_regular_quit(run.trace(), code, problems)


def scenario_sheet_open(run, problems):
    # AppKit refuses `terminate:` while a sheet is attached; the signal must still run the quit and end the app.
    run.signal(signal.SIGTERM)
    code = run.wait_exit(EXIT_BOUND)
    if code is None:
        problems.append(f"still running {EXIT_BOUND:.0f} s after SIGTERM with a sheet open")
        return
    lines = run.trace()
    if code != 0:
        problems.append(f"exit code {code}, expected 0")
    for needed in ("milestone transmitReleased=true", "shutdown finished", "exit without AppKit"):
        if needed not in lines:
            problems.append(f"trace lacks '{needed}'")


MULT_KINDS = ["dxcc", "grid", "itu", "cq", "districts", "other", "sections"]
# Every id the app persists in `config.openWindows` (WindowsModel.implemented without `notPersisted`; the world map
# is one window with the two ids, the DXCC one is saved when it was opened in that mode).
ALL_WINDOWS = [
    "log", "defeditor", "catLog", "rotator", "cwkeyboard", "cwreader", "digitalinterface", "waterfall",
    "dxCluster", "bandmap", "availMult", "blacklist", "netstatus", "chat", "partner", "wsjtxdecodes", "hamqthLog",
    "rate", "statistics", "score", "dupesheet", "skeds", "qtc", "bandnotes", "movemults", "propagation",
    "worldmap-dxcc",
] + ["mult:" + kind for kind in MULT_KINDS] + [
    # A plugin window: inert, so its plugin never starts (and this one is not installed); the id must survive the quit.
    "plugin:sample/main",
]
WINDOWS_SETTLE = 4.0  # the scenes of the saved ids open right after the main window is ready


def logbook_counts(data):
    """The number of QSO rows of each logbook of the data directory (a read-only open of the file), by file name."""
    counts = {}
    databases = os.path.join(data, "databases")
    for name in sorted(os.listdir(databases)) if os.path.isdir(databases) else []:
        if not name.endswith(".sqlite"):
            continue
        db = sqlite3.connect("file:" + os.path.join(databases, name) + "?mode=ro", uri=True)
        try:
            counts[name] = db.execute("SELECT COUNT(*) FROM qso").fetchone()[0]
        finally:
            db.close()
    return counts


def scenario_all_windows(how):
    def check(run, problems):
        data = os.path.join(run.dir, "data")
        if how == "sigterm":
            time.sleep(WINDOWS_SETTLE)
            run.signal(signal.SIGTERM)
        # (terminate: the smoke timer fires 6 s after the start, once the windows are open)
        code = run.wait_exit(EXIT_BOUND + 5)
        if code is None:
            problems.append(f"still running {EXIT_BOUND + 5:.0f} s after the quit with every window open")
            return
        check_regular_quit(run.trace(), code, problems)
        with open(os.path.join(data, "config.json"), encoding="utf-8") as handle:
            saved = json.load(handle)
        wanted = run.config["openWindows"]
        if sorted(saved.get("openWindows", [])) != sorted(wanted):
            lost = sorted(set(wanted) - set(saved.get("openWindows", [])))
            extra = sorted(set(saved.get("openWindows", [])) - set(wanted))
            problems.append(f"openWindows changed by the quit: lost {lost}, added {extra}")
        if saved.get("radioMode") != run.config.get("radioMode", saved.get("radioMode")):
            problems.append(f"radioMode changed: {saved.get('radioMode')}")
        if saved.get("databasesDir") != os.path.join(data, "databases"):
            problems.append(f"databasesDir changed: {saved.get('databasesDir')}")
        # Nothing was logged: the logbook (opened read-only after the exit) must hold no QSO.
        after = logbook_counts(data)
        if any(count != 0 for count in after.values()):
            problems.append(f"the logbook gained QSOs during the quit: {after}")
        if not after:
            problems.append("no logbook file in the data directory after the quit")
    return check


SPOT_WINDOWS = {"openWindows": ["log", "dxCluster", "bandmap", "availMult", "blacklist"]}

# (name, extra environment, config.json entries — None: no config, check)
SCENARIOS = [
    ("sigterm", {}, {}, scenario_sigterm),
    ("second-signal", {}, {}, scenario_second_signal),
    ("coalesced", {}, {}, scenario_coalesced),
    ("stalled-quit", {"MCL_DEBUG_STALL_QUIT": "1"}, {}, scenario_stalled_quit),
    ("wedged-single-signal", {"MCL_DEBUG_STALL_QUIT": "1"}, {}, scenario_wedged_single_signal),
    ("terminate", {"MCL_SMOKE_QUIT": "1"}, {}, scenario_terminate),
    # More windows open (the spot and cluster windows), as in a contest.
    ("spot-windows", {}, SPOT_WINDOWS, scenario_sigterm),
    # Every persistent window open (also as the quit check of the window restore), and the same with VFO B (SO2V).
    ("all-windows-sigterm", {}, {"openWindows": ALL_WINDOWS}, scenario_all_windows("sigterm")),
    ("all-windows-terminate", {"MCL_SMOKE_QUIT": "6"}, {"openWindows": ALL_WINDOWS}, scenario_all_windows("terminate")),
    ("all-windows-vfob-sigterm", {}, {"openWindows": ALL_WINDOWS, "radioMode": "SO2V"},
     scenario_all_windows("sigterm")),
    ("all-windows-vfob-terminate", {"MCL_SMOKE_QUIT": "6"}, {"openWindows": ALL_WINDOWS, "radioMode": "SO2V"},
     scenario_all_windows("terminate")),
    # A fresh data directory: the first-start sheet (the choice of the databases directory) is open.
    ("sheet-open", {}, None, scenario_sheet_open),
]


def clean_test_domain():
    clean_domain(TEST_DOMAIN)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="build/app/MacContestLogger.app")
    parser.add_argument("--only", nargs="*", default=None)
    parser.add_argument("--keep", action="store_true", help="keep the temporary directory (logs, traces)")
    args = parser.parse_args()

    if sys.platform != "darwin":
        print("quit-e2e: macOS only", file=sys.stderr)
        return 2
    if screen_locked():
        print("quit-e2e: the screen is locked (or its state is unreadable); not launching the app", file=sys.stderr)
        return 2
    if not os.path.isdir(args.app):
        print(f"quit-e2e: no app bundle at {args.app} (scripts/bundle.sh --config debug)", file=sys.stderr)
        return 2

    real_prefs_before = os.path.exists(preferences_file(REAL_DOMAIN))
    work = tempfile.mkdtemp(prefix="mcl-quit-e2e-")
    failures = 0
    try:
        clean_test_domain()
        executable = prepare_bundle(args.app, work, TEST_DOMAIN)
        for name, extra_env, config, check in SCENARIOS:
            # `--only all-windows` selects the group (all-windows-sigterm, all-windows-vfob-terminate, ...).
            if args.only and not any(name == only or name.startswith(only + "-") for only in args.only):
                continue
            # A frame record as AppKit leaves it after a window moved: every exit path removes it (the panels' last
            # folder is the user's and stays; the throwaway domain is removed by this script).
            subprocess.run(["defaults", "write", TEST_DOMAIN, "NSWindow Frame main", "10 10 800 500 0 0 1440 900 "],
                           check=True)
            run = Run(executable, work, name, extra_env, config)
            problems = []
            try:
                if not run.wait_for("ready", READY_TIMEOUT):
                    problems.append(f"no 'ready' in the trace within {READY_TIMEOUT:.0f} s "
                                    "(a debug bundle is needed)")
                else:
                    check(run, problems)
            finally:
                run.finish()
            time.sleep(1.0)  # cfprefsd writes the domain's file asynchronously
            left = subprocess.run(["defaults", "read", TEST_DOMAIN], capture_output=True, text=True)
            if left.returncode == 0:
                problems.append("the defaults domain was left behind: " + " ".join(left.stdout.split()))
            # (A domain whose keys were all removed keeps an empty plist of cfprefsd; it holds nothing and goes here.)
            clean_test_domain()
            status = "ok" if not problems else "FAILED"
            print(f"{name}: {status}")
            for problem in problems:
                print(f"  - {problem}")
            if problems:
                failures += 1
                print("  trace: " + " | ".join(run.trace()))
    finally:
        clean_test_domain()
        if not real_prefs_before and os.path.exists(preferences_file(REAL_DOMAIN)):
            # Reported, never deleted: it is the user's (the real app may have been started meanwhile).
            print(f"quit-e2e: the user's {REAL_DOMAIN} defaults domain appeared during the run; left untouched")
            failures += 1
        if args.keep:
            print(f"kept: {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)
    print("quit-e2e: " + ("all passed" if failures == 0 else f"{failures} failed"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
