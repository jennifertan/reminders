#!/usr/bin/env python3
"""Makes Ringlet's alarm sounds as 16-bit mono WAV files in Ringlet/Sounds.

Each sound is a short pattern of soft-edged tones repeated for 5 seconds, so a reminder rings
briefly. A wake-up alarm's alarm screen loops the sound for longer.
Run from the repo root:  python3 scripts/make-sounds.py
"""
import math
import struct
import wave
from pathlib import Path

RATE = 32000
LENGTH = 5.0
OUT = Path(__file__).resolve().parent.parent / "Ringlet" / "Sounds"

# name: (wave shape, repeat every N seconds, [(frequency Hz, start s, duration s), ...])
SOUNDS = {
    "chime": ("sine", 2.4, [(1046.5, 0.0, 0.9), (1318.5, 0.16, 0.9), (1568.0, 0.32, 1.3)]),
    "bells": ("bell", 2.2, [(1568.0, 0.0, 0.5), (2093.0, 0.12, 0.5), (1568.0, 0.24, 0.5), (2093.0, 0.36, 0.8)]),
    "pulse": ("soft-square", 1.6, [(880.0, 0.0, 0.14), (880.0, 0.22, 0.14), (880.0, 0.44, 0.14), (880.0, 0.66, 0.14)]),
    "rise": ("sine", 3.0, [(523.3, 0.0, 0.6), (659.3, 0.3, 0.6), (784.0, 0.6, 0.6), (1046.5, 0.9, 1.2)]),
    "marimba": ("marimba", 2.0, [(659.3, 0.0, 0.35), (784.0, 0.15, 0.35), (987.8, 0.3, 0.35), (784.0, 0.45, 0.6)]),
}


def tone(shape, freq, t):
    x = 2 * math.pi * freq * t
    if shape == "sine":
        return math.sin(x)
    if shape == "bell":
        return 0.7 * math.sin(x) + 0.2 * math.sin(2.76 * x) + 0.1 * math.sin(5.4 * x)
    if shape == "marimba":
        return 0.8 * math.sin(x) + 0.2 * math.sin(4 * x)
    if shape == "soft-square":
        return math.tanh(3 * math.sin(x)) * 0.8
    raise ValueError(shape)


def render(shape, period, notes):
    total = int(RATE * LENGTH)
    samples = [0.0] * total
    start = 0.0
    while start < LENGTH - period * 0.5:
        for freq, offset, duration in notes:
            begin = int((start + offset) * RATE)
            count = int(duration * RATE)
            for i in range(count):
                n = begin + i
                if n >= total:
                    break
                t = i / RATE
                attack = min(1.0, t / 0.012)
                decay = math.exp(-4.5 * t / duration)
                samples[n] += tone(shape, freq, t) * attack * decay * 0.32
        start += period
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.85 / peak
    return [int(max(-1, min(1, s * scale)) * 32767) for s in samples]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (shape, period, notes) in SOUNDS.items():
        data = render(shape, period, notes)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(struct.pack(f"<{len(data)}h", *data))
        print(f"wrote {name}.wav")


if __name__ == "__main__":
    main()
