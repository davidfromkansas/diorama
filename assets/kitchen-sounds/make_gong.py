"""Synthesises the service gong (`gong-0…1`): a struck bronze gong, made here rather than taken
from a pack. Inharmonic partials with their own decays (the higher ones fade first and drift
slightly sharp, the shimmer of a real gong), a felt mallet's soft thump at the start, 4 s long.

    python3 make_gong.py <out_dir>      # writes gong-0.wav, gong-1.wav; convert with ffmpeg (README)
"""
import math, sys, wave, os
import numpy as np

RATE = 44100
PARTIALS = [(1.0, 1.0, 3.2), (1.52, 0.55, 2.4), (2.11, 0.45, 1.9), (2.74, 0.32, 1.5),
            (3.39, 0.25, 1.1), (4.21, 0.18, 0.8), (5.53, 0.12, 0.55), (7.02, 0.08, 0.4)]   # (ratio, level, decay s)

def gong(fundamental, seed, seconds=4.0):
    rng = np.random.default_rng(seed)
    t = np.arange(int(RATE * seconds)) / RATE
    out = np.zeros_like(t)
    for ratio, level, decay in PARTIALS:
        drift = 1 + 0.004 * ratio * (1 - np.exp(-t / 0.6))            # higher partials creep sharp
        phase = 2 * math.pi * np.cumsum(fundamental * ratio * drift) / RATE + rng.uniform(0, 2 * math.pi)
        beat = 1 + 0.12 * np.sin(2 * math.pi * rng.uniform(0.6, 1.8) * t)   # slow beating between modes
        out += level * beat * np.exp(-t / decay) * np.sin(phase)
    swell = 1 - 0.35 * np.exp(-t / 0.08)                              # the bloom just after the hit
    out *= swell
    # The felt mallet: a short low-passed thump.
    n = int(RATE * 0.05)
    thump = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (RATE * 0.012))
    thump = np.convolve(thump, np.ones(40) / 40, mode="same")
    out[:n] += 0.9 * thump
    out *= np.minimum(1, (t[-1] - t) / 0.4)                           # fade the tail out
    return out / np.max(np.abs(out)) * 0.89

if __name__ == "__main__":
    dest = sys.argv[1]
    for i, (f, seed) in enumerate(((98.0, 3), (112.0, 7))):
        data = (gong(f, seed) * 32767).astype("<i2")
        with wave.open(os.path.join(dest, f"gong-{i}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())
