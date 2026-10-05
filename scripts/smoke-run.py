#!/usr/bin/env python3
"""Launches the app bundle for a scripted or exploratory smoke run, isolated from the user's own setup.

    scripts/smoke-run.py [--app build/app/MacContestLogger.app] [--data DIR] [--keep] [-- APP ARGS...]

- A copy of the bundle, re-signed ad hoc under the throwaway bundle identifier cz.ok1xoe.maccontestlogger.smoke:
  whatever AppKit writes into the defaults domain (window frames, the open/save panels' last folder) or the saved
  application state lands there and is removed at the end. The user's own `cz.ok1xoe.maccontestlogger` domain is
  never touched.
- MCL_INERT_HARDWARE=1 and MCL_INERT_NETWORK=1: no rig, serial port, audio device, cluster or callbook service.
- A temporary MCL_DATA_DIR, or --data DIR (kept; the user's own data directory, anything inside it or any directory
  holding it is refused).
- The app runs as this script's child; its pid is printed. Signal only that pid, or this script: SIGINT, SIGTERM and
  SIGHUP sent to the script are passed on to the app (its regular quit) while it is an unreaped child. When the
  script ends, a still running app is killed.
- Further MCL_* variables of the caller (MCL_SMOKE_LANGUAGE, MCL_QUIT_TRACE, ...) pass through.
- Refuses to run while the screen is locked (or its state is unreadable). Sends no input events.
"""
import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True  # no __pycache__ next to the scripts
from mcl_launch import clean_domain, prepare_bundle, screen_locked, signal_child, unsafe_data_dir

DOMAIN = "cz.ok1xoe.maccontestlogger.smoke"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="build/app/MacContestLogger.app")
    parser.add_argument("--data", default=None, help="data directory to use (kept); default: a temporary one")
    parser.add_argument("--keep", action="store_true", help="keep the temporary directory")
    parser.add_argument("app_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    app_args = args.app_args[1:] if args.app_args[:1] == ["--"] else args.app_args

    if screen_locked():
        print("smoke-run: the screen is locked (or its state is unreadable); not launching the app", file=sys.stderr)
        return 2
    if not os.path.isdir(args.app):
        print(f"smoke-run: no app bundle at {args.app} (scripts/bundle.sh --config debug)", file=sys.stderr)
        return 2
    if args.data is not None:
        reason = unsafe_data_dir(args.data)
        if reason:
            print(f"smoke-run: refusing --data {args.data}: {reason}", file=sys.stderr)
            return 2

    work = tempfile.mkdtemp(prefix="mcl-smoke-")
    process = None
    try:
        clean_domain(DOMAIN)
        executable = prepare_bundle(args.app, work, DOMAIN)
        data = args.data if args.data is not None else os.path.join(work, "data")
        os.makedirs(data, exist_ok=True)
        env = dict(os.environ, MCL_INERT_HARDWARE="1", MCL_INERT_NETWORK="1", MCL_DATA_DIR=data)
        process = subprocess.Popen([executable] + app_args, env=env)

        def forward(signo, _frame):
            signal_child(process, signo)

        for signo in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signo, forward)
        print(f"smoke-run: pid {process.pid}, data {data}, defaults domain {DOMAIN}", flush=True)
        status = process.wait()
        print(f"smoke-run: the app ended with status {status}")
        return 0 if status == 0 else 1
    finally:
        for signo in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signo, signal.SIG_DFL)
        if process is not None and signal_child(process, signal.SIGKILL):
            process.wait()
        clean_domain(DOMAIN)
        if args.keep:
            print(f"smoke-run: kept {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
