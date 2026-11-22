#!/usr/bin/env python3
"""Overview backdrop for niri, drawn by a second awww-daemon (namespace "backdrop") instead of a shell window.
Same picture the shell used to paint: four soft radial blobs in theme colours placed from a hash of the wallpaper path,
darkened a little in dark themes. Rendered small (1/3) and stretched by awww: it is a blur anyway.
usage: backdrop.py <wallpaper-path> <surface> <c1,c2,c3,c4> <dark 0|1>     |     backdrop.py --off <surface>"""
import math, re, subprocess, sys, time
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path.home() / ".cache/lwts"


def awww(*a):
    for _ in range(10):
        if subprocess.run(["awww", *a, "-n", "backdrop"], capture_output=True).returncode == 0:
            return True
        time.sleep(0.5)
    return False


def hexrgb(h):
    h = h.lstrip("#")[-6:]
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def outputs():
    q = subprocess.run(["awww", "query", "-n", "backdrop"], capture_output=True, text=True).stdout
    return [(m[0], int(m[1]), int(m[2])) for m in re.findall(r"(\S+): (\d+)x(\d+)", q)]


def seed_of(t):   # same as the old QML hash()
    h = 7
    for ch in t:
        h = (h * 31 + ord(ch)) % 1000003
    return h


def render(w, h, seed, surface, cols, dark):
    rnd = lambda i: (math.fmod(math.sin(seed * 12.9898 + i * 78.233) * 43758.5453, 1) + 1) % 1
    img = np.empty((h, w, 3)) ; img[:] = hexrgb(surface)
    yy, xx = np.mgrid[0:h, 0:w]
    for i, c in enumerate(cols):
        r = max(w, h) * (0.45 + rnd(i * 4 + 2) * 0.3)
        cx, cy = rnd(i * 4) * w, rnd(i * 4 + 1) * h
        a = (0.34 * np.clip(1 - np.hypot(xx - cx, yy - cy) / r, 0, 1))[..., None]
        img = img * (1 - a) + hexrgb(c) * a
    if dark:
        img *= 0.7
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype("uint8"))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if sys.argv[1] == "--off":
        awww("clear", sys.argv[2].lstrip("#")[-6:]); return
    path, surface, cols, dark = sys.argv[1], sys.argv[2], sys.argv[3].split(","), sys.argv[4] == "1"
    seed = seed_of(path)
    for _ in range(10):
        outs = outputs()
        if outs: break
        time.sleep(0.5)
    for name, w, h in outs:
        f = OUT / f"backdrop-{name}.png"
        render(max(2, w // 3), max(2, h // 3), seed, surface, cols, dark).save(f)
        awww("img", str(f), "-o", name, "--resize", "stretch", "--transition-type", "fade", "--transition-duration", "0.6")


main()
