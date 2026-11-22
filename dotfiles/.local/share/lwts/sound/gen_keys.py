#!/usr/bin/env python3
"""LWTS Keys: piano / electric piano / synth pluck notes (C3..C6, chromatic) and short phrases built from them - the default LWTS sounds.
Run: python3 -I gen_keys.py -> ~/.local/share/sounds/lwts/{piano,ep,pluck}-<note>.oga and the phrase files. Pure synthesis, no samples."""
import sys, os as _os; sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import common
import math, struct, wave, os, subprocess, tempfile, random
R = 32000
OUT = os.path.expanduser("~/.local/share/sounds/lwts")
NAMES = ["c", "cs", "d", "ds", "e", "f", "fs", "g", "gs", "a", "as", "b"]
def freq(name, octave): return 440.0 * 2 ** ((NAMES.index(name) + 12 * (octave - 4) - 9) / 12)

def piano(f, dur, vel=1.0):
    n = int(R * dur); out = [0.0] * n
    B = 0.00012 * (f / 261.63) ** 1.5                      # string stiffness: slightly sharp upper partials
    for k in range(1, 11):
        fk = k * f * math.sqrt(1 + B * k * k)
        if fk > 9000: break
        a = vel / (k ** 1.15) * (1.0 if k != 1 else 1.0)
        rate = 1.6 + 1.1 * k + 0.0016 * f                  # higher partials die faster
        w1, w2 = 2 * math.pi * fk / R, 2 * math.pi * (fk + 0.35) / R   # two slightly detuned strings
        for i in range(n):
            out[i] += a * 0.5 * (math.sin(w1 * i) + math.sin(w2 * i)) * math.exp(-rate * i / R)
    rnd = random.Random(int(f)); hn = int(R * 0.012)       # hammer: a short soft noise
    prev = 0.0
    for i in range(min(hn, n)):
        prev += 0.25 * (rnd.uniform(-1, 1) - prev); out[i] += prev * 0.35 * vel * (1 - i / hn) ** 2
    return finish(out, 0.9)

def epiano(f, dur, vel=1.0):   # FM tine: sine carrier, decaying modulation, faint bell partial
    n = int(R * dur); out = []
    for i in range(n):
        t = i / R
        idx = 1.8 * math.exp(-t * 7) + 0.25
        v = math.sin(2 * math.pi * f * t + idx * math.sin(2 * math.pi * f * t)) \
            + 0.12 * math.exp(-t * 14) * math.sin(2 * math.pi * f * 14 * t)
        out.append(v * vel * math.exp(-t * 3.0))
    return finish(out, 0.55)

def pluck(f, dur, vel=1.0):    # synth pluck: saw partials with a closing "filter"
    n = int(R * dur); out = [0.0] * n
    for k in range(1, 22):
        fk = k * f
        if fk > 9000: break
        w = 2 * math.pi * fk / R; rate = 2.2 + 1.5 * k
        for i in range(n):
            out[i] += vel / k * math.sin(w * i) * math.exp(-rate * i / R)
    return finish(out, 0.55)

def finish(x, peak):
    n = len(x); m = max(1e-9, max(abs(v) for v in x))
    fade = int(R * 0.05)
    for i in range(n):
        g = peak / m
        if i < int(R * 0.002): g *= i / (R * 0.002)
        if i > n - fade: g *= (n - i) / fade
        x[i] *= g
    return x

def mix(parts, tail=0.0):
    """parts: [(start_s, samples)] -> one buffer (clipped softly)"""
    n = max(int(R * s) + len(x) for s, x in parts); out = [0.0] * n
    for s, x in parts:
        o = int(R * s)
        for i, v in enumerate(x): out[o + i] += v
    m = max(1.0, max(abs(v) for v in out))
    return [v / m * 0.9 for v in out]

def write_oga(path, samples): return common.write_oga(path, samples, R)

os.makedirs(OUT, exist_ok=True)
# 1. the note library, 3 timbres
for oct_ in (3, 4, 5, 6):
    for nm in NAMES:
        if oct_ == 6 and nm != "c": continue
        f = freq(nm, oct_)
        for kind, fn, dur in (("piano", piano, 1.3), ("ep", epiano, 1.1), ("pluck", pluck, 0.7)):
            write_oga(f"{OUT}/{kind}-{nm}{oct_}.oga", fn(f, dur))
# 2. phrases - the LWTS defaults
P = lambda nm, o, d=0.7, v=1.0: piano(freq(nm, o), d, v)
PH = {
  "piano-rise":        mix([(0.0, P("e", 5, 0.5, 0.8)), (0.09, P("b", 5, 0.8, 0.9))]),                          # notification
  "piano-low-alert":   mix([(0.0, P("a", 3, 0.8)), (0.16, P("a", 3, 0.8)), (0.32, P("e", 3, 1.0))]),            # urgent
  "piano-fifth-up":    mix([(0.0, P("c", 5, 0.7)), (0.07, P("g", 5, 0.9))]),                                    # charger in
  "piano-fifth-down":  mix([(0.0, P("g", 5, 0.7)), (0.07, P("c", 5, 0.9))]),                                    # charger out
  "piano-tick":        P("c", 6, 0.18, 0.6),                                                                     # volume
  "pluck-snap":        mix([(0.0, pluck(freq("c", 6), 0.25, 0.9)), (0.03, pluck(freq("g", 5), 0.3, 0.6))]),     # screenshot
  "piano-arpeggio-up": mix([(i * 0.11, P(n_, o, 1.0 - i * 0.1)) for i, (n_, o) in enumerate((("c", 5), ("e", 5), ("g", 5), ("c", 6)))]),
  "piano-chord":       mix([(0.0, P("c", 4, 1.2, 0.9)), (0.0, P("e", 4, 1.2, 0.8)), (0.0, P("g", 4, 1.2, 0.8)), (0.0, P("c", 5, 1.2, 0.7))]),
  "ep-bell-pair":      mix([(0.0, epiano(freq("g", 5), 0.8)), (0.12, epiano(freq("c", 6), 0.9))]),
  "ep-chord":          mix([(0.0, epiano(freq("c", 4), 1.2)), (0.0, epiano(freq("e", 4), 1.2)), (0.0, epiano(freq("a", 4), 1.2))]),
}
for name, smp in PH.items(): write_oga(f"{OUT}/{name}.oga", smp)
lines = [f"keys\tnote\t{k}-{nm}{o}\n" for o in (3, 4, 5, 6) for nm in NAMES if not (o == 6 and nm != "c") for k in ("piano", "ep", "pluck")]
open(OUT + "/manifest-keys.tsv", "w").write("".join(lines) + "".join(f"keys\tphrase\t{k}\n" for k in PH))
print(len(PH), "phrases ->", OUT)
