#!/usr/bin/env python3
"""전투·UI 효과음(#628)을 numpy로 합성해 OGG로 쓴다. 외부 샘플을 쓰지 않는다.

실행: python3 scenes/combat/audio/sources/make_sfx.py  (저장소 루트에서, numpy와 ffmpeg 필요. ffmpeg 내장 vorbis 인코더를 쓴다(스테레오만 지원해 두 채널에 같은 소리를 쓴다))
난수 씨앗을 고정해 다시 실행하면 같은 소리를 만든다. cue별 변수는 sfx_generation.json에 적는다.
hit_wood.ogg는 Kenney의 원본(THIRD_PARTY_NOTICES.md)이라 여기서 만들지 않는다.
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[4]
COMBAT = ROOT / "scenes/combat/audio"
UI = ROOT / "scenes/ui/audio"


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds, seed):
    return np.random.default_rng(seed).uniform(-1, 1, int(RATE * seconds))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(n, attack, decay):
    e = np.ones(n)
    a = max(1, int(attack * RATE))
    e[:a] = np.linspace(0, 1, a)
    d = np.exp(-np.arange(n) / (decay * RATE))
    return e * d


def square(freq, seconds, duty=0.5):
    return np.where((t(seconds) * freq) % 1.0 < duty, 1.0, -1.0)


def sine(freq, seconds):
    return np.sin(2 * np.pi * freq * t(seconds))


def sweep(f0, f1, seconds, shape=square):
    ph = np.cumsum(np.linspace(f0, f1, int(RATE * seconds))) / RATE
    return np.sin(2 * np.pi * ph) if shape is sine else np.where(ph % 1.0 < 0.5, 1.0, -1.0)


def chirp_notes(notes, wave_shape=square):
    return np.concatenate([wave_shape(f, d) * env(int(RATE * d), 0.002, d * 0.8) for f, d in notes])


def norm(x, peak=0.8):
    return x / max(1e-9, np.abs(x).max()) * peak


def fade(x, ms=8):
    n = int(RATE * ms / 1000)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def write(path, x, loop=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-ac", "2", "-c:a", "vorbis", "-strict", "-2",
                        "-b:a", "96k", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        str(path)], check=True)


def pad(x, size):
    out = np.zeros(size)
    out[:len(x)] += x[:size]
    return out


def hit_flesh():
    n = 0.16
    body = lowpass(noise(n, 1), 900) * env(int(RATE * n), 0.001, 0.035)
    thump = sweep(140, 55, n, sine) * env(int(RATE * n), 0.001, 0.05)
    return norm(fade(body * 1.2 + thump))


def hit_metal():
    n = 0.4
    x = np.zeros(int(RATE * n))
    for f, g in [(820, 1.0), (1337, 0.7), (2110, 0.5), (3050, 0.3)]:
        x += g * sine(f, n) * env(len(x), 0.0005, 0.07)
    x += highpass(noise(n, 2), 2500) * env(len(x), 0.0005, 0.02) * 0.8
    return norm(fade(x))


def hit_stone():
    n = 0.3
    x = lowpass(noise(n, 3), 1800) * env(int(RATE * n), 0.0005, 0.03)
    x += sweep(220, 90, n, sine) * env(len(x), 0.0005, 0.06) * 0.8
    x += highpass(noise(n, 4), 3000) * env(len(x), 0.0005, 0.008) * 0.6
    return norm(fade(x))


def critical():
    a = hit_flesh()
    b = hit_metal()
    x = pad(a, int(RATE * 0.5)) + 0.8 * np.roll(pad(b, int(RATE * 0.5)), int(RATE * 0.03))
    x += sweep(60, 30, 0.5, sine) * env(len(x), 0.001, 0.12) * 0.6
    return norm(fade(x))


def miss():
    n = 0.28
    x = noise(n, 5)
    x = lowpass(x, 3500) - lowpass(x, 600)
    x *= np.sin(np.pi * np.linspace(0, 1, len(x))) ** 2
    return norm(fade(x), 0.6)


def downed():
    n = 0.9
    x = sweep(180, 40, n, sine) * env(int(RATE * n), 0.002, 0.25)
    x += lowpass(noise(n, 6), 600) * env(len(x), 0.002, 0.12) * 0.7
    return norm(fade(x, 20))


def shield():
    n = 0.7
    x = np.zeros(int(RATE * n))
    for f in (523, 784, 1046):
        x += sine(f, n) * env(len(x), 0.01, 0.25)
    x += sweep(400, 1600, n, sine) * env(len(x), 0.01, 0.15) * 0.4
    return norm(fade(x, 15))


def heal():
    return norm(fade(chirp_notes([(660, 0.07), (880, 0.07), (1320, 0.16)], sine)), 0.7)


def shout():
    n = 0.9
    x = np.zeros(int(RATE * n))
    for f in (196, 294, 392):
        x += square(f, n, 0.3) * env(len(x), 0.04, 0.5)
    x = lowpass(x, 1800)
    for k in range(3):
        beat = sweep(120, 60, 0.12, sine) * env(int(RATE * 0.12), 0.001, 0.04)
        s = int(RATE * 0.0) + k * int(RATE * 0.28)
        x[s:s + len(beat)] += beat * 1.3
    return norm(fade(x, 20))


def step(seed, cutoff, length=0.12, decay=0.025):
    return norm(fade(lowpass(noise(length, seed), cutoff) * env(int(RATE * length), 0.001, decay)), 0.7)


def step_dirt():
    return step(10, 700)


def step_stone():
    x = step(11, 2200, 0.1, 0.015)
    return norm(fade(x + 0.5 * highpass(noise(0.1, 12), 3000) * env(len(x), 0.0005, 0.006)), 0.7)


def step_water():
    n = 0.22
    x = np.zeros(int(RATE * n))
    for i, f in enumerate((700, 1100, 520)):
        s = int(RATE * 0.03 * i)
        b = sweep(f, f * 1.8, 0.09, sine) * env(int(RATE * 0.09), 0.002, 0.03)
        x[s:s + len(b)] += b
    x += lowpass(noise(n, 13), 1500) * env(len(x), 0.002, 0.05) * 0.5
    return norm(fade(x), 0.7)


def jump():
    return norm(fade(sweep(220, 520, 0.14, sine) * env(int(RATE * 0.14), 0.005, 0.08)
                     + lowpass(noise(0.14, 14), 1200) * 0.2 * env(int(RATE * 0.14), 0.005, 0.08)), 0.6)


def land():
    n = 0.18
    x = sweep(130, 60, n, sine) * env(int(RATE * n), 0.001, 0.05)
    x += lowpass(noise(n, 15), 700) * env(int(RATE * n), 0.001, 0.03)
    return norm(fade(x), 0.75)


def turn_ally():
    return norm(fade(chirp_notes([(523, 0.09), (784, 0.16)])), 0.5)


def turn_enemy():
    return norm(fade(chirp_notes([(262, 0.1), (196, 0.2)])), 0.5)


def ambient(seed, cutoff, lfo, seconds=8.0):
    """처음과 끝을 이어 붙여 반복해도 끊기지 않게 한다(순환 잡음 + 정수 주기 LFO)."""
    n = int(RATE * seconds)
    spectrum = np.fft.rfft(np.random.default_rng(seed).uniform(-1, 1, n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum *= 1.0 / (1.0 + (freqs / cutoff) ** 2)
    x = np.fft.irfft(spectrum, n)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * lfo * seconds * np.arange(n) / n / seconds * 1.0)
    return norm(x, 0.5)


def ambient_water():
    n = int(RATE * 8.0)
    x = ambient(21, 1200, 0.25)
    bubbles = np.random.default_rng(22).uniform(-1, 1, n)
    spectrum = np.fft.rfft(bubbles)
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum *= np.exp(-((freqs - 900) / 500) ** 2)
    band = np.fft.irfft(spectrum, n)
    mod = 0.5 + 0.5 * np.sin(2 * np.pi * 3.0 * np.arange(n) / n * 8.0 / 8.0 * 3)
    return norm(x + 0.5 * norm(band, 0.5) * mod, 0.5)


def ui_hover():
    return norm(fade(chirp_notes([(1320, 0.03)])), 0.3)


def ui_click():
    return norm(fade(chirp_notes([(880, 0.035), (1175, 0.05)])), 0.4)


def ui_cancel():
    return norm(fade(chirp_notes([(660, 0.04), (440, 0.07)])), 0.4)


def ui_disabled():
    x = square(110, 0.1, 0.25) * env(int(RATE * 0.1), 0.002, 0.08)
    return norm(fade(lowpass(x, 900)), 0.4)


COMBAT_CUES = {
    "hit_flesh": hit_flesh, "hit_metal": hit_metal, "hit_stone": hit_stone, "critical": critical,
    "miss": miss, "downed": downed, "shield": shield, "heal": heal, "shout": shout,
    "step_dirt": step_dirt, "step_stone": step_stone, "step_water": step_water,
    "jump": jump, "land": land, "turn_ally": turn_ally, "turn_enemy": turn_enemy,
}
LOOP_CUES = {"ambient_water": ambient_water, "ambient_wind": lambda: ambient(23, 500, 0.125)}
UI_CUES = {"ui_hover": ui_hover, "ui_click": ui_click, "ui_cancel": ui_cancel, "ui_disabled": ui_disabled}

if __name__ == "__main__":
    for name, fn in COMBAT_CUES.items():
        write(COMBAT / f"{name}.ogg", fn())
    for name, fn in LOOP_CUES.items():
        write(COMBAT / f"{name}.ogg", fn(), loop=True)
    for name, fn in UI_CUES.items():
        write(UI / f"{name}.ogg", fn())
