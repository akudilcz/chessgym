#!/usr/bin/env python3
"""Generates the app's sound effects as 16-bit mono WAVs.

The effects are synthesised rather than sampled so they carry no licence
and can be regenerated deterministically:

    python3 tool/gen_sfx.py

Writes into assets/sfx/. Keep the output committed — the app ships these,
and the build has no Python in it.
"""

import math
import os
import struct
import wave

RATE = 22050  # plenty for short blips, and half the bytes of 44.1k
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def _write(name, samples):
    """Normalise to just under full scale and write a mono 16-bit WAV."""
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = 0.89 / peak
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * scale * 32767))))
        for s in samples
    )
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"{name}: {len(samples) / RATE * 1000:.0f}ms, {len(frames) + 44} bytes")


def _env(i, n, attack=0.005, decay=4.0):
    """Fast attack, exponential decay. Attack is in seconds, decay a rate."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-decay * t)


def tone(freq, dur, decay=4.0, harmonics=(1.0,), attack=0.005, detune=0.0):
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        v = 0.0
        for h, amp in enumerate(harmonics, start=1):
            v += amp * math.sin(2 * math.pi * freq * h * (1 + detune) * t)
        out.append(v * _env(i, n, attack, decay))
    return out


def noise(dur, decay=40.0, lowpass=0.35):
    """Deterministic pseudo-noise (a fixed LCG) through a one-pole lowpass."""
    n = int(dur * RATE)
    state = 12345
    prev = 0.0
    out = []
    for i in range(n):
        state = (1103515245 * state + 12345) % (1 << 31)
        white = (state / (1 << 30)) - 1.0
        prev = prev + lowpass * (white - prev)
        out.append(prev * _env(i, n, 0.0005, decay))
    return out


def mix(*layers):
    n = max(len(x) for x in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def seq(*parts):
    """Lay tones out in time: (start_seconds, samples) pairs."""
    total = max(int(s * RATE) + len(x) for s, x in parts)
    out = [0.0] * total
    for start, layer in parts:
        off = int(start * RATE)
        for i, v in enumerate(layer):
            out[off + i] += v
    return out


def main():
    os.makedirs(OUT, exist_ok=True)

    # A piece landing on a board: a woody knock, no pitch to speak of.
    _write("move.wav", mix(
        tone(210, 0.07, decay=55, harmonics=(1.0, 0.3)),
        [v * 0.5 for v in noise(0.035, decay=90, lowpass=0.5)],
    ))

    # Capture: same knock, lower and with more crack to it.
    _write("capture.wav", mix(
        tone(140, 0.12, decay=34, harmonics=(1.0, 0.45, 0.2)),
        [v * 0.8 for v in noise(0.06, decay=55, lowpass=0.7)],
    ))

    # Check: a two-note alert, urgent but not shrill.
    _write("check.wav", seq(
        (0.0, tone(1180, 0.09, decay=26, harmonics=(1.0, 0.25))),
        (0.075, tone(1570, 0.13, decay=20, harmonics=(1.0, 0.3))),
    ))

    # Solved: a rising major arpeggio, bell-toned.
    _write("solve.wav", seq(
        (0.00, tone(523.25, 0.30, decay=9, harmonics=(1.0, 0.22, 0.08))),
        (0.07, tone(659.25, 0.30, decay=9, harmonics=(1.0, 0.22, 0.08))),
        (0.14, tone(783.99, 0.32, decay=8, harmonics=(1.0, 0.24, 0.09))),
        (0.21, tone(1046.50, 0.45, decay=6, harmonics=(1.0, 0.3, 0.12))),
    ))

    # Missed: two notes falling, slightly detuned so it reads as "wrong".
    _write("fail.wav", seq(
        (0.00, tone(233.08, 0.20, decay=13, harmonics=(1.0, 0.5, 0.25))),
        (0.11, tone(174.61, 0.30, decay=10, harmonics=(1.0, 0.55, 0.3),
                    detune=-0.006)),
    ))

    # Level / tier up: a wider fanfare, the only sound allowed to feel big.
    _write("levelup.wav", seq(
        (0.00, tone(523.25, 0.22, decay=11, harmonics=(1.0, 0.3, 0.12))),
        (0.09, tone(783.99, 0.22, decay=11, harmonics=(1.0, 0.3, 0.12))),
        (0.18, tone(1046.50, 0.26, decay=9, harmonics=(1.0, 0.32, 0.14))),
        (0.27, tone(1318.51, 0.55, decay=5, harmonics=(1.0, 0.35, 0.18, 0.08))),
    ))


if __name__ == "__main__":
    main()
