"""Placeholder soundtrack: a 128 BPM instrumental so the cut has a grid to sit
on. Replace out/motion/music.wav with a real track (for example one generated
from the lyric sheet in looks.js) and re-run render.mjs; the waveform bars in
the HUD are read from music.json, which this script also writes.
Usage: python3 tools/motion/music.py <seconds> [bpm]"""
import json, math, sys, wave
import numpy as np

seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 100.0
bpm = float(sys.argv[2]) if len(sys.argv) > 2 else 128.0
rate = 44100
n = int(seconds * rate)
t = np.arange(n) / rate
beat = 60.0 / bpm
rng = np.random.default_rng(1991)

def env(times, decay, length):
    """Sum of exponential envelopes triggered at `times`."""
    out = np.zeros(n)
    for start in times:
        i = int(start * rate)
        if i >= n: break
        span = min(n - i, int(length * rate))
        out[i:i + span] += np.exp(-np.arange(span) / rate / decay)
    return out

beats = np.arange(0, seconds, beat)
bars = np.arange(0, seconds, beat * 4)
# Kick: pitched-down sine on every beat.
kick_env = env(beats, 0.09, 0.5)
phase = np.cumsum(60 + 140 * np.exp(-((t % beat) / 0.04))) / rate * 2 * np.pi
kick = np.sin(phase) * kick_env * 0.9
# Hats: filtered noise on off-beats, shorter on the 16ths.
hat_env = env(beats + beat / 2, 0.03, 0.15) + 0.35 * env(np.arange(beat / 4, seconds, beat / 2), 0.015, 0.08)
noise = rng.standard_normal(n)
hat = noise * hat_env * 0.18
# Bass: an eight-note sequence in A minor, one note per half beat, square-ish.
seq = [45, 45, 52, 45, 48, 45, 43, 45]  # MIDI
half = beat / 2
idx = np.minimum((t // half).astype(int) % len(seq), len(seq) - 1)
freqs = 440 * 2 ** ((np.array(seq)[idx] - 69) / 12)
bass_phase = np.cumsum(freqs) / rate
bass = (np.sign(np.sin(2 * np.pi * bass_phase)) * 0.4 + np.sin(2 * np.pi * bass_phase) * 0.6)
bass *= env(np.arange(0, seconds, half), 0.12, half) * 0.35
# Pad: detuned saws on Am, swelling every four bars; sidechained to the kick.
chord = [57, 60, 64, 69]
pad = np.zeros(n)
for note in chord:
    f = 440 * 2 ** ((note - 69) / 12)
    for det in (-0.4, 0.4):
        pad += ((t * (f + det)) % 1.0 - 0.5)
pad *= 0.045 * (0.6 + 0.4 * np.sin(2 * np.pi * t / (beat * 16) - np.pi / 2))
duck = 1 - 0.7 * np.clip(kick_env, 0, 1)
mix = kick + hat + bass + pad * duck
# Section markers: every 8 bars a short rising blip, as a cue for cuts.
blips = env(bars[::8], 0.05, 0.2)
mix += np.sin(2 * np.pi * 1760 * t) * blips * 0.12
# Simple one-pole low-pass, soft clip, bit reduction for a retro grain.
kernel = np.exp(-np.arange(24) / 6.0); kernel /= kernel.sum()
lp = np.convolve(mix, kernel, mode="same")
out = np.tanh(lp * 1.6) * 0.8
out = np.round(out * 2047) / 2047
fade = np.minimum(1, t / 0.5) * np.minimum(1, (seconds - t) / 3.0)
out *= fade
stereo = np.stack([out, out], axis=1)
with wave.open("out/motion/music.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes((stereo * 32767).astype(np.int16).tobytes())
# RMS envelope at 30 Hz for the HUD waveform.
hop = rate // 30
rms = [float(np.sqrt(np.mean(out[i:i + hop] ** 2))) for i in range(0, n - hop, hop)]
peak = max(rms) or 1
json.dump({"bpm": bpm, "seconds": seconds, "fps": 30, "rms": [round(v / peak, 3) for v in rms]}, open("out/motion/music.json", "w"))
print(f"wrote out/motion/music.wav ({seconds:.0f}s at {bpm:.0f} BPM) and music.json ({len(rms)} samples)")
