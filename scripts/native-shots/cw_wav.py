#!/usr/bin/env python3
"""Synthetic CW receiver audio (stereo 16-bit 12 kHz, both channels alike): several stations keyed at different
pitches and speeds over noise.   cw_wav.py out.wav [--seconds 90]"""
import math, random, struct, sys, wave
RATE = 12000
MORSE = {"A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....", "I": "..",
         "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
         "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
         "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....",
         "7": "--...", "8": "---..", "9": "----.", "/": "-..-.", "?": "..--.."}
def keying(text, wpm):
    unit = 1.2 / wpm
    out = []
    for word in text.split():
        for ch in word:
            for sym in MORSE.get(ch, ""):
                out.append((1, unit * (3 if sym == "-" else 1)))
                out.append((0, unit))
            out.append((0, unit * 2))
        out.append((0, unit * 4))
    return out
def main():
    path = sys.argv[1]
    seconds = int(sys.argv[sys.argv.index("--seconds") + 1]) if "--seconds" in sys.argv else 90
    total = seconds * RATE
    rnd = random.Random(3)
    mix = [rnd.gauss(0, 0.05) for _ in range(total)]
    stations = [(600, 30, 0.30, "CQ TEST SV5ZQX SV5ZQX TEST"), (820, 28, 0.18, "TU UA3ZQR TEST"),
                (1150, 34, 0.22, "CQ ON4ZXK ON4ZXK TEST"), (1480, 26, 0.12, "TEST DL7QXV DL7QXV"),
                (1900, 32, 0.20, "5NN 14 TU UA9ZQX"), (2350, 24, 0.10, "CQ TEST JA1QZX JA1QZX")]
    for pitch, wpm, amp, text in stations:
        t = rnd.uniform(0, 3)
        step = 2 * math.pi * pitch / RATE
        while t < seconds:
            for on, dur in keying(text, wpm):
                n0, n1 = int(t * RATE), int((t + dur) * RATE)
                if on:
                    for i in range(n0, min(n1, total)):
                        edge = min(1.0, (i - n0) / 48.0, (n1 - i) / 48.0)
                        mix[i] += amp * edge * math.sin(step * i)
                t += dur
            t += rnd.uniform(1.5, 4.0)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE)
        frames = bytearray()
        for v in mix:
            s = max(-32767, min(32767, int(v * 32767)))
            frames += struct.pack("<hh", s, s)
        w.writeframes(bytes(frames))
main()
