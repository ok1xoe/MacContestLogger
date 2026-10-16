#!/usr/bin/env python3
"""Captures the user guide's screenshots from the running app (see docs/screenshots.md, "Native captures").

    scripts/native-shots/shoot.py --lang cs|en [--only scenario,...] [--out DIR] [--app build/app/MacContestLogger.app]

For every scenario of scripts/native-shots/scenarios/*.json: a demo data directory with a synthetic log
(`mcl-synthlog`), a fake DX cluster (and for multi-op a throwaway mosquitto broker with fictitious peer stations) on
127.0.0.1 ephemeral ports, the app started through scripts/smoke-run.py with MCL_DEMO_DIR (honoured only together with
MCL_INERT_HARDWARE and MCL_INERT_NETWORK, which smoke-run.py always sets), the windows captured with `screencapture -l`
at the scheduled times, the app quit. No input events are sent. Output: DIR/<name>.png (default build/native-shots/<lang>).

Work files go to $MCL_SHOTS_WORK (default /tmp/mcl-demo): that path is visible in a few windows (the definition editor
shows its contest directory), so it is kept short and neutral.
"""
import argparse
import glob
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
WORK = os.environ.get("MCL_SHOTS_WORK", "/tmp/mcl-demo")
BIN = os.path.join(WORK, "bin")
STATION = {
    "call": "OK1DEMO", "name": "Demo Station", "gridSquare": "JO70FC", "cqZone": "15", "ituZone": "28",
    "country": "Czech Republic", "city": "Praha", "operator": "OK1DEMO", "power": "100", "antenna": "Yagi",
}


def tool(name):
    """Compiles a Swift helper (window list, image tools) once into WORK/bin."""
    out = os.path.join(BIN, name)
    src = os.path.join(HERE, name + ".swift")
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src):
        os.makedirs(BIN, exist_ok=True)
        subprocess.run(["swiftc", "-O", src, "-o", out], check=True)
    return out


def synthlog():
    subprocess.run(["swift", "build", "--product", "mcl-synthlog"], cwd=REPO, check=True, stdout=subprocess.DEVNULL)
    return os.path.join(REPO, ".build", "debug", "mcl-synthlog")


def set_path(config, key, value):
    target = config
    parts = key.split(".")
    for part in parts[:-1]:
        target = target.setdefault(part, {})
    target[parts[-1]] = value


def prepare(scenario, lang, data):
    """The data directory: contest data, a synthetic log, config.json with the demo station and the windows."""
    if os.path.exists(data):
        shutil.rmtree(data)
    os.makedirs(os.path.join(data, "databases"))
    shutil.copytree(os.path.join(REPO, "contest-data"), os.path.join(data, "contest-data"))
    log = scenario["log"]
    name = log["contest"].upper().replace("-", " ").replace("CQ WW", "CQWW") + " 2026"
    db = os.path.join(data, "databases", name + ".sqlite")
    low, high = [int(x) for x in log.get("gap", "20-100").split("-")]
    start = int(time.time() - log["count"] * (low + high) / 2.0 - 120)
    subprocess.run([synthlog(), db, "--contest-data", os.path.join(REPO, "contest-data"), "--count", str(log["count"]),
                    "--seed", str(log.get("seed", 1)), "--start-epoch", str(start), "--contest", log["contest"],
                    "--call", STATION["call"], "--zone", "15", "--mode", log["mode"], "--gap", log.get("gap", "20-100"),
                    "--no-measure"], check=True, stdout=subprocess.DEVNULL)
    config = {
        "language": lang, "databasesDir": os.path.join(data, "databases"), "lastDatabase": name,
        "autoReloadLastContest": True, "station": dict(STATION),
        "rig": {"modelLabel": "Radio 1"}, "rig2": {"modelLabel": "Radio 2", "port": 4534},
        "openWindows": scenario.get("windows", []), "windowGeometry": scenario.get("geometry", {}),
        "dxCluster": {"favorites": [{"name": "DEMO-9", "host": "dxc.example.net", "port": 7300, "login": "OK1DEMO",
                                     "password": "", "parallel": False}], "lastFavorite": "DEMO-9"},
    }
    for key, value in scenario.get("config", {}).items():
        set_path(config, key, value)
    json.dump(config, open(os.path.join(data, "config.json"), "w"), indent=1, ensure_ascii=False)
    for command in scenario.get("before", []):
        subprocess.run(command.replace("$DATA", data), shell=True, check=True)
    return db


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def windows(pid):
    out = subprocess.run([tool("wins"), str(pid)], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 6:
            rows.append({"id": parts[0], "title": parts[5]})
    return rows


def run(scenario_path, lang, outdir, app):
    scenario = json.load(open(scenario_path))
    name = os.path.splitext(os.path.basename(scenario_path))[0]
    data = os.path.join(WORK, f"{name}-{lang}")
    run_dir = data + ".run"
    shutil.rmtree(run_dir, ignore_errors=True)
    os.makedirs(run_dir)
    os.makedirs(BIN, exist_ok=True)
    db = prepare(scenario, lang, data)
    children = []
    try:
        port_file = os.path.join(run_dir, "cluster.port")
        children.append(subprocess.Popen(["python3", os.path.join(HERE, "fake_cluster.py"), "--port-file", port_file,
                                          "--mode", scenario["log"]["mode"], "--log", db],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        for _ in range(50):
            if os.path.exists(port_file) and open(port_file).read():
                break
            time.sleep(0.1)
        demo = {"clusterPort": int(open(port_file).read()), "connectCluster": "DEMO-9", "connectRigs": True}
        audio = scenario.get("audio")
        if audio:
            wav = os.path.join(BIN, audio + ".wav")
            if not os.path.exists(wav):
                subprocess.run(["python3", os.path.join(HERE, audio + "_wav.py"), wav], check=True,
                               stdout=subprocess.DEVNULL)
            demo["audio"] = wav
        if scenario.get("broker"):
            port = free_port()
            conf = os.path.join(run_dir, "mosquitto.conf")
            open(conf, "w").write(f"listener {port} 127.0.0.1\nallow_anonymous true\npersistence false\n")
            children.append(subprocess.Popen([shutil.which("mosquitto") or "/opt/homebrew/sbin/mosquitto", "-c", conf],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(0.5)
            demo["brokerPort"] = port
            children.append(subprocess.Popen(["python3", os.path.join(HERE, "peers.py"), str(port), "--lang", lang,
                                              "--chat-after", str(scenario.get("chatAfter", 10))]))
        demo.update(json.loads(json.dumps(scenario.get("demo", {})).replace("$DATA", data)))
        json.dump(demo, open(os.path.join(run_dir, "demo.json"), "w"), indent=1)
        env = dict(os.environ, MCL_DEMO_DIR=run_dir)
        smoke = subprocess.Popen(["python3", os.path.join(REPO, "scripts", "smoke-run.py"), "--app", app, "--data", data],
                                 cwd=REPO, env=env, stdout=subprocess.PIPE, text=True)
        line = smoke.stdout.readline()
        match = re.search(r"pid (\d+)", line)
        if not match:
            print(line, file=sys.stderr)
            return 1
        pid = match.group(1)
        start = time.time()
        try:
            for shot in sorted(scenario["shots"], key=lambda s: s["at"]):
                delay = shot["at"] - (time.time() - start)
                if delay > 0:
                    time.sleep(delay)
                rows = [r for r in windows(pid) if re.search(shot["title"], r["title"])]
                if not rows:
                    print(f"{name}: no window for {shot['name']} ({shot['title']})", file=sys.stderr)
                    continue
                target = os.path.join(outdir, shot["name"] + ".png")
                subprocess.run(["screencapture", "-x", "-o", "-l", rows[0]["id"], target], check=True)
                if "crop" in shot:
                    x, y, w, h = shot["crop"]
                    subprocess.run([tool("img"), "crop", target, target, str(x), str(y), str(w), str(h)], check=True)
                print(f"{name}: {shot['name']} ← {rows[0]['title']}")
        finally:
            smoke.send_signal(signal.SIGTERM)
            try:
                smoke.wait(timeout=20)
            except subprocess.TimeoutExpired:
                smoke.kill()
    finally:
        for child in children:
            child.kill()
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", required=True, choices=["cs", "en"])
    parser.add_argument("--only", default="")
    parser.add_argument("--out", default=None)
    parser.add_argument("--app", default=os.path.join(REPO, "build", "app", "MacContestLogger.app"))
    args = parser.parse_args()
    outdir = os.path.abspath(args.out or os.path.join(REPO, "build", "native-shots", args.lang))
    os.makedirs(outdir, exist_ok=True)
    only = [s for s in args.only.split(",") if s]
    status = 0
    for path in sorted(glob.glob(os.path.join(HERE, "scenarios", "*.json"))):
        if only and os.path.splitext(os.path.basename(path))[0] not in only:
            continue
        status |= run(path, args.lang, outdir, os.path.abspath(args.app))
    subprocess.run(["python3", os.path.join(HERE, "pngopt.py")] + glob.glob(os.path.join(outdir, "*.png")),
                   stdout=subprocess.DEVNULL)
    print(f"images in {outdir}")
    return status


if __name__ == "__main__":
    sys.exit(main())
