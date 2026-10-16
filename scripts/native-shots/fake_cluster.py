#!/usr/bin/env python3
"""Fake DX cluster (telnet) on 127.0.0.1 for the screenshot demo. Synthetic spots only.

    fake_cluster.py --port-file F --mode SSB|CW|RTTY [--log DB.sqlite] [--seed N]

Binds an ephemeral loopback port and writes it to --port-file. On connect: a greeting, a burst of spots, then a new
spot every few seconds. With --log, about a quarter of the spotted calls are calls of that log (worked = dupes on the
band map).
"""
import argparse
import random
import socket
import sqlite3
import threading
import time
from datetime import datetime, timezone

PREFIXES = [
    ("DL", "0123456789", 40), ("OK", "12", 10), ("OM", "0123456789", 8), ("SP", "0123456789", 15),
    ("HA", "0123456789", 8), ("S5", "0123456789", 6), ("9A", "0123456789", 6), ("I", "0123456789", 15),
    ("F", "123456789", 12), ("G", "0123456789", 15), ("EA", "1234567", 12), ("EA", "8", 4), ("CT", "12", 4),
    ("PA", "0123456789", 8), ("ON", "4567", 6), ("OH", "0123456789", 8), ("SM", "0123456789", 8),
    ("LA", "0123456789", 5), ("UA", "1346", 12), ("UA", "9", 8), ("UR", "0123456789", 8), ("YO", "2345689", 6),
    ("LZ", "12345", 6), ("SV", "123456789", 5), ("4X", "1456", 3), ("K", "0123456789", 25),
    ("W", "0123456789", 25), ("N", "6", 5), ("VE", "1234567", 8), ("KH", "6", 3), ("KL", "7", 2),
    ("XE", "123", 3), ("PY", "1234567", 6), ("LU", "123456789", 4), ("CE", "1234", 3), ("JA", "0123456789", 10),
    ("BY", "14", 3), ("HL", "15", 3), ("VU", "23", 2), ("A", "6", 2), ("VK", "234567", 4), ("ZL", "1234", 2),
    ("ZS", "1256", 3), ("CN", "8", 2), ("5B", "4", 2), ("9K", "2", 1), ("TA", "12", 3), ("EA", "6", 2),
    ("CX", "2", 1), ("HK", "3", 1), ("YB", "1", 1), ("D4", "4", 1), ("EA", "9", 1), ("V5", "1", 1),
]
SPOTTERS_SUFFIX = ["-#", "-#", "-#", "", "", "-2", "-1"]
BANDS = {
    "CW": [(1810, 1840), (3500, 3560), (7000, 7040), (14000, 14060), (21000, 21060), (28000, 28070)],
    "SSB": [(1840, 1900), (3700, 3800), (7090, 7200), (14150, 14350), (21200, 21450), (28400, 28700)],
    "RTTY": [(1838, 1842), (3570, 3600), (7040, 7080), (14070, 14120), (21070, 21120), (28070, 28130)],
}
WEIGHTS = [6, 14, 26, 30, 16, 8]
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
COMMENTS = {
    "CW": ["CQ", "TEST", "", "", "CQ WW", "{wpm} WPM CQ", "{wpm} WPM CQ", "{db} dB {wpm} WPM CQ"],
    "SSB": ["", "", "CQ WW", "CQ CONTEST", "5/9+", "big signal", "CQ WW SSB"],
    "RTTY": ["RTTY", "RTTY CQ", "", "CQ WW RTTY", "RY TEST"],
}


def make_call(rnd):
    total = sum(p[2] for p in PREFIXES)
    target = rnd.randrange(total)
    for letters, digits, weight in PREFIXES:
        if target < weight:
            break
        target -= weight
    suffix = "".join(rnd.choice("QXZQXZJKVWY" + LETTERS) for _ in range(2 + rnd.randrange(2)))
    return letters + rnd.choice(digits) + suffix


def spotter(rnd):
    call = make_call(rnd)
    s = rnd.choice(SPOTTERS_SUFFIX)
    return call + s


class Spots:
    def __init__(self, mode, log, seed):
        self.mode = mode
        self.rnd = random.Random(seed)
        self.worked = []
        if log:
            con = sqlite3.connect(log)
            try:
                rows = con.execute("SELECT call, freq_hz FROM qso ORDER BY RANDOM() LIMIT 400").fetchall()
            except sqlite3.Error:
                rows = []
            self.worked = [(c, f) for c, f in rows if c and f]

    def line(self):
        rnd = self.rnd
        mode = self.mode
        if self.worked and rnd.random() < 0.25:
            call, freq = rnd.choice(self.worked)
            khz = freq / 1000.0
        else:
            call = make_call(rnd)
            low, high = rnd.choices(BANDS[mode], weights=WEIGHTS)[0]
            khz = low + rnd.random() * (high - low)
        if mode == "SSB":
            khz = round(khz)
        else:
            khz = round(khz * 10) / 10
        comment = rnd.choice(COMMENTS[mode]).format(wpm=rnd.choice([26, 28, 30, 32, 35]), db=rnd.randrange(8, 36))
        hhmm = datetime.now(timezone.utc).strftime("%H%MZ")
        de = (spotter(rnd) + ":").ljust(10)
        return f"DX de {de}{khz:>8.1f}  {call:<13}{comment:<30} {hhmm}"


def serve(conn, spots, burst):
    try:
        conn.sendall(b"Hello, this is the DEMO-9 DX cluster (DXSpider demo).\r\nPlease enter your call: ")
        buffer = b""
        call = ""
        conn.settimeout(0.5)
        start = time.time()
        while time.time() - start < 3 and b"\n" not in buffer:
            try:
                data = conn.recv(256)
                if not data:
                    return
                buffer += data
            except socket.timeout:
                pass
        if b"\n" in buffer:
            call = buffer.split(b"\n")[0].strip().decode("ascii", "replace")
        if call:
            conn.sendall(f"Hello {call}, this is DEMO-9 in a demo network\r\n{call} de DEMO-9 >\r\n".encode())
        for _ in range(burst):
            conn.sendall((spots.line() + "\r\n").encode())
            time.sleep(0.02)
        conn.sendall(b"WWV de DEMO-9 <18>:   SFI=142, A=8, K=2, No Storms -> No Storms\r\n")
        while True:
            time.sleep(spots.rnd.uniform(1.0, 3.5))
            conn.sendall((spots.line() + "\r\n").encode())
            try:
                data = conn.recv(256)
                if data == b"":
                    return
            except socket.timeout:
                pass
    except OSError:
        return
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--mode", default="SSB")
    parser.add_argument("--log")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--burst", type=int, default=90)
    args = parser.parse_args()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(4)
    with open(args.port_file, "w") as handle:
        handle.write(str(server.getsockname()[1]))
    n = 0
    while True:
        conn, _ = server.accept()
        n += 1
        spots = Spots(args.mode.upper(), args.log, args.seed + n)
        threading.Thread(target=serve, args=(conn, spots, args.burst), daemon=True).start()


if __name__ == "__main__":
    main()
