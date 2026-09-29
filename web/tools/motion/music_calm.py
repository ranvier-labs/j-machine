"""Calm variant of the lookbook soundtrack: piano-like tones, plucked
strings, a soft sine pad and a sine bass, in a small room. No drums, no
saw or square waves. It follows the same sections as music.py, read from
that file, so every cut still lands on a bar. Writes out/motion/music-calm.wav
and music-calm.json (the RMS envelope the HUD waveform reads).
With --pulse it adds a soft rhythm section (felt kick, brushed shaker,
rim click) for a middle ground between this and music.py, and writes
out/motion/music-calmer.wav/.json instead.
Usage: python3 tools/motion/music_calm.py [--pulse]
       node tools/motion/render.mjs --music out/motion/music-calmer --label <name>"""
import json, pathlib, re, sys, wave
import numpy as np

src = (pathlib.Path(__file__).parent / "music.py").read_text()
INTRO, BUILD, DROP1, BREAK, DROP2, OUTRO = eval(re.search(r"INTRO, BUILD, DROP1, BREAK, DROP2, OUTRO = (.*)", src).group(1))
bpm, rate = 128.0, 44100
beat = 60.0 / bpm; bar = 4 * beat; bars = OUTRO[1]
seconds = bars * bar; n = int(seconds * rate)
rng = np.random.default_rng(7)
dry = np.zeros(n)
PULSE = '--pulse' in sys.argv
NAME = 'music-calmer' if PULSE else 'music-calm'

def within(b, s): return s[0] <= b < s[1]
def midi(m): return 440.0 * 2 ** ((m - 69) / 12)
def add(start, sig, gain=1.0):
    i = int(start * rate); j = min(n, i + len(sig))
    if i < n: dry[i:j] += sig[:j - i] * gain

def piano(m, dur, vel):
    """Additive piano-like tone: slightly stretched partials, higher ones die sooner, a short hammer tick."""
    f = midi(m); L = int(dur * rate); tt = np.arange(L) / rate; sig = np.zeros(L)
    for k in range(1, 10):
        fk = f * k * np.sqrt(1 + 0.00035 * k * k)
        if fk > 9000: break
        sig += np.sin(2 * np.pi * fk * tt + rng.random() * 6.283) * np.exp(-tt * (0.7 + 0.6 * k)) / k ** 1.4
    sig *= np.minimum(1, tt / 0.003) * np.clip((dur - tt) / 0.25, 0, 1)
    sig += rng.standard_normal(L) * np.exp(-tt / 0.004) * 0.015
    return sig * vel

def pluck(m, dur, vel, damp=0.996):
    """Karplus-Strong string, computed one period at a time."""
    f = midi(m); N = max(2, int(rate / f)); L = int(dur * rate)
    y = np.zeros(L + N + 1); y[1:N + 1] = rng.uniform(-1, 1, N)
    for s0 in range(N + 1, L + N + 1, N):
        e = min(s0 + N, L + N + 1); y[s0:e] = damp * 0.5 * (y[s0 - N:e - N] + y[s0 - N - 1:e - N - 1])
    out = y[N + 1:N + 1 + L]; tt = np.arange(len(out)) / rate
    return out * np.clip((dur - tt) / 0.2, 0, 1) * vel

def pad(ms, dur, vel):
    """Sine pad with slow attack and release, a hair of detune."""
    L = int(dur * rate); tt = np.arange(L) / rate; sig = np.zeros(L)
    for m in ms:
        for det in (-0.35, 0.35): sig += np.sin(2 * np.pi * (midi(m) + det) * tt)
    env = np.minimum(1, tt / 1.2) * np.clip((dur - tt) / 1.0, 0, 1)
    return sig * env * vel / (2 * len(ms))

def bass(m, dur, vel):
    f = midi(m); L = int(dur * rate); tt = np.arange(L) / rate
    sig = np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)
    return sig * np.minimum(1, tt / 0.02) * np.exp(-tt / 1.4) * np.clip((dur - tt) / 0.1, 0, 1) * vel

# Am, F, C, G: one chord per bar. Piano voicing, bass note, two melody notes (half notes).
CHORDS = [((57, 60, 64, 69), 45, (76, 72)), ((53, 57, 60, 65), 41, (77, 72)), ((48, 52, 55, 60), 36, (76, 79)), ((55, 59, 62, 67), 43, (74, 71))]
for b in range(bars):
    voicing, root, melody = CHORDS[b % 4]; t0 = b * bar
    last = b == bars - 1
    if within(b, INTRO):
        for m in voicing: add(t0, piano(m, bar * 1.2, 0.30))
        add(t0, pad(voicing, bar * 1.1, 0.10))
    elif within(b, BUILD):
        grow = (b - BUILD[0] + 1) / (BUILD[1] - BUILD[0])
        for k, m in enumerate((voicing[0], voicing[2], voicing[1], voicing[3])): add(t0 + k * beat, piano(m, beat * 2.5, 0.22 + 0.18 * grow))
        add(t0, pad(voicing, bar * 1.1, 0.10 + 0.06 * grow))
    elif within(b, DROP1) or within(b, DROP2):
        full = within(b, DROP2)
        arp = (voicing[0], voicing[2], voicing[3], voicing[1] + 12, voicing[3], voicing[2], voicing[1], voicing[2])
        for k, m in enumerate(arp): add(t0 + k * beat / 2, piano(m, beat * 1.6, (0.30 if k % 2 == 0 else 0.22) + (0.06 if full else 0)))
        add(t0, bass(root, bar * 0.5, 0.30)); add(t0 + bar / 2, bass(root + (7 if b % 2 else 0), bar * 0.5, 0.24))
        add(t0, pad(voicing, bar * 1.1, 0.14 if full else 0.11))
        if full or b % 2 == 1:
            for k, m in enumerate(melody): add(t0 + k * bar / 2, pluck(m, bar * 0.55, 0.55))
    elif within(b, BREAK):
        for m in voicing: add(t0, piano(m, bar * 1.2, 0.20))
        add(t0, pad(voicing, bar * 1.1, 0.18))
        for k, m in enumerate(melody): add(t0 + k * bar / 2, pluck(m - 12, bar * 0.6, 0.6))
    elif within(b, OUTRO):
        fade = 1 - (b - OUTRO[0]) / (OUTRO[1] - OUTRO[0])
        chord = CHORDS[0][0] if last else voicing
        for m in chord: add(t0, piano(m, bar * (1.9 if last else 1.2), 0.28 * (0.5 + 0.5 * fade)))
        add(t0, pad(chord, bar * (1.0 if last else 1.1), 0.12 * fade))

# The rhythm section of the --pulse variant: soft, low, and only where the music already moves.
def kick(vel):
    L = int(0.35 * rate); tt = np.arange(L) / rate
    return np.sin(2 * np.pi * np.cumsum(48 + 60 * np.exp(-tt / 0.03)) / rate) * np.exp(-tt / 0.12) * np.minimum(1, tt / 0.002) * vel
def brush(vel, length=0.09):
    L = int(length * rate); tt = np.arange(L) / rate; x = rng.standard_normal(L)
    x = x - np.convolve(x, np.ones(9) / 9, mode="same")      # drop the low end
    x = np.convolve(x, np.ones(3) / 3, mode="same")          # and the harshest top
    return x * np.exp(-tt / (length / 3)) * np.minimum(1, tt / 0.004) * vel
def rim(vel):
    L = int(0.06 * rate); tt = np.arange(L) / rate
    return (np.sin(2 * np.pi * 1750 * tt) * 0.6 + rng.standard_normal(L) * 0.25) * np.exp(-tt / 0.012) * vel
if PULSE:
    for b in range(bars):
        t0 = b * bar
        if within(b, BUILD) and b >= BUILD[1] - 2: add(t0, kick(0.30)); add(t0 + 2 * beat, kick(0.22))
        elif within(b, DROP1):
            for k in (0, 2): add(t0 + k * beat, kick(0.34))
            for k in range(8): add(t0 + k * beat / 2, brush(0.05 if k % 2 else 0.08))
        elif within(b, DROP2):
            for k in range(4): add(t0 + k * beat, kick(0.36 if k % 2 == 0 else 0.26))
            for k in range(16): add(t0 + k * beat / 4, brush(0.035 if k % 2 else 0.06, 0.07))
            for k in (1, 3): add(t0 + k * beat, rim(0.10))
        elif within(b, OUTRO) and b < OUTRO[1] - 2: add(t0, kick(0.22))

# A small room: exponentially decaying noise, different for each ear, applied by FFT convolution.
def room(x, seed):
    r = np.random.default_rng(seed); L = int(1.3 * rate); tt = np.arange(L) / rate
    ir = r.standard_normal(L) * np.exp(-tt / 0.32); ir = np.convolve(ir, np.ones(6) / 6, mode="same"); ir[0] = 0; ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + L)))
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
left = dry + 0.28 * room(dry, 1); right = dry + 0.28 * room(dry, 2)
tt = np.arange(n) / rate
fade = np.minimum(1, tt / 0.4) * np.minimum(1, (seconds - tt) / 3.0)
stereo = np.stack([left * fade, right * fade], axis=1)
stereo *= 0.89 / np.max(np.abs(stereo))
with wave.open(f"out/motion/{NAME}.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes((stereo * 32767).astype(np.int16).tobytes())
mono = stereo.mean(axis=1); hop = rate // 30
rms = [float(np.sqrt(np.mean(mono[i:i + hop] ** 2))) for i in range(0, n - hop, hop)]
peak = max(rms) or 1
json.dump({"bpm": bpm, "seconds": seconds, "fps": 30, "rms": [round(v / peak, 3) for v in rms],
           "sections": {"intro": INTRO, "build": BUILD, "drop1": DROP1, "break": BREAK, "drop2": DROP2, "outro": OUTRO}}, open(f"out/motion/{NAME}.json", "w"))
print(f"wrote out/motion/{NAME}.wav ({seconds:.1f}s, {bars} bars) and {NAME}.json")
