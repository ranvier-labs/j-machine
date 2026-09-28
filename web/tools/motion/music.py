"""Soundtrack for the lookbook: a 128 BPM instrumental with sections that
follow the three acts (intro, build, drop, break, second drop, outro), so the
cut has somewhere to go. Still a placeholder for a produced track; the
lyric sheet in README.md is the brief for one. Also writes music.json, the
RMS envelope the HUD waveform reads.
Usage: python3 tools/motion/music.py <bars> [bpm]"""
import json, sys, wave
import numpy as np

bars = int(sys.argv[1]) if len(sys.argv) > 1 else 45
bpm = float(sys.argv[2]) if len(sys.argv) > 2 else 128.0
rate = 44100
beat = 60.0 / bpm
bar = beat * 4
seconds = bars * bar
n = int(seconds * rate)
t = np.arange(n) / rate
rng = np.random.default_rng(1991)

# Sections in bars: [start, end).
INTRO, BUILD, DROP1, BREAK, DROP2, OUTRO = (0, 4), (4, 9), (9, 25), (25, 31), (31, 41), (41, 45)
def in_section(b, s): return s[0] <= b < s[1]
def bar_of(time): return int(time // bar)

def midi(m): return 440 * 2 ** ((m - 69) / 12)
def env(times, decay, length, curve=1.0):
    out = np.zeros(n)
    for start in times:
        i = int(start * rate)
        if i >= n: break
        span = min(n - i, int(length * rate))
        out[i:i + span] += np.exp(-np.arange(span) / rate / decay) ** curve
    return out
def lowpass_fast(x, cutoff_hz):
    """First-order low-pass with a per-block cutoff (Hz per 512-sample block), computed in closed form per block."""
    out = np.empty_like(x); y = 0.0; block = 128
    for i in range(0, n, block):
        fc = cutoff_hz[min(len(cutoff_hz) - 1, i // 512)]
        a = 1 - np.exp(-2 * np.pi * fc / rate)
        seg = x[i:i + block]
        # y[k] = (1-a) y[k-1] + a x[k]  → closed form with powers
        k = np.arange(len(seg))
        decay = (1 - a) ** (k + 1)
        conv = a * np.cumsum(seg * (1 - a) ** (-k - 1.0)) * (1 - a) ** (k + 1) if a < 0.99 else seg
        y_block = y * decay + conv
        out[i:i + len(seg)] = y_block; y = y_block[-1]
    return out

# Chords: Am F C G, one per bar. (root, third, fifth) as MIDI.
CHORDS = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
chord_at = lambda b: CHORDS[b % 4]

# ---- kick ------------------------------------------------------------------
kick_times = []
for b in range(bars):
    if in_section(b, BUILD) and b >= BUILD[1] - 3: kick_times += [b * bar, b * bar + 2 * beat]
    elif in_section(b, DROP1) or in_section(b, DROP2): kick_times += [b * bar + k * beat for k in range(4)]
    elif in_section(b, OUTRO) and b < OUTRO[1] - 2: kick_times += [b * bar, b * bar + 2 * beat]
kick_env = env(kick_times, 0.10, 0.6)
pitch = np.zeros(n)
for s in kick_times:
    i = int(s * rate); span = min(n - i, int(0.6 * rate)); pitch[i:i + span] = 50 + 130 * np.exp(-np.arange(span) / rate / 0.035)
kick = np.sin(np.cumsum(np.where(pitch > 0, pitch, 0)) / rate * 2 * np.pi) * kick_env * 1.0
# impacts at the two drops: a low boom plus a noise burst
impact = env([DROP1[0] * bar, DROP2[0] * bar], 0.5, 2.5)
kick += np.sin(2 * np.pi * 42 * t) * impact * 0.7 + rng.standard_normal(n) * env([DROP1[0] * bar, DROP2[0] * bar], 0.25, 1.5) * 0.25

# ---- snare / clap -------------------------------------------------------------
snare_times = []
for b in range(bars):
    if in_section(b, DROP1) or in_section(b, DROP2): snare_times += [b * bar + beat, b * bar + 3 * beat]
    if b in (BUILD[1] - 1, BREAK[1] - 1): snare_times += [b * bar + k * beat / 4 for k in range(16)]  # fill
snare = rng.standard_normal(n) * env(snare_times, 0.06, 0.3) * 0.35 + np.sin(2 * np.pi * 190 * t) * env(snare_times, 0.03, 0.1) * 0.4

# ---- hats ------------------------------------------------------------------
hat_times = []
for b in range(bars):
    if in_section(b, DROP1): hat_times += [b * bar + beat / 2 + k * beat for k in range(4)]
    if in_section(b, DROP2): hat_times += [b * bar + k * beat / 4 for k in range(16)]
    if in_section(b, BUILD) and b >= BUILD[0] + 2: hat_times += [b * bar + beat / 2 + k * beat for k in range(4)]
hat = rng.standard_normal(n) * env(hat_times, 0.025, 0.12) * 0.16
# the clock: quiet 16th-note ticks in the intro and the first act (waiting)
tick_times = [k * beat / 4 for k in range(int(BUILD[1] * bar / (beat / 4)))]
hat += np.sin(2 * np.pi * 3200 * t) * env(tick_times, 0.006, 0.03) * 0.12

# ---- bass ------------------------------------------------------------------
bass = np.zeros(n); step = beat / 2
for k in range(int(seconds / step)):
    s = k * step; b = bar_of(s)
    if in_section(b, INTRO) or in_section(b, BREAK): continue
    if in_section(b, BUILD) and (k % 2): continue
    root = chord_at(b)[0] - 12
    note = root + (12 if (in_section(b, DROP2) and k % 4 == 2) else 0)
    i = int(s * rate); span = min(n - i, int(step * rate))
    tt = np.arange(span) / rate; f = midi(note)
    wave_ = np.sign(np.sin(2 * np.pi * f * tt)) * 0.35 + np.sin(2 * np.pi * f * tt) * 0.65
    bass[i:i + span] += wave_ * np.exp(-tt / 0.18) * (0.42 if in_section(b, DROP1) or in_section(b, DROP2) else 0.3)

# ---- pad -------------------------------------------------------------------
pad = np.zeros(n)
for b in range(bars):
    i = int(b * bar * rate); span = min(n - i, int(bar * rate * 1.05)); tt = np.arange(span) / rate
    level = 0.9 if in_section(b, BREAK) else 1.4 if in_section(b, INTRO) else 0.7
    if in_section(b, OUTRO): level = 0.6 * (1 - (b - OUTRO[0]) / (OUTRO[1] - OUTRO[0]))
    attack = np.minimum(1, tt / 0.6); release = np.minimum(1, (span / rate - tt) / 0.4)
    for m in chord_at(b) + (chord_at(b)[0] + 12,):
        f = midi(m)
        for det in (-0.6, 0.6): pad[i:i + span] += ((tt * (f + det)) % 1.0 - 0.5) * 0.028 * level * attack * release

# ---- lead: an arpeggio in the second drop, a slow motif in the break -------------
lead = np.zeros(n)
for k in range(int(seconds / (beat / 4))):
    s = k * beat / 4; b = bar_of(s)
    if not in_section(b, DROP2): continue
    chord = chord_at(b); tones = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24]
    note = tones[k % 4] if (b % 2 == 0) else tones[(3 - k) % 4]
    i = int(s * rate); span = min(n - i, int(beat / 4 * rate * 1.8)); tt = np.arange(span) / rate; f = midi(note)
    lead[i:i + span] += np.sign(np.sin(2 * np.pi * f * tt) - 0.3) * np.exp(-tt / 0.12) * 0.09
motif = [(0, 76), (1, 72), (2, 74), (3, 69), (4, 72), (6, 67), (8, 69), (10, 71), (12, 72), (14, 76)]
for b0 in ([BREAK[0], BREAK[0] + 4] if BREAK[1] - BREAK[0] >= 8 else [BREAK[0]]):
    for off, m in motif:
        s = b0 * bar + off * beat / 2 * 2 / 2; i = int(s * rate); span = min(n - i, int(beat * 1.8 * rate)); tt = np.arange(span) / rate
        lead[i:i + span] += np.sin(2 * np.pi * midi(m) * tt) * np.minimum(1, tt / 0.03) * np.exp(-tt / 0.6) * 0.14
# echo on the lead
d = int(beat * 3 / 4 * rate); lead[d:] += lead[:-d] * 0.35

# ---- risers before each drop -----------------------------------------------------
riser = np.zeros(n)
for end in (DROP1[0], DROP2[0]):
    s0 = (end - 2) * bar; i = int(s0 * rate); span = min(n - i, int(2 * bar * rate)); tt = np.arange(span) / rate; u = tt / (2 * bar)
    riser[i:i + span] += rng.standard_normal(span) * (u ** 2) * 0.28 + np.sin(2 * np.pi * (220 + 660 * u ** 2) * tt) * u * 0.12

# ---- mix, filter automation, sidechain, master ----------------------------------------
duck = 1 - 0.65 * np.clip(kick_env, 0, 1)
mix = kick + snare + hat + (bass + pad + lead) * duck + riser
blocks = n // 512 + 1
cut = np.empty(blocks)
for i in range(blocks):
    b = bar_of(i * 512 / rate)
    if in_section(b, INTRO): c = 1500
    elif in_section(b, BUILD): c = 1500 + (b - BUILD[0]) / (BUILD[1] - BUILD[0]) * 7000
    elif in_section(b, BREAK): c = 2600
    elif in_section(b, OUTRO): c = 8000 - (b - OUTRO[0]) / (OUTRO[1] - OUTRO[0]) * 7200
    else: c = 9000
    cut[i] = c
filtered = lowpass_fast(mix, cut)
out = np.tanh(filtered * 1.5) * 0.85
out = np.round(out * 2047) / 2047
out *= np.minimum(1, t / 0.3) * np.minimum(1, (seconds - t) / 4.0)
out /= max(1e-6, np.max(np.abs(out))) / 0.89
with wave.open("out/motion/music.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes((np.stack([out, out], axis=1) * 32767).astype(np.int16).tobytes())
hop = rate // 30
rms = [float(np.sqrt(np.mean(out[i:i + hop] ** 2))) for i in range(0, n - hop, hop)]
peak = max(rms) or 1
json.dump({"bpm": bpm, "seconds": seconds, "fps": 30, "rms": [round(v / peak, 3) for v in rms],
           "sections": {"intro": INTRO, "build": BUILD, "drop1": DROP1, "break": BREAK, "drop2": DROP2, "outro": OUTRO}}, open("out/motion/music.json", "w"))
print(f"wrote out/motion/music.wav ({seconds:.1f}s, {bars} bars at {bpm:.0f} BPM) and music.json")
