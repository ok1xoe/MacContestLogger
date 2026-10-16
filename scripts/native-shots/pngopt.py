#!/usr/bin/env python3
"""Lossless PNG recompression: the same pixel data (IDAT inflated and deflated again at level 9, filters unchanged)."""
import struct, sys, zlib
def chunks(data):
    pos = 8
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos+4])[0]
        yield data[pos+4:pos+8], data[pos+8:pos+8+n]
        pos += 12 + n
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
for path in sys.argv[1:]:
    data = open(path, "rb").read()
    parts = list(chunks(data))
    raw = zlib.decompress(b"".join(d for t, d in parts if t == b"IDAT"))
    best = zlib.compress(raw, 9)
    out = bytearray(data[:8]); done = False
    for t, d in parts:
        if t == b"IDAT":
            if not done: out += chunk(b"IDAT", best); done = True
        else:
            out += chunk(t, d)
    if len(out) < len(data):
        assert zlib.decompress(b"".join(d for t, d in chunks(bytes(out)) if t == b"IDAT")) == raw
        open(path, "wb").write(out)
    print(f"{path.split('/')[-1]}: {len(data)} -> {min(len(out), len(data))}")
