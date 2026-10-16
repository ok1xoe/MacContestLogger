#!/usr/bin/env python3
"""Fictitious multi-op peer stations on the throwaway broker: retained status heartbeats and a few chat lines.
    peers.py PORT [--chat-after S] [--lang cs|en]"""
import json, subprocess, sys, time, uuid
from datetime import datetime, timezone
port = sys.argv[1]
lang = sys.argv[sys.argv.index("--lang") + 1] if "--lang" in sys.argv else "en"
chat_after = float(sys.argv[sys.argv.index("--chat-after") + 1]) if "--chat-after" in sys.argv else 12
PUB = "/opt/homebrew/bin/mosquitto_pub"
def now(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
def pub(topic, obj, retain=False):
    subprocess.run([PUB, "-h", "127.0.0.1", "-p", port, "-q", "1", "-t", topic, "-m", json.dumps(obj)]
                   + (["-r"] if retain else []), check=False)
PEERS = [("RUN2", "OK2DEMO", "RUN2", "40m", 7008200, "Run", 512, False, "UA9ZQX"),
         ("MULT", "OK3DEMO", "MULT", "15m", 21031500, "S&P", 187, False, "ZS6QXV"),
         ("RUN3", "OK4DEMO", "RUN", "80m", 3512700, "Run", 268, True, "")]
CHAT = {"cs": [("RUN2", "OK2DEMO", "40 m je otevřená do JA, máte někdo volno?"),
               ("MULT", "OK3DEMO", "ZS6QXV na 21031.5 volá CQ, nový násobič na 15 m"),
               ("RUN3", "OK4DEMO", "Za 10 minut střídám operátora, pak jedeme dál"),
               ("RUN2", "OK2DEMO", "Rate 120/h, držím 7008.2"),
               ("MULT", "OK3DEMO", "Předávám VK2ZQX na 20 m, volá na 14012"),
               ("RUN3", "OK4DEMO", "Díky, 80 m se pomalu zavírá")],
        "en": [("RUN2", "OK2DEMO", "40 m is open to JA, anyone free?"),
               ("MULT", "OK3DEMO", "ZS6QXV calling CQ on 21031.5, a new mult on 15 m"),
               ("RUN3", "OK4DEMO", "Changing operators in 10 minutes, then we carry on"),
               ("RUN2", "OK2DEMO", "Rate 120/h, holding 7008.2"),
               ("MULT", "OK3DEMO", "Passing VK2ZQX to 20 m, he calls on 14012"),
               ("RUN3", "OK4DEMO", "Thanks, 80 m is slowly closing")]}
import random
from datetime import timedelta
rnd = random.Random(21)
PFX = ["DL", "SP", "UA", "I", "F", "G", "EA", "JA", "K", "W", "PY", "VE", "OH", "SM", "HA", "YO", "LZ", "UR", "ON", "PA"]
def qso_states():
    t0 = datetime.now(timezone.utc)
    for sid, op, st, band, f, run, n, tx, call in PEERS:
        for i in range(45):
            ts = t0 - timedelta(minutes=i * rnd.uniform(0.6, 1.6) + 1)
            c = rnd.choice(PFX) + str(rnd.randrange(10)) + "".join(rnd.choice("QXZVWYJK") for _ in range(3))
            u = str(uuid.UUID(int=rnd.getrandbits(128)))
            iso = ts.strftime("%Y-%m-%dT%H:%M:%SZ")
            pub("qso/state/" + u, {"uuid": u, "stationId": sid, "version": 1, "updatedAtUtc": iso, "deleted": False,
                "qso": {"timestampUtc": iso, "call": c, "freqHz": f, "band": band, "mode": "CW", "rstSent": "599",
                        "rstRcvd": "599", "exchangeSent": "599 15", "exchangeRcvd": "599 14", "serialSent": n - i,
                        "serialRcvd": None, "operator": op, "comment": "", "dxccEntity": None, "dxccName": None,
                        "continent": None, "xqso": False, "radioNr": 1}}, retain=True)
qso_states()
start = time.time(); sent = False
while True:
    for sid, op, st, band, f, run, n, tx, call in PEERS:
        pub("station/status/" + sid, {"stationId": sid, "operator": op, "stationType": st, "band": band,
            "mode": "CW", "freqHz": f, "runMode": run, "qsoCount": n + int((time.time() - start) / 40),
            "transmitting": tx, "online": True, "timestampUtc": now(), "entryCall": call}, retain=True)
    if not sent and time.time() - start > chat_after:
        for sid, op, text in CHAT[lang]:
            pub("station/msg", {"type": "CHAT", "id": str(uuid.uuid4()), "fromStation": sid, "fromOperator": op,
                "toStation": "", "text": text, "call": "", "freqHz": 0, "mode": "", "timestampUtc": now()})
            time.sleep(0.5)
        sent = True
    time.sleep(5)
