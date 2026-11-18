#!/usr/bin/env python3
"""전투·UI 효과음(#628)을 OGG로 쓴다.

타격·전투 불능·발소리(흙·돌)·점프·착지는 Kenney CC0 원본(kenney/ 폴더)을 잘라 다듬어 만든다.
빗나감·물 발소리·방어막·회복·함성·턴 신호·환경음·UI는 numpy로 합성한다(외부 샘플 없음).
주사위 소리(#627: dice_roll·roll_success·roll_fail)도 칩튠풍으로 합성한다.

실행: python3 scenes/combat/audio/sources/make_sfx.py  (저장소 루트에서, numpy와 ffmpeg 필요. ffmpeg 내장 vorbis 인코더를 쓴다(스테레오만 지원해 두 채널에 같은 소리를 쓴다))
난수 씨앗을 고정해 다시 실행하면 같은 소리를 만든다. cue별 변수는 sfx_generation.json에 적는다.
hit_wood.ogg는 Kenney의 원본(THIRD_PARTY_NOTICES.md)이라 여기서 만들지 않는다.
원본과 출처는 THIRD_PARTY_NOTICES.md와 sfx_generation.json의 external에 있다.
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
KENNEY = Path(__file__).resolve().parent / "kenney"


def kenney(name, seconds, peak=0.8, gain=1.0):
    """Kenney 원본을 모노 44.1kHz로 읽어 seconds까지 자르고 끝을 줄여 정규화한다."""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(KENNEY / f"{name}.ogg"), "-ac", "1", "-ar", str(RATE),
                          "-f", "s16le", "-"], check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.int16).astype(float) / 32768.0
    x = x[:int(RATE * seconds)] * gain
    tail = min(len(x) // 3, int(RATE * 0.04))
    x[-tail:] *= np.linspace(1, 0, tail)
    return norm(x, peak)


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
    return kenney("impactPunch_medium_000", 0.3)


def hit_metal():
    return kenney("impactMetal_medium_000", 0.27)


def hit_stone():
    return kenney("impactMining_000", 0.45)


def critical():
    n = int(RATE * 0.6)
    x = pad(kenney("impactPunch_heavy_000", 0.6), n) + 0.7 * np.roll(pad(kenney("impactMetal_heavy_000", 0.17), n), int(RATE * 0.03))
    return norm(x)


def miss():
    n = 0.28
    x = noise(n, 5)
    x = lowpass(x, 3500) - lowpass(x, 600)
    x *= np.sin(np.pi * np.linspace(0, 1, len(x))) ** 2
    return norm(fade(x), 0.6)


def downed():
    return kenney("impactSoft_heavy_000", 0.5)


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
    return kenney("footstep00", 0.2, 0.7)


def step_stone():
    return kenney("footstep_concrete_000", 0.11, 0.7)


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
    return kenney("cloth1", 0.3, 0.6)


def land():
    return kenney("impactSoft_medium_000", 0.12, 0.75)


def turn_ally():
    return norm(fade(chirp_notes([(523, 0.09), (784, 0.16)])), 0.5)


def turn_enemy():
    return norm(fade(chirp_notes([(262, 0.1), (196, 0.2)])), 0.5)


def dice_roll():
    """면이 8번 바뀌는 굴림(0.45초)에 맞춘 사각파 틱 8개. 음높이는 씨앗 고정 난수로 고른다."""
    rng = np.random.default_rng(627)
    pitches = [587, 659, 740, 880, 988]
    x = np.zeros(int(RATE * 0.43))
    for k in range(8):
        s = int(RATE * 0.05 * k)
        tick = square(pitches[rng.integers(len(pitches))], 0.03, 0.25) * env(int(RATE * 0.03), 0.001, 0.02)
        click = highpass(noise(0.005, 700 + k), 2000) * env(int(RATE * 0.005), 0.0005, 0.002)
        tick[:len(click)] += 0.3 * click
        x[s:s + len(tick)] += tick
    return norm(fade(x), 0.45)


def roll_success():
    x = np.concatenate([chirp_notes([(784, 0.05), (988, 0.05), (1175, 0.05)]), chirp_notes([(1568, 0.15)])])
    return norm(fade(x), 0.5)


def roll_fail():
    x = np.concatenate([chirp_notes([(392, 0.07), (330, 0.07)], lambda f, d: square(f, d, 0.25)),
                        lowpass(sweep(247, 185, 0.18), 1200) * env(int(RATE * 0.18), 0.002, 0.14)])
    return norm(fade(x), 0.5)


def ambient(seed, cutoff, lfo, seconds=8.0):
    """처음과 끝을 이어 붙여 반복해도 끊기지 않게 한다(순환 잡음 + 정수 주기 LFO)."""
    n = int(RATE * seconds)
    spectrum = np.fft.rfft(np.random.default_rng(seed).uniform(-1, 1, n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum *= 1.0 / (1.0 + (freqs / cutoff) ** 2)
    x = np.fft.irfft(spectrum, n)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * lfo * np.arange(n) / RATE)
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
    "dice_roll": dice_roll, "roll_success": roll_success, "roll_fail": roll_fail,
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
