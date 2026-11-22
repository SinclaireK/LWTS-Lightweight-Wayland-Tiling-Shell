#!/usr/bin/env python3
"""LWTS Easter egg: slot-machine sounds for a long scroll in the wallpaper / palette picker - original synthesis.
reel-jackpot = a slot-machine win: ding-ding-ding, two airhorn stabs
(the meme), a coin shower.
Run: python3 -I gen_casino.py -> ~/.local/share/sounds/lwts/reel-jackpot-synth.oga, and reel-jackpot.oga only if there is none yet (your own file is never overwritten)"""
import sys, os as _os; sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import common
import math, os, random
R = 32000
OUT = os.path.expanduser("~/.local/share/sounds/lwts")
TAU = 2 * math.pi
random.seed(7)

def mix(buf, x, at):
    s = int(at * R)
    if s + len(x) > len(buf): buf.extend([0.0] * (s + len(x) - len(buf)))
    for i, v in enumerate(x): buf[s + i] += v

def click(f):
    """a short mechanical tick: a burst of noise plus a damped ping"""
    n = int(R * 0.03); out = []
    for i in range(n):
        t = i / R
        out.append(0.7 * random.uniform(-1, 1) * math.exp(-700 * t) + 0.6 * math.sin(TAU * f * t) * math.exp(-260 * t))
    return out

def bell(f, dur=0.55, amp=1.0, decay=7.0):
    n = int(R * dur); out = [0.0] * n
    for ratio, a, xd in ((1, 1.0, 0), (2.76, 0.45, 3), (5.4, 0.22, 6), (8.9, 0.1, 9)):
        w = TAU * f * ratio / R
        for i in range(n): out[i] += amp * a * math.sin(w * i) * math.exp(-(decay + xd) * i / R)
    return out

def fade(x, f=0.04):
    n = len(x); k = int(R * f)
    for i in range(min(k, n)): x[n - 1 - i] *= i / k
    return x

def horn(f, dur=0.38, amp=1.0):
    """an airhorn stab: a stack of detuned saw-ish notes with a short pitch dip at the start"""
    n = int(R * dur); out = [0.0] * n
    for ratio, a in ((1.0, 1.0), (1.26, 0.8), (1.5, 0.7)):
        ph = 0.0
        for i in range(n):
            t = i / R; ff = f * ratio * (1 + 0.06 * math.exp(-30 * t)) * (1 + 0.004 * math.sin(TAU * 6 * t)); ph += TAU * ff / R
            v = sum(math.sin(k * ph) / k for k in range(1, 9))
            env = min(1.0, t / 0.012) * (1.0 if t < dur - 0.06 else (dur - t) / 0.06)
            out[i] += amp * a * 0.3 * v * env
    return out

def coin(f):
    n = int(R * 0.22); out = [0.0] * n
    for ratio, a, d in ((1, 1.0, 22), (2.4, 0.6, 30), (4.1, 0.35, 40)):
        w = TAU * f * ratio / R
        for i in range(n): out[i] += a * math.sin(w * i) * math.exp(-d * i / R)
    return out

write = common.write_oga

# jackpot (~4 s): a ringing "ding-ding-ding-ding" that speeds up and climbs, two airhorn stabs, a long coin shower
jp = []
t = 0.0; gap = 0.16; notes = (2093.0, 2637.0, 3136.0, 4186.0)
for k in range(16):
    mix(jp, bell(notes[k % 4] * (1 + 0.015 * (k // 4)), 0.5, 0.75, 9.0), t)
    t += gap; gap = max(0.07, gap * 0.9)
mix(jp, horn(466.0), t + 0.05); mix(jp, horn(466.0, 0.55), t + 0.5)         # the airhorn, twice
for f in (1046.5, 1568.0, 2093.0, 3136.0):
    mix(jp, bell(f, 1.6, 0.5, 3.8), t + 0.5)                                # a big bell chord under the second stab
at = 0.25
while at < 4.2:
    mix(jp, coin(random.choice((1760, 2093, 2349, 2637, 3136, 3520)) * random.uniform(0.97, 1.03)), at)
    at += random.uniform(0.018, 0.055)
print("reel-jackpot-synth", write(os.path.join(OUT, "reel-jackpot-synth.oga"), fade(jp, 0.2), R))
if not os.path.exists(os.path.join(OUT, "reel-jackpot.oga")):   # the shell plays reel-jackpot.oga: a file of your own (a meme) wins, this synth is the default
    import shutil; shutil.copy(os.path.join(OUT, "reel-jackpot-synth.oga"), os.path.join(OUT, "reel-jackpot.oga"))
