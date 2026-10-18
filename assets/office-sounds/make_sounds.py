"""Synthesises the office's foley into Sources/DioramaApp/Resources/OfficeSounds/<sound>-<n>.caf.

The office plays the kitchen's cues (`KitchenSound.cues`); a file here replaces the kitchen's sound
of the same name, and anything missing plays the kitchen's. Short, soft and cartoon-bright like the
kitchen's set, 44.1 kHz mono 16-bit CAF, stored without the in-app volume (`KitchenSound.volume`).

    python3 assets/office-sounds/make_sounds.py        (needs numpy and macOS afconvert)
"""
import os, subprocess, sys, tempfile, wave
import numpy as np

RATE = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Sources", "DioramaApp", "Resources", "OfficeSounds")


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def envelope(n, attack=0.002, decay=0.1):
    x = np.arange(n) / RATE
    return np.minimum(1, x / max(attack, 1e-4)) * np.exp(-x / decay)


def lowpass(signal, cutoff):
    """One-pole low-pass, enough to round off noise."""
    a = np.exp(-2 * np.pi * cutoff / RATE)
    out = np.zeros_like(signal)
    y = 0.0
    for i, s in enumerate(signal):
        y = (1 - a) * s + a * y
        out[i] = y
    return out


def place(buffer, sound, at):
    start = int(at * RATE)
    end = min(len(buffer), start + len(sound))
    buffer[start:end] += sound[: end - start]


def keyboard(rng):
    """A short burst of typing: soft plastic key clicks with a little thock."""
    out = np.zeros(int(0.42 * RATE))
    at = 0.005
    for _ in range(rng.integers(4, 7)):
        n = int(0.03 * RATE)
        click = rng.normal(0, 1, n) * envelope(n, 0.0005, 0.004)
        click = click - lowpass(click, 1800)  # bright click
        thock = np.sin(2 * np.pi * rng.uniform(170, 240) * t(0.03)) * envelope(n, 0.001, 0.008) * 0.6
        place(out, (click * 0.7 + thock) * rng.uniform(0.6, 1.0), at)
        at += rng.uniform(0.045, 0.085)
    return out


def blip(rng):
    """The terminal answering: two soft rising blips."""
    out = np.zeros(int(0.3 * RATE))
    base = rng.uniform(780, 980)
    for i, ratio in enumerate([1.0, rng.choice([1.25, 1.5, 1.335])]):
        tone = t(0.09)
        s = np.sin(2 * np.pi * base * ratio * tone) * envelope(len(tone), 0.004, 0.04)
        s += 0.25 * np.sin(4 * np.pi * base * ratio * tone) * envelope(len(tone), 0.004, 0.02)
        place(out, s, 0.01 + i * 0.1)
    return out


def squeak(rng):
    """A marker on the whiteboard: a quick felt-tip squeak."""
    d = rng.uniform(0.1, 0.16)
    tone = t(d)
    f0, f1 = rng.uniform(1700, 2100), rng.uniform(2300, 2900)
    freq = f0 + (f1 - f0) * (tone / d) ** 0.7
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    s = np.sin(phase) * 0.35 + rng.normal(0, 1, len(tone)) * 0.15
    s = lowpass(s, 5000)
    return s * envelope(len(tone), 0.01, d / 2.5)


def thump(rng):
    """A boxed deliverable set down on the demo table: a cardboard thump."""
    tone = t(0.35)
    n = len(tone)
    body = np.sin(2 * np.pi * rng.uniform(85, 110) * tone) * envelope(n, 0.002, 0.07)
    papery = lowpass(rng.normal(0, 1, n), 1400) * envelope(n, 0.001, 0.03) * 3
    return body + papery * 0.6


def bell(rng):
    """The manager's desk bell: a bright, slightly inharmonic ring."""
    tone = t(1.6)
    f = rng.uniform(2050, 2150)
    s = np.zeros_like(tone)
    for ratio, amp, decay in [(1.0, 1.0, 0.55), (2.76, 0.45, 0.25), (5.4, 0.25, 0.12), (0.5, 0.2, 0.4)]:
        s += amp * np.sin(2 * np.pi * f * ratio * tone + rng.uniform(0, 6)) * np.exp(-tone / decay)
    strike = rng.normal(0, 1, len(tone)) * envelope(len(tone), 0.0003, 0.003) * 0.4
    return (s + strike) * np.minimum(1, tone / 0.001)


def elevator(rng):
    """The elevator arriving: a two-tone chime."""
    out = np.zeros(int(1.4 * RATE))
    for i, freq in enumerate([1318.5, 1046.5]):
        tone = t(1.0)
        s = (np.sin(2 * np.pi * freq * tone) + 0.3 * np.sin(4 * np.pi * freq * tone) * np.exp(-tone / 0.15)) * envelope(len(tone), 0.003, 0.35)
        place(out, s, 0.02 + i * 0.32)
    return out


SOUNDS = {"chop": (keyboard, 3), "pot": (blip, 3), "tap": (squeak, 3), "plate": (thump, 3), "gong": (bell, 2), "ding": (elevator, 1)}


def write(name, samples):
    samples = samples / max(1e-6, np.max(np.abs(samples))) * 0.85
    # Trim the silent tail and fade the last few milliseconds.
    loud = np.nonzero(np.abs(samples) > 0.003)[0]
    samples = samples[: (loud[-1] + 1) if len(loud) else len(samples)]
    fade = min(len(samples), int(0.008 * RATE))
    samples[-fade:] *= np.linspace(1, 0, fade)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as handle:
        path = handle.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((samples * 32767).astype("<i2").tobytes())
    target = os.path.join(OUT, name + ".caf")
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", path, target], check=True)
    os.remove(path)
    return target


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(0x0FF1CE)
    for name, (make, variants) in SOUNDS.items():
        for n in range(variants):
            print("OFFICE SOUND", write(f"{name}-{n}", make(rng)))


if __name__ == "__main__":
    sys.exit(main())
