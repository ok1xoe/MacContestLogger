#!/usr/bin/env python3
"""Synthetic two-receiver RTTY audio (stereo, 16-bit, 12 kHz): left = RX1, right = RX2.

Each channel carries several AFSK RTTY signals (45.45 Bd, 170 Hz shift, ITA2) at different audio tones plus
white noise. Pure Python (no numpy).

    rtty_wav.py out.wav [--seconds 120]
"""
import math
import random
import struct
import sys
import wave

RATE = 12000
BAUD = 45.45
SHIFT = 170.0

LTRS = {
    "E": 0x01, "\n": 0x02, "A": 0x03, " ": 0x04, "S": 0x05, "I": 0x06, "U": 0x07, "\r": 0x08, "D": 0x09,
    "R": 0x0A, "J": 0x0B, "N": 0x0C, "F": 0x0D, "C": 0x0E, "K": 0x0F, "T": 0x10, "Z": 0x11, "L": 0x12,
    "W": 0x13, "H": 0x14, "Y": 0x15, "P": 0x16, "Q": 0x17, "O": 0x18, "B": 0x19, "G": 0x1A, "M": 0x1C,
    "X": 0x1D, "V": 0x1E,
}
FIGS = {
    "3": 0x01, "-": 0x03, "8": 0x06, "7": 0x07, "4": 0x0A, ",": 0x0C, ":": 0x0E, "(": 0x0F, "5": 0x10,
    ")": 0x12, "2": 0x13, "6": 0x15, "0": 0x16, "1": 0x17, "9": 0x18, "?": 0x19, ".": 0x1C, "/": 0x1D,
}


def encode(text):
    out = [0x1F]
    figs = False
    for ch in text.upper():
        if ch in " \r\n":
            out.append(LTRS[ch])
        elif ch in LTRS:
            if figs:
                out.append(0x1F)
                figs = False
            out.append(LTRS[ch])
        elif ch in FIGS:
            if not figs:
                out.append(0x1B)
                figs = True
            out.append(FIGS[ch])
    return out


def bits(codes):
    """(level, duration in bit units): 1 = mark."""
    seq = []
    for code in codes:
        seq.append((0, 1.0))
        for i in range(5):
            seq.append(((code >> i) & 1, 1.0))
        seq.append((1, 1.5))
    return seq


def signal(total, schedule, mark, amp, seed):
    """schedule: list of (start_seconds, text). The carrier stays on (idle mark) for the whole file, so the decoder
    prints nothing between the transmissions (as a station holding its carrier in a pileup)."""
    rnd = random.Random(seed)
    out = [0.0] * total
    phase = rnd.random() * 2 * math.pi
    pos = 0
    unit = RATE / BAUD
    events = sorted(schedule)
    t = 0.0
    def emit(level, units):
        nonlocal pos, phase, t
        n = int(round(t + units * unit)) - int(round(t))
        t += units * unit
        step = 2 * math.pi * (mark if level else mark + SHIFT) / RATE
        for _ in range(n):
            if pos < total:
                out[pos] += amp * math.sin(phase)
            phase += step
            pos += 1
    for start, text in events:
        idle_units = max(0.0, (start * RATE - pos) / unit)
        emit(1, idle_units)
        for level, units in bits(encode("\r\n" + text)):
            emit(level, units)
    while pos < total:
        emit(1, 1.0)
    return out


def channel(total, plan, noise, seed):
    rnd = random.Random(seed)
    mix = [rnd.gauss(0.0, noise) for _ in range(total)]
    for index, (mark, amp, schedule) in enumerate(plan):
        sig = signal(total, schedule, mark, amp, seed * 31 + index)
        for i in range(total):
            mix[i] += sig[i]
    return mix


def main():
    out = sys.argv[1]
    seconds = 120
    if "--seconds" in sys.argv:
        seconds = int(sys.argv[sys.argv.index("--seconds") + 1])
    total = seconds * RATE
    # RX1 (left): the run frequency (2125 Hz) — callers answering the CQ, plus two other stations nearby.
    left = channel(total, [
        (2125.0, 0.30, [
            (1, "OK1DEMO DE K3ZQX K3ZQX"),
            (14, "OK1DEMO TU 599 05 PA 05 PA K3ZQX"),
            (30, "OK1DEMO DE JA1YQZ JA1YQZ"),
            (43, "TU 599 25 25 JA1YQZ"),
            (58, "OK1DEMO DE DL7QXV DL7QXV"),
            (71, "R 599 14 14 DL7QXV"),
            (86, "OK1DEMO DE PY2QZX PY2QZX"),
            (100, "599 11 11 PY2QZX"),
        ]),
        (1450.0, 0.14, [
            (4, "CQ TEST UA9XZQ UA9XZQ CQ"),
            (36, "CQ TEST UA9XZQ UA9XZQ CQ"),
            (70, "CQ TEST UA9XZQ UA9XZQ CQ"),
        ]),
        (900.0, 0.11, [
            (20, "TU 599 14 14 F5QZX"),
            (60, "QRZ? F5QZX TEST"),
            (95, "TU 599 14 14 F5QZX"),
        ]),
    ], 0.07, 1)
    # RX2 (right): searching and pouncing on another band.
    right = channel(total, [
        (2125.0, 0.28, [
            (6, "CQ TEST VK2ZQX VK2ZQX CQ"),
            (24, "OK1DEMO 599 30 30 VK2ZQX"),
            (52, "TU VK2ZQX TEST"),
            (76, "CQ TEST VK2ZQX VK2ZQX CQ"),
            (104, "QRZ VK2ZQX"),
        ]),
        (1700.0, 0.12, [
            (10, "CQ CQ TEST ZS6QXV ZS6QXV"),
            (48, "TU 599 38 38 ZS6QXV"),
            (88, "CQ CQ TEST ZS6QXV ZS6QXV"),
        ]),
        (1100.0, 0.10, [
            (16, "CQ TEST LU5ZQX LU5ZQX K"),
            (64, "CQ TEST LU5ZQX LU5ZQX K"),
        ]),
    ], 0.07, 2)
    with wave.open(out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for a, b in zip(left, right):
            frames += struct.pack("<hh", max(-32767, min(32767, int(a * 32767))),
                                  max(-32767, min(32767, int(b * 32767))))
        w.writeframes(bytes(frames))
    print(f"wrote {out}: {seconds} s stereo {RATE} Hz")


if __name__ == "__main__":
    main()
