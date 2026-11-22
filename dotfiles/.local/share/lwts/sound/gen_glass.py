#!/usr/bin/env python3
"""LWTS Glass: soft, rounded interface sounds in the spirit of macOS / iOS (glassy taps, pops, sonar, bottle, tri-chime) - original
synthesis, named by how they sound. Run: python3 -I gen_glass.py -> ~/.local/share/sounds/lwts/<name>.oga"""
import sys, os as _os; sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import common
import math, struct, wave, os, subprocess, tempfile, random
R = 32000
OUT = os.path.expanduser("~/.local/share/sounds/lwts")
TAU = 2 * math.pi

def fin(x, peak=0.8, fade=0.03):
    n = len(x); m = max(1e-9, max(abs(v) for v in x)); f = int(R * fade); a = int(R * 0.002)
    for i in range(n):
        g = peak / m * (i / a if i < a else 1.0) * ((n - i) / f if i > n - f else 1.0)
        x[i] *= g
    return x

def partials(f, dur, parts, decay):
    """parts: [(ratio, amp, extra_decay)] -> a struck, ringing tone"""
    n = int(R * dur); out = [0.0] * n
    for ratio, amp, xd in parts:
        w = TAU * f * ratio / R; d = decay + xd
        for i in range(n): out[i] += amp * math.sin(w * i) * math.exp(-d * i / R)
    return out

def glide(f0, f1, dur, decay, amp=1.0):
    n = int(R * dur); ph = 0.0; out = []
    for i in range(n):
        t = i / n; ph += TAU * (f0 + (f1 - f0) * t) / R
        out.append(amp * math.sin(ph) * math.exp(-decay * i / R))
    return out

def noise_band(dur, f_lo, f_hi, decay, seed=3):   # low-passed noise minus a slower low-pass = a rough band
    rnd = random.Random(seed); n = int(R * dur); a = min(0.99, TAU * f_hi / R); b = min(0.99, TAU * f_lo / R); p = q = 0.0; out = []
    for i in range(n):
        v = rnd.uniform(-1, 1); p += a * (v - p); q += b * (p - q); out.append((p - q) * math.exp(-decay * i / R))
    return out

def mix(parts):
    n = max(int(R * s) + len(x) for s, x in parts); out = [0.0] * n
    for s, x in parts:
        o = int(R * s)
        for i, v in enumerate(x): out[o + i] += v
    return out

def bell(f, dur=0.5, amp=1.0, decay=7.0): return partials(f, dur, [(1, 1.0 * amp, 0), (2.0, 0.35 * amp, 4), (3.01, 0.18 * amp, 9), (4.2, 0.08 * amp, 14)], decay)

S = {
  "glass-tap":    fin(partials(1760, 0.55, [(1, 1.0, 0), (2.76, 0.45, 6), (5.4, 0.25, 12), (8.9, 0.1, 20)], 6.0)),
  "ping-up":      fin(mix([(0, glide(1180, 1320, 0.5, 5.5)), (0, glide(2360, 2640, 0.5, 9.0, 0.3))])),
  "soft-pop":     fin(glide(760, 240, 0.11, 22.0)),
  "tiny-tink":    fin(partials(3100, 0.18, [(1, 1.0, 0), (2.4, 0.5, 10), (4.1, 0.3, 20)], 26.0)),
  "deep-sonar":   fin(mix([(0, glide(560, 540, 1.1, 3.2)), (0.28, glide(560, 540, 0.9, 4.0, 0.45)), (0.52, glide(560, 540, 0.7, 5.0, 0.2))])),
  "bottle-blow":  fin(mix([(0, noise_band(0.5, 90, 900, 4.0, 5)), (0, glide(470, 470, 0.5, 5.0, 0.7))]), 0.7),
  "wood-tick":    fin(partials(930, 0.12, [(1, 1.0, 0), (1.73, 0.5, 10), (2.9, 0.2, 20)], 38.0)),
  "tri-chime":    fin(mix([(0.00, bell(1318.5, 0.5)), (0.11, bell(1568.0, 0.5)), (0.22, bell(2093.0, 0.8))])),
  "hero-rise":    fin(mix([(0.00, glide(523.25, 523.25, 0.35, 2.5)), (0.13, glide(783.99, 783.99, 0.35, 2.5)), (0.26, glide(1046.5, 1046.5, 0.7, 2.2)),
                          (0.26, glide(1318.5, 1318.5, 0.7, 2.6, 0.5))])),
  "funk-thud":    fin(mix([(0, glide(190, 70, 0.22, 11.0)), (0, noise_band(0.02, 200, 3000, 60.0, 8))])),
  "morse-pair":   fin(mix([(0, glide(880, 880, 0.08, 10.0)), (0.12, glide(880, 880, 0.12, 10.0))])),
  "purr-low":     fin([glide(110, 110, 0.6, 3.0)[i] * (0.65 + 0.35 * math.sin(TAU * 26 * i / R)) for i in range(int(R * 0.6))]),
  "low-fall":     fin(mix([(0, glide(310, 140, 0.55, 5.0)), (0, glide(620, 280, 0.55, 8.0, 0.25))])),
  "whoosh-up":    fin([v * (i / (R * 0.28)) ** 0.7 for i, v in enumerate(noise_band(0.28, 400, 6000, 2.0, 11))], 0.6),
  "snap-click":   fin(mix([(0, noise_band(0.03, 300, 5000, 90.0, 21)), (0.02, glide(1500, 900, 0.06, 40.0, 0.5))])),
  "sparkle-up":   fin(mix([(i * 0.045, bell(f, 0.45, 1.0 - i * 0.12, 9.0)) for i, f in enumerate((1568.0, 1975.5, 2349.3, 3135.9))])),
  "keycap-tap":   fin(mix([(0, noise_band(0.025, 500, 4500, 110.0, 31)), (0, glide(300, 200, 0.03, 70.0, 0.4))]), 0.55),
  "glass-pair":   fin(mix([(0, partials(1480, 0.45, [(1, 1.0, 0), (2.76, 0.4, 6), (5.4, 0.2, 12)], 7.0)),
                           (0.1, partials(1976, 0.5, [(1, 1.0, 0), (2.76, 0.4, 6), (5.4, 0.2, 12)], 7.0))])),
}

def write_oga(path, samples): return common.write_oga(path, samples, R)

os.makedirs(OUT, exist_ok=True)
for name, smp in S.items(): write_oga(f"{OUT}/{name}.oga", smp)
open(OUT + "/manifest-glass.tsv", "w").write("".join(f"glass\tphrase\t{k}\n" for k in S))
print(len(S), "sounds ->", OUT)
