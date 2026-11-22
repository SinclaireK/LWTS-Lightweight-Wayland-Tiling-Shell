#!/usr/bin/env python3
"""LWTS Retro: minimalist 8-bit sounds, named by how they sound.
Run: python3 -I gen_theme.py  -> ~/.local/share/sounds/lwts/<name>.oga. Pure tones, no samples, no licences."""
import sys, os as _os; sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import common
import math, struct, wave, os, subprocess, tempfile, random
R = 44100
OUT = os.path.expanduser("~/.local/share/sounds/lwts")
N = dict(C4=261.63, G4=392.0, A4=440.0, E4=329.63, C5=523.25, D5=587.33, E5=659.25, F5=698.46, G5=783.99, A5=880.0, B5=987.77,
         C6=1046.5, D6=1174.7, E6=1318.5, G6=1568.0, A6=1760.0)

def tone(notes, kind="square", vol=0.28, duty=0.5, gap=12):
    """notes: [(freq, ms, glide_to|None)]; 4 ms attack, curved decay, `gap` ms of silence between notes"""
    out = []
    for f, ms, g in notes:
        n = int(R * ms / 1000); ph = 0.0
        for i in range(n):
            t = i / n; fr = f + ((g - f) * t if g else 0); ph += fr / R; p = ph % 1.0
            v = (1.0 if p < duty else -1.0) if kind == "square" else (1.0 if p < 0.25 else -1.0) if kind == "pulse" \
                else 4 * abs(p - 0.5) - 1 if kind == "tri" else math.sin(2 * math.pi * p)
            out.append(v * min(1.0, i / (R * 0.004)) * (1 - t) ** 1.6 * vol)
        out += [0.0] * int(R * gap / 1000)
    return out

def click(ms=40, vol=0.35):   # noise burst for shutter / capture
    rnd = random.Random(7); n = int(R * ms / 1000)
    return [(rnd.uniform(-1, 1)) * (1 - i / n) ** 3 * vol for i in range(n)]

def seq(*parts):
    o = []
    for p in parts: o += p
    return o

n = N
# sounds are named by how they sound; which event plays which is decided in Sounds.qml (defaults) and Settings -> System sounds
SOUNDS = {
  "blip-rise":       tone([(n["E6"], 55, None), (n["A6"], 85, None)], "pulse", 0.22),
  "blip-fall":       tone([(n["A6"], 55, None), (n["E6"], 70, None)], "pulse", 0.2),
  "triple-rise":     tone([(n["G5"], 70, None), (n["C6"], 70, None), (n["E6"], 110, None)], "pulse", 0.22),
  "ping":            tone([(n["B5"] * 2, 150, None)], "sine", 0.4),
  "double-ping":     tone([(n["B5"] * 2, 90, None), (n["B5"] * 2, 140, None)], "sine", 0.4, gap=60),
  "quad-ping":       tone([(n["B5"] * 2, 90, None)] * 4, "sine", 0.4, gap=70),
  "chirp-up":        tone([(n["C6"], 100, n["G6"])], "tri", 0.45),
  "sweep-down":      tone([(n["G6"], 140, n["C5"])], "tri", 0.4),
  "alarm-two-tone":  tone([(n["A5"], 90, None), (n["E5"], 90, None), (n["A5"], 90, None), (n["E5"], 140, None)], "pulse", 0.22),
  "buzz-low":        tone([(n["C4"] * 2, 90, None), (n["C4"] * 2, 90, None), (n["C4"], 200, None)], "pulse", 0.28),
  "question-rise":   tone([(n["E5"], 80, None), (n["B5"], 140, None)], "tri", 0.45),
  "arp-up":          tone([(n["C6"], 45, None), (n["E6"], 45, None), (n["G6"], 80, None)], "pulse", 0.22),
  "arp-down":        tone([(n["G6"], 45, None), (n["E6"], 45, None), (n["C6"], 80, None)], "pulse", 0.22),
  "bright-run":      tone([(n["C6"], 60, None), (n["E6"], 60, None), (n["G6"], 130, None)], "square", 0.2),
  "soft-fall":       tone([(n["E5"], 90, None), (n["C5"], 160, None)], "pulse", 0.28),
  "coin-up":         tone([(n["B5"], 55, None), (n["E6"], 160, None)], "square", 0.2),
  "coin-down":       tone([(n["E6"], 55, None), (n["B5"], 160, None)], "square", 0.2),
  "stairs-up":       tone([(n["C5"], 60, None), (n["G5"], 60, None), (n["C6"], 110, None)], "tri", 0.45),
  "stairs-down":     tone([(n["C6"], 60, None), (n["G5"], 60, None), (n["C5"], 140, None)], "tri", 0.45),
  "tick":            tone([(n["A5"], 35, None)], "sine", 0.35),
  "shutter":         seq(click(35), tone([(n["E6"], 60, None)], "tri", 0.3)),
  "melody-up":       tone([(n["C5"], 80, None), (n["E5"], 80, None), (n["G5"], 80, None), (n["C6"], 200, None)], "tri", 0.45),
  "melody-down":     tone([(n["C6"], 80, None), (n["G5"], 80, None), (n["E5"], 80, None), (n["C5"], 220, None)], "tri", 0.45),
  "test-tone":       tone([(440.0, 500, None)], "sine", 0.4),
}

def write_oga(path, samples): return common.write_oga(path, samples, R)

os.makedirs(OUT, exist_ok=True)
for name, smp in SOUNDS.items(): write_oga(f"{OUT}/{name}.oga", smp)
open(OUT + "/manifest-retro.tsv", "w").write("".join(f"retro\tphrase\t{k}\n" for k in SOUNDS))
print(len(SOUNDS), "sounds ->", OUT)
