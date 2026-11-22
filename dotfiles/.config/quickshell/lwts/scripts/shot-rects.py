#!/usr/bin/env python3
"""Where are the windows on a frozen frame? niri 26.04 gives tile sizes and the scrolling layout order but no on-screen
positions for tiled windows. So: the workspace's active window is searched on the picture (a rectangle of its exact tile size
whose edges are painted in the border colours); every other tile follows by layout arithmetic (column widths, row heights, gap).
Several anchor candidates are tried; the one whose implied tiles best match borders on the picture wins.

usage: shot-rects.py <output>=<frame.png> ...   (frames are what grim wrote; scale = frame px / logical px)
stdout: {"<output>": [{"id", "title", "app_id", "focused", "x", "y", "w", "h", "cx", "cy", "cw", "ch"}]} in LOGICAL px relative to the output,
x y w h = the tile (border included, may extend past the output), cx cy cw ch = the window surface. Tiles that are not on the picture are left out.
Border colours and the gap come from ~/.config/niri/lwts.kdl; no border = nothing is found.
"""
import json, os, re, subprocess, sys, traceback
import numpy as np
from PIL import Image

R = 6          # corner allowance: edge runs skip this many px at each end (geometry-corner-radius + antialiasing)
MIN_EDGE = 20  # an edge shorter than this on the picture says nothing
TOPK = 8       # anchor candidates


def niri(*a):
    return json.loads(subprocess.run(["niri", "msg", "-j", *a], capture_output=True, text=True, timeout=5).stdout)


def config():
    cols, gap = [], 6
    try:
        t = open(os.path.expanduser("~/.config/niri/lwts.kdl")).read()
        g = re.search(r"\bgaps\s+(\d+)", t)
        if g:
            gap = int(g.group(1))
        m = re.search(r"\bborder\s*\{([^}]*)\}", t)
        for k in ("active-color", "inactive-color", "urgent-color"):
            c = re.search(k + r'\s+"#([0-9a-fA-F]{6})', m.group(1)) if m else None
            if c:
                h = c.group(1)
                cols.append(tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)))
    except Exception as e:
        print("shot-rects: cannot read ~/.config/niri/lwts.kdl: %s" % e, file=sys.stderr)
    return cols, gap


class Edges:
    def __init__(self, mask):
        self.H, self.W = mask.shape
        self.cx = np.zeros((self.H, self.W + 1), np.int32); np.cumsum(mask, axis=1, out=self.cx[:, 1:])
        self.cy = np.zeros((self.H + 1, self.W), np.int32); np.cumsum(mask, axis=0, out=self.cy[1:, :])

    def peaks(self, tw, th):
        """top candidate (x, y) for a tw x th rectangle, best first, non-overlapping"""
        H, W = self.H, self.W
        if tw < 2 * R + 4 or th < 2 * R + 4 or tw > W or th > H:
            return []
        ln, lv = tw - 2 * R, th - 2 * R
        nx, ny = W - tw + 1, H - th + 1
        A = self.cx[:, R + ln:R + ln + nx] - self.cx[:, R:R + nx]
        B = self.cy[R + lv:R + lv + ny, :] - self.cy[R:R + ny, :]
        score = A[0:ny, :] + A[th - 1:th - 1 + ny, :] + B[:, 0:nx] + B[:, tw - 1:tw - 1 + nx]
        flat = score.ravel()
        n = min(flat.size, 4000)
        idx = np.argpartition(flat, -n)[-n:]
        idx = idx[np.argsort(-flat[idx])]
        out = []
        for i in idx:
            if flat[i] < 0.6 * (2 * ln + 2 * lv):
                break
            y, x = divmod(int(i), nx)
            if all(abs(x - px) > tw // 3 or abs(y - py) > th // 3 for px, py in out):
                out.append((x, y))
                if len(out) >= TOPK:
                    break
        return out

    def present(self, x, y, tw, th):
        """mean share of border-coloured pixels on the edges that are on the picture (None = nothing of it visible)"""
        H, W = self.H, self.W
        parts = []
        for yy in (y, y + th - 1):
            if 0 <= yy < H:
                x0, x1 = max(0, x + R), min(W, x + tw - R)
                if x1 - x0 >= MIN_EDGE:
                    parts.append((self.cx[yy, x1] - self.cx[yy, x0]) / (x1 - x0))
        for xx in (x, x + tw - 1):
            if 0 <= xx < W:
                y0, y1 = max(0, y + R), min(H, y + th - R)
                if y1 - y0 >= MIN_EDGE:
                    parts.append((self.cy[y1, xx] - self.cy[y0, xx]) / (y1 - y0))
        return float(np.mean(parts)) if parts else None


def layout_positions(tiled, anchor, ax, ay, k, gap):
    """tile top-left (px) of every tiled window, from the anchor's position. tiled: windows with pos_in_scrolling_layout."""
    cols = {}
    for w in tiled:
        c, r = w["layout"]["pos_in_scrolling_layout"]
        cols.setdefault(c, {})[r] = w
    order = sorted(cols)
    colw = {c: max(w["layout"]["tile_size"][0] for w in cols[c].values()) * k for c in order}
    ac, ar = anchor["layout"]["pos_in_scrolling_layout"]
    g = gap * k
    left = {}
    left[ac] = ax
    for c in order:                      # to the right
        if c > ac:
            p = max(cc for cc in order if cc < c)
            left[c] = left[p] + colw[p] + g
    for c in reversed(order):            # to the left
        if c < ac:
            n = min(cc for cc in order if cc > c)
            left[c] = left[n] - colw[c] - g
    pos = {}
    for c in order:
        rows = sorted(cols[c])
        ar_ = ar if c == ac else None
        tops = {}
        if ar_ is not None:
            tops[ar_] = ay
            for r in rows:
                if r > ar_:
                    p = max(rr for rr in rows if rr < r)
                    tops[r] = tops[p] + cols[c][p]["layout"]["tile_size"][1] * k + g
            for r in reversed(rows):
                if r < ar_:
                    n = min(rr for rr in rows if rr > r)
                    tops[r] = tops[n] - cols[c][r]["layout"]["tile_size"][1] * k - g
        else:
            # other columns share the vertical placement of the anchor's column only when they have the same height: top-align to the anchor row stack
            y0 = ay - sum(cols[ac][r]["layout"]["tile_size"][1] * k + g for r in sorted(cols[ac]) if r < ar)
            t = y0
            for r in rows:
                tops[r] = t
                t += cols[c][r]["layout"]["tile_size"][1] * k + g
        for r in rows:
            pos[cols[c][r]["id"]] = (round(left[c]), round(tops[r]))
    return pos


def main():
    frames = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    cols, gap = config()
    res = {n: [] for n in frames}
    if not cols:
        print("shot-rects: no border colours in lwts.kdl (layout { border { ... } }): windows cannot be located", file=sys.stderr)
        print(json.dumps(res)); return
    wins, wss, outs = niri("windows"), niri("workspaces"), niri("outputs")
    def scan(name, path):
        lg = outs.get(name, {}).get("logical")
        ws = next((w for w in wss if w["output"] == name and w.get("is_active")), None)
        if not lg or not ws:
            return
        img = np.asarray(Image.open(path).convert("RGB"))
        k = img.shape[1] / lg["width"]
        def mk(cs):
            m = np.zeros(img.shape[:2], bool)
            for c in cs:
                m |= (img == np.array(c, np.uint8)).all(2)
            return m
        E = Edges(mk(cols))                       # any border colour: how well the other tiles match
        EA = Edges(mk(cols[:1]))                  # active colour only: the anchor (an equal-size neighbour cannot pass for it)
        inws = [w for w in wins if w["workspace_id"] == ws["id"]]
        tiled = [w for w in inws if w["layout"].get("pos_in_scrolling_layout")]
        if not tiled:
            return
        anchor = next((w for w in tiled if w["id"] == ws.get("active_window_id")), None) or next((w for w in tiled if w.get("is_focused")), tiled[0])
        sz = lambda w: (round(w["layout"]["tile_size"][0] * k), round(w["layout"]["tile_size"][1] * k))
        best, bestpos = -1.0, None
        # the active window wears the active colour; where it is not seen (an unfocused output may draw it in the inactive one) fall back to every colour
        for (ax, ay) in (EA.peaks(*sz(anchor)) or E.peaks(*sz(anchor))):
            pos = layout_positions(tiled, anchor, ax, ay, k, gap)
            tot = 0.0
            for w in tiled:
                p = E.present(pos[w["id"]][0], pos[w["id"]][1], *sz(w))
                if p is not None:
                    tot += p
            if tot > best:
                best, bestpos = tot, pos
        if not bestpos:
            return
        for w in tiled:
            x, y = bestpos[w["id"]]; tw, th = sz(w)
            p = E.present(x, y, tw, th)
            if p is None or p < 0.7:
                continue
            ox, oy = w["layout"]["window_offset_in_tile"]
            res[name].append({"id": w["id"], "title": w.get("title") or "", "app_id": w.get("app_id") or "", "focused": bool(w.get("is_focused")),
                              "x": x / k, "y": y / k, "w": tw / k, "h": th / k,
                              "cx": x / k + ox, "cy": y / k + oy, "cw": w["layout"]["window_size"][0], "ch": w["layout"]["window_size"][1]})

    for name, path in frames.items():
        try:
            scan(name, path)
        except Exception:
            traceback.print_exc()   # one output failing must not take the others down
    print(json.dumps(res))


main()
