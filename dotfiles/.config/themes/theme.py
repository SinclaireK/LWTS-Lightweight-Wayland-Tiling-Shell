#!/usr/bin/env python3
"""Static colour themes for the rice.

Palettes live in ~/.config/themes/palettes/<id>.toml. A palette is turned into the
Material roles the app templates expect, then render.lua (luajit) fills the templates.

  theme list            ids and names, current one marked
  theme menu            pick a theme in rofi (grid with previews)
  theme set <id|name>   apply a theme
  theme current         print current id
  theme wallpaper-set <file>  niri: put a wallpaper on screen (LWTS Wallpaper)
  theme personalize     rofi menu: theme, wallpaper, wallpaper recolour, opacity
  theme display <img>   path to show for a wallpaper (recoloured copy when "recolor" is on)

Settings (~/.config/themes/settings.toml): opacity, recolor = "off" | "soft" | "full", font, mono,
bar_font / bar_opacity (waybar only; empty = same as font / opacity).
Recolouring: lutgen builds a Hald CLUT from the palette once per theme, Pillow applies it.
"""
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

HOME = Path.home()
PALETTES = HOME / ".config/themes/palettes"
SCRIPTS = HOME / ".config/hypr/hyprland/core/scripts"
STATE = HOME / ".local/state/theme/current"
RENDER_JSON = HOME / ".cache/themes/current.json"
APPLY_LOCK = HOME / ".cache/themes/apply.lock"
WALL_WANT = HOME / ".cache/themes/wall.want"     # the newest `wallpaper-set` request
APPLY_WANT = HOME / ".cache/themes/apply.want"   # the newest `apply` request (pid + theme)
SETTINGS = HOME / ".config/themes/settings.toml"
RENDERER = HOME / ".config/themes/render.lua"   # fills the app templates from RENDER_JSON (replaced matugen)
FALLBACK_THEME = "garnet-dark"                 # when the saved theme is gone (the removed "material" one)
LUTGEN = shutil.which("lutgen") or str(HOME / ".cargo/bin/lutgen")
WALLS = HOME / "Pictures/Wallpapers"
RECOLOR = HOME / ".cache/wallpaper-recolor"
CLUTS = HOME / ".cache/themes/clut"
WALL_SETTER = SCRIPTS / "next-wallpaper.sh"
# niri (no hyprpaper): the LWTS Wallpaper service draws the wallpaper and watches these two state files
STATE_DIR = HOME / ".local/state"
WALL_ORIG = STATE_DIR / "lwts-wallpaper"           # the original (not recoloured) wallpaper
WALL_SHOWN = STATE_DIR / "lwts-wallpaper-shown"    # what is on screen: the original or its recoloured copy


def on_hyprland():
    """hyprpaper draws the wallpaper (the old setup). LWTS_NIRI=1 forces the niri path (tests); no hyprpaper process = niri."""
    if os.environ.get("LWTS_NIRI") == "1" or not WALL_SETTER.exists():
        return False
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return True
    return subprocess.run(["pgrep", "-x", "hyprpaper"], capture_output=True).returncode == 0


def set_wallpaper(orig):
    """Put a wallpaper on screen. Hyprland: next-wallpaper.sh (hyprpaper). Anything else (niri): the state files."""
    if on_hyprland():
        subprocess.run(["bash", str(WALL_SETTER), "set", orig],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp_o = WALL_ORIG.with_name(f".{WALL_ORIG.name}.{os.getpid()}")
    tmp_o.write_text(orig)
    os.replace(tmp_o, WALL_ORIG)   # atomic: the shell reads it on every change, never an empty half-write
    shown = display(orig)
    tmp = WALL_SHOWN.with_name(f".{WALL_SHOWN.name}.{os.getpid()}")
    tmp.write_text(shown)
    os.replace(tmp, WALL_SHOWN)
RECOLOR_MODES = ("off", "soft", "full")
WALL_DIMS = {"off": 0.0, "light": 0.25, "strong": 0.45}   # settings.toml wall_dim: how much darker the wallpaper is drawn
# popular rice fonts (installed into ~/.local/share/fonts/rice; terminal ones are Nerd Font builds)
FONTS_UI = ("Space Grotesk", "Adwaita Sans", "Inter", "Geist", "Rubik", "IBM Plex Sans",
            "JetBrainsMono Nerd Font", "Terminess Nerd Font")
FONTS_MONO = ("Adwaita Mono", "JetBrainsMono Nerd Font", "FiraCode Nerd Font", "CaskaydiaCove Nerd Font",
              "Maple Mono NF", "Terminess Nerd Font")
# pixel fonts are only sharp at their native pixel sizes (multiples of their grid)
# Terminess (Terminus) has many native sizes -> sharp and normal-sized (14 px UI, 18 px terminal).
# Departure Mono / Cozette were removed: sharp only at 11/13 px (too small) or double (too big).
PIXEL_FONTS = {"Terminess Nerd Font": (12, 14, 16, 18, 20, 22, 24, 28, 32)}
# sizes (pt for GTK/Qt/rofi/terminal; waybar px = UI px * 14/14.67); 96 dpi -> px = pt * 4/3
BASE_UI_PT, BASE_MONO_PT, BASE_BAR_PX = 11, 14, 14
BORDER_STEPS = ("0.00", "0.10", "0.19", "0.30", "0.45", "0.60", "0.80", "1.00")  # 0.19 = the old fixed 0x30
OPACITY_STEPS = ("0.60", "0.65", "0.70", "0.75", "0.80", "0.85", "0.90", "1.00")

ANSI_NAMES = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c):
    return "#" + "".join(f"{max(0, min(255, round(v))):02x}" for v in c)


def mix(a, b, t):
    """a moved towards b by t (0 = a, 1 = b)."""
    a, b = rgb(a), rgb(b)
    return hexc(tuple(x + (y - x) * t for x, y in zip(a, b)))


def roles(p):
    bg, fg, acc, ter = p["background"], p["foreground"], p["accent"], p["tertiary"]
    dark = p["mode"] == "dark"
    red = p["ansi"][1]
    variant = mix(fg, bg, 0.25)          # dimmer text
    sec = mix(acc, variant, 0.55)        # muted accent, Material-style secondary

    def tonal(c, name):
        return {
            name: c,
            f"on_{name}": bg,
            f"{name}_container": mix(c, bg, 0.7 if dark else 0.78),
            f"on_{name}_container": mix(c, fg, 0.45),
            f"{name}_fixed": mix(c, "#ffffff", 0.55),
            f"{name}_fixed_dim": mix(c, "#ffffff", 0.25),
            f"on_{name}_fixed": mix(c, "#000000", 0.8),
            f"on_{name}_fixed_variant": mix(c, "#000000", 0.55),
        }

    r = {
        "background": bg,
        "surface": bg,
        "surface_dim": mix(bg, "#000000", 0.25) if dark else mix(bg, fg, 0.10),
        "surface_bright": mix(bg, fg, 0.20) if dark else mix(bg, "#ffffff", 0.5),
        "surface_container_lowest": mix(bg, "#000000", 0.35) if dark else mix(bg, "#ffffff", 0.6),
        "surface_container_low": mix(bg, fg, 0.04),
        "surface_container": mix(bg, fg, 0.08),
        "surface_container_high": mix(bg, fg, 0.12),
        "surface_container_highest": mix(bg, fg, 0.17),
        "surface_variant": mix(bg, fg, 0.17),
        "on_background": fg,
        "on_surface": fg,
        "on_surface_variant": variant,
        "outline": mix(fg, bg, 0.5),
        "outline_variant": mix(fg, bg, 0.75),
        "inverse_surface": fg,
        "inverse_on_surface": bg,
        "inverse_primary": mix(acc, bg, 0.45),
        "shadow": "#000000",
        "scrim": "#000000",
        "surface_tint": acc,
        "source_color": acc,
        "error": red,
        "on_error": bg,
        "error_container": mix(red, bg, 0.7 if dark else 0.78),
        "on_error_container": mix(red, fg, 0.45),
    }
    r |= tonal(acc, "primary") | tonal(sec, "secondary") | tonal(ter, "tertiary")
    return r


def load(tid):
    p = tomllib.loads((PALETTES / f"{tid}.toml").read_text())
    for k in ("name", "mode", "background", "foreground", "accent", "tertiary", "selection"):
        if k not in p:
            sys.exit(f"{tid}: missing '{k}'")
    if len(p.get("ansi", [])) != 8 or len(p.get("ansi_bright", [])) != 8:
        sys.exit(f"{tid}: ansi and ansi_bright need 8 colours each")
    return p


def all_themes():
    out = []
    for f in sorted(PALETTES.glob("*.toml")):
        p = tomllib.loads(f.read_text())
        out.append((f.stem, p.get("name", f.stem), p.get("mode", "dark")))
    return out


def menu_label(name, mode, current):
    return f"{name} · {mode}" + (" ✓" if current else "")


def resolve(arg):
    arg = arg.removesuffix(" ✓").split(" · ")[0]
    for tid, name, _ in all_themes():
        if arg in (tid, name):
            return tid
    sys.exit(f"unknown theme: {arg}")


PREVIEWS = HOME / ".cache/themes/previews"
THUMBS = HOME / ".cache/wallpaper-thumbs"


def thumb(image, size=(460, 290), recolor=False):
    """Cover-cropped thumbnail of a wallpaper, cached by mtime (also used by the wallpaper menu).
    recolor=True: the thumbnail as it would look recoloured with the current settings."""
    from PIL import Image, ImageOps
    src = Path(image)
    out = THUMBS / f"{src.stem}-{size[0]}x{size[1]}.png"
    if not out.exists() or out.stat().st_mtime < src.stat().st_mtime:
        THUMBS.mkdir(parents=True, exist_ok=True)
        with Image.open(src) as im:
            ImageOps.fit(im.convert("RGB"), size, Image.LANCZOS).save(out)
    t = recolor_target() if recolor else None
    if not t:
        return out
    tid, mode = t
    rout = THUMBS / f"{tid}-{mode}" / out.name
    if not rout.exists() or rout.stat().st_mtime < max(out.stat().st_mtime, palette_mtime(tid)):
        rout.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(out) as im:
            recolor_image(im, tid, mode).save(rout)
    return rout


# ---- settings -------------------------------------------------------------

def _scale(cfg):
    """Settings -> Fonts -> Size: ui_scale in % (90 / 100 / 110 / 125)."""
    try:
        return max(0.5, min(2.0, float(cfg.get("ui_scale", 100)) / 100))
    except (TypeError, ValueError):
        return 1.0


def _float(v, default):
    try:
        return min(1.0, max(0.0, float(v)))
    except (TypeError, ValueError):
        return default


def settings():
    try:
        cfg = tomllib.loads(SETTINGS.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        cfg = {}
    try:
        op = min(1.0, max(0.0, float(cfg.get("opacity", 0.75))))
    except (TypeError, ValueError):
        op = 0.75
    rc = cfg.get("recolor", "off")
    try:  # waybar's own opacity ("glass"); absent = the shared one
        bar_op = min(1.0, max(0.0, float(cfg["bar_opacity"])))
    except (KeyError, TypeError, ValueError):
        bar_op = None
    wd = str(cfg.get("wall_dim", "off"))
    return {"opacity": op, "recolor": rc if rc in RECOLOR_MODES else "off", "wall_dim": WALL_DIMS.get(wd, 0.0),
            "wallpaper_dots": bool(cfg.get("wallpaper_dots", True)),   # Nothing style: dot grid baked into the shown wallpaper
            "font": str(cfg.get("font") or "Adwaita Sans"), "mono": str(cfg.get("mono") or "Adwaita Mono"),   # "" = Settings → Font → Theme
            "bar_font": str(cfg.get("bar_font", "")), "bar_opacity": bar_op,
            "border_opacity": _float(cfg.get("border_opacity"), 0.19),
            "size": BASE_UI_PT * _scale(cfg), "mono_size": BASE_MONO_PT * _scale(cfg)}


def set_setting(key, toml_value):
    """Replace or append `key = value`, keeping comments in settings.toml."""
    lines = SETTINGS.read_text().splitlines() if SETTINGS.exists() else []
    for i, line in enumerate(lines):
        if re.match(rf"\s*{key}\s*=", line):
            lines[i] = f"{key} = {toml_value}"
            break
    else:
        lines.append(f"{key} = {toml_value}")
    SETTINGS.write_text("\n".join(lines) + "\n")


def current_theme():
    tid = STATE.read_text().strip() if STATE.exists() else ""
    return FALLBACK_THEME if tid == "material" else tid   # the wallpaper-generated theme is gone


# ---- wallpaper recolouring ---------------------------------------------------

_luts = {}


def palette_mtime(tid):
    return max((PALETTES / f"{tid}.toml").stat().st_mtime, Path(__file__).stat().st_mtime)


def recolor_target():
    """(theme id, mode) when wallpapers are recoloured, else None."""
    mode, tid = settings()["recolor"], current_theme()
    if mode == "off" or not tid or not (PALETTES / f"{tid}.toml").exists():
        return None
    return tid, mode


def lut_for(tid):
    if tid in _luts:
        return _luts[tid]
    from PIL import Image, ImageFilter
    out = CLUTS / f"{tid}.png"
    if not out.exists() or out.stat().st_mtime < palette_mtime(tid):
        p = load(tid)
        colours = [p["background"], p["foreground"], p["selection"], p["accent"], p["tertiary"],
                   *p["ansi"], *p["ansi_bright"]]
        CLUTS.mkdir(parents=True, exist_ok=True)
        # level 8 = 64^3 cube, the largest Pillow's Color3DLUT takes
        subprocess.run([LUTGEN, "generate", "-l", "8", "-o", str(out), "--", *colours],
                       check=True, capture_output=True)
    with Image.open(out) as h:
        data = h.convert("RGB").tobytes()
    _luts[tid] = ImageFilter.Color3DLUT(64, [b / 255 for b in data], channels=3)
    return _luts[tid]


def recolor_image(im, tid, mode):
    from PIL import Image
    im = im.convert("RGB")
    out = im.filter(lut_for(tid))
    return Image.blend(im, out, 0.5) if mode == "soft" else out


def add_dots(im, tid):
    """Nothing style: a quiet dot grid baked into the picture (no extra shell surface). The grid is sized for a 2560x1440 screen
    showing the picture 'cover' (awww scales the same way), so the spacing stays ~18 screen px whatever the file size."""
    import numpy as np
    from PIL import Image
    w, h = im.size
    k = max(2560 / w, 1440 / h)            # screen px per picture px
    step, rad = 18 / k, max(0.8, 1.0 / k)   # in picture px
    try:
        fg = load(tid)["foreground"].lstrip("#") if tid else "ffffff"
    except (OSError, SystemExit, tomllib.TOMLDecodeError):
        fg = "ffffff"
    ink = np.array([int(fg[i:i + 2], 16) for i in (0, 2, 4)], np.float32)
    xs = (np.arange(w, dtype=np.float32) + 0.5) % step - step / 2
    ys = (np.arange(h, dtype=np.float32) + 0.5) % step - step / 2
    d = np.sqrt(xs[None, :] ** 2 + ys[:, None] ** 2)
    a = np.clip(rad + 0.5 * max(1.0, 1 / k) - d, 0, 1) * 0.13   # anti-aliased dot edge, 13% like the old overlay
    base = np.asarray(im.convert("RGB"), np.float32)
    out = base * (1 - a[..., None]) + ink * a[..., None]
    return Image.fromarray(out.astype(np.uint8))


def display(image):
    """Path to put on screen for an original wallpaper: itself, or a cached recoloured copy."""
    t = recolor_target()
    dim = settings()["wall_dim"]
    dots = settings()["wallpaper_dots"]
    if (not t and not dim and not dots) or not image or not Path(image).exists():
        return image
    src = Path(image)
    try:
        rel = src.resolve().relative_to(WALLS.resolve()).with_suffix(".jpg")
    except ValueError:
        rel = Path(src.stem + ".jpg")
    tag = (f"{t[0]}-{t[1]}" if t else "plain") + (f"-dim{round(dim * 100)}" if dim else "") + (f"-dots-{current_theme() or 'x'}" if dots else "")   # one cache folder per tint + dim + dots combination
    out = RECOLOR / tag / rel
    newest = max(src.stat().st_mtime, palette_mtime(t[0]) if t else Path(__file__).stat().st_mtime)
    if not out.exists() or out.stat().st_mtime < newest:
        from PIL import Image, ImageEnhance
        out.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(src) as im:
            im = recolor_image(im, t[0], t[1]) if t else im.convert("RGB")
            if dim:
                im = ImageEnhance.Brightness(im).enhance(1.0 - dim)
            if dots:
                im = add_dots(im, current_theme())
            # temp file + rename: the shell may read `out` at any moment, a half-written jpg stays on screen
            tmp = out.with_name(f".{out.name}.{os.getpid()}.tmp")
            im.save(tmp, format="JPEG", quality=94)
            os.replace(tmp, out)
    return str(out)


def refresh_wallpaper():
    """Re-set the wallpaper if what is on screen no longer matches theme/recolour settings."""
    orig = current_wallpaper()
    if not orig:
        return
    shown = ""
    try:
        if on_hyprland():
            for line in (HOME / ".config/hypr/hyprpaper.conf").read_text().splitlines():
                if line.strip().startswith("path"):
                    shown = line.split("=", 1)[1].strip()
                    break
        else:
            shown = WALL_SHOWN.read_text().strip()
    except OSError:
        pass
    if display(orig) != shown:
        set_wallpaper(orig)


def preview(tid):
    """Card: window with fake code in the theme's colours + ANSI strip. Cached."""
    src = PALETTES / f"{tid}.toml"
    out = PREVIEWS / f"{tid}.png"
    if out.exists() and out.stat().st_mtime >= max(src.stat().st_mtime, Path(__file__).stat().st_mtime):
        return out
    p = load(tid)
    return draw_card(p, roles(p), out)


THEME_CARD = 150  # px, square = rofi's icon box; drawn at exactly this size -> shown 1:1, sharp, tiny PNG


def draw_card(p, r, out):
    """Square card: mini window with fake code in the theme's colours, accent button, 16 ANSI swatches."""
    from PIL import Image, ImageDraw
    a, b = p["ansi"], p["ansi_bright"]
    S = THEME_CARD
    im = Image.new("RGB", (S, S), r["surface_dim"])
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, S - 1, S - 1), 12, fill=p["background"], outline=r["outline_variant"])
    d.rounded_rectangle((0, 0, S - 1, 24), 12, fill=r["surface_container_high"])
    d.rectangle((1, 14, S - 2, 24), fill=r["surface_container_high"])
    for i, c in enumerate((a[1], a[3], a[2])):
        d.ellipse((11 + i * 12, 9, 18 + i * 12, 16), fill=c)
    code = [  # (indent, [(colour, width)])
        (0, [(a[5], 22), (a[4], 40), (p["foreground"], 10)]),
        (1, [(a[5], 18), (p["foreground"], 26), (a[2], 46)]),
        (1, [(b[0], 84)]),
        (1, [(a[4], 30), (p["foreground"], 8), (a[3], 24), (a[6], 22)]),
        (2, [(a[1], 26), (a[2], 52)]),
    ]
    y = 34
    for indent, toks in code:
        x = 12 + indent * 12
        for c, w in toks:
            if x + w > S - 12:
                break
            d.rounded_rectangle((x, y, x + w, y + 6), 3, fill=c)
            x += w + 5
        y += 13
    d.rounded_rectangle((S - 52, 99, S - 12, 111), 6, fill=p["accent"])
    sw = (S - 24) / 8
    for row, cols in enumerate((a, b)):
        for i, c in enumerate(cols):
            x0 = 12 + i * sw
            d.rectangle((round(x0), 119 + row * 10, round(x0 + sw) - 1, 127 + row * 10), fill=c)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    im.save(out, optimize=True)
    return out


FONT_PREVIEWS = HOME / ".cache/themes/font-previews"
FONT_CARD = (180, 180)


def font_file(family, style="Regular"):
    r = subprocess.run(["fc-match", "-f", "%{file}", f"{family}:style={style}"], capture_output=True, text=True)
    return r.stdout.strip()


def font_preview(family, mono):
    """Card with a sample of the font, in the current theme's colours. Cached per theme."""
    from PIL import Image, ImageDraw, ImageFont
    cur = current_theme() or "default"
    out = FONT_PREVIEWS / cur / (re.sub(r"[^A-Za-z0-9]+", "-", family) + ".png")
    if out.exists() and out.stat().st_mtime >= Path(__file__).stat().st_mtime:
        return out
    if cur == "default":
        data = json.loads(RENDER_JSON.read_text()) if RENDER_JSON.exists() else None
        bg, fg, acc, dim = (("#1e1e2e", "#cdd6f4", "#89b4fa", "#6c7086") if not data else
                            (data["term"]["background"], data["term"]["foreground"], data["term"]["accent"],
                             data["term"]["bright_black"]))
    else:
        p = load(cur)
        bg, fg, acc, dim = p["background"], p["foreground"], p["accent"], p["ansi_bright"][0]
    path = font_file(family)
    # exactly FONT_CARD px: rofi shows it 1:1 (element-icon size), no scaling -> sharp text
    W, H = FONT_CARD
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    if family in PIXEL_FONTS:
        d.fontmode = "1"  # no antialiasing, like on screen
    big = ImageFont.truetype(path, snap_px(family, 36))
    small = ImageFont.truetype(path, snap_px(family, 13))
    d.text((14, 12), "Aa Яя", font=big, fill=fg)
    d.text((14, 56), "0123", font=big, fill=fg)
    d.text((14, 108), "Швидка бура лисиця", font=small, fill=fg)
    d.text((14, 128), "The quick brown fox", font=small, fill=dim)
    d.text((14, 152), "x != 0 => {}" if mono else "Wi-Fi · 14:52", font=small, fill=acc)
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)
    return out


def menu(cur):
    themes = all_themes()
    rows = []
    for tid, name, mode in themes:
        icon = preview(tid)
        rows.append(escape_markup(name) + ("  ✓" if tid == cur else "") + (f"\0icon\x1f{icon}" if icon else ""))
    sel = next((i for i, t in enumerate(themes) if t[0] == cur), 0)
    # light/dark is visible on the card itself, so the label is just the name (grid size: rofi/grid.rasi)
    i = rofi_pick(rows, "Theme", sel, markup=True, grid=True)
    if i is not None and themes[i][0] != cur:
        apply(themes[i][0])


def current_wallpaper():
    if not on_hyprland():   # niri: the LWTS state file is the only truth
        try:
            t = WALL_ORIG.read_text().strip()
            if t:
                return t
        except OSError:
            pass
    try:
        return (Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / "next-wallpaper.state").read_text().strip()
    except OSError:
        pass
    try:
        for line in (HOME / ".config/hypr/hyprpaper.conf").read_text().splitlines():
            if line.strip().startswith("path"):
                path = Path(line.split("=", 1)[1].strip())
                try:  # recoloured copy (state is lost after reboot) -> the original
                    rel = path.relative_to(RECOLOR)
                    rel = Path(*rel.parts[1:])
                    for f in sorted((WALLS / rel.parent).glob(rel.stem + ".*")):
                        return str(f)
                except ValueError:
                    pass
                return str(path)
    except OSError:
        pass
    return ""


def snap_px(family, px):
    """Nearest native size for a pixel font, the px as is for any other font."""
    native = PIXEL_FONTS.get(family)
    if not native:
        return px
    # largest native size that is not bigger than wanted (rounding up made 18.7 px -> 22 px)
    fitting = [n for n in native if n <= px + 0.5]
    return max(fitting) if fitting else min(native)


def fmt_pt(px):
    return f"{px * 0.75:.2f}".rstrip("0").rstrip(".")


def font_sizes(font, mono, size=BASE_UI_PT, mono_size=BASE_MONO_PT, bar_font=None):
    ui_px = snap_px(font, size * 4 / 3)
    mono_px = snap_px(mono, mono_size * 4 / 3)
    bar_px = snap_px(bar_font or font, round(size * 4 / 3 * BASE_BAR_PX / (BASE_UI_PT * 4 / 3)))
    mono_ui_px = snap_px(mono, size * 4 / 3)  # monospace inside GTK/Qt apps
    return {"size_pt": fmt_pt(ui_px), "mono_pt": fmt_pt(mono_px), "mono_ui_pt": fmt_pt(mono_ui_px),
            "bar_px": f"{bar_px:g}"}


def ui_settings():
    cfg = settings()
    op = cfg["opacity"]
    bar_op = op if cfg["bar_opacity"] is None else cfg["bar_opacity"]
    bar_font = cfg["bar_font"] or cfg["font"]
    return {"opacity": f"{op:.2f}", "alpha_hex": f"{round(op * 255):02x}", "bar_opacity": f"{bar_op:.2f}",
            "border_opacity": f"{cfg['border_opacity']:.2f}",
            "font": cfg["font"], "mono": cfg["mono"], "bar_font": bar_font} \
        | font_sizes(cfg["font"], cfg["mono"], cfg["size"], cfg["mono_size"], bar_font)


def render_data(tid):
    image = current_wallpaper()
    p = load(tid)
    c = roles(p)
    term = {n: v for n, v in zip(ANSI_NAMES, p["ansi"])}
    term |= {f"bright_{n}": v for n, v in zip(ANSI_NAMES, p["ansi_bright"])}
    term |= {"background": p["background"], "foreground": p["foreground"],
             "selection": p["selection"], "accent": p["accent"]}
    return {
        "mode": p["mode"],
        "is_dark_mode": p["mode"] == "dark",
        "image": image,
        "theme": {"id": tid, "name": p["name"]},
        "term": term,
        "term_strip": {k: v.lstrip("#") for k, v in term.items()},
        "ui": ui_settings(),
        "colors": {k: {m: {"color": v} for m in ("default", "dark", "light")} for k, v in c.items()},
    }


def gsettings(key, value):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", key, value],
                   stderr=subprocess.DEVNULL)


def icon_theme(dark):
    """Settings -> Cursor & icons -> Icons: "auto" = Breeze light/dark by the theme, else that theme."""
    try:
        name = tomllib.loads(SETTINGS.read_text()).get("icon_theme", "auto")
    except (OSError, tomllib.TOMLDecodeError):
        name = "auto"
    if name in ("", "auto", "breeze"):
        return "breeze-dark" if dark else "breeze"
    return name


def set_desktop_mode(dark):
    gsettings("color-scheme", "prefer-dark" if dark else "default")
    # re-set via "" so GTK3 apps notice the change even when the name stays the same
    gsettings("gtk-theme", "")
    gsettings("gtk-theme", "adw-gtk3-dark" if dark else "adw-gtk3")
    icon = icon_theme(dark)
    if icon == "Adwaita":   # Adwaita folders are hard-coded blue: a copy recoloured to the accent (folder-recolor.lua)
        try:
            accent = json.loads(RENDER_JSON.read_text())["colors"]["primary"]["default"]["color"]
            subprocess.run([str(HOME / ".config/themes/folder-recolor.lua"), accent], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            icon = "Adwaita-lwts"
        except (OSError, KeyError, ValueError, subprocess.CalledProcessError):
            pass
        gsettings("icon-theme", "")   # re-set via "" so apps notice the new colours under the same name
    gsettings("icon-theme", icon)
    for conf in (HOME / ".config/qt6ct/qt6ct.conf", HOME / ".config/qt5ct/qt5ct.conf"):
        if conf.exists():
            lines = conf.read_text().splitlines()
            pal = f"color_scheme_path={conf.parent}/colors/Adwaita-{'Dark' if dark else 'Light'}.conf"   # stock Adwaita palette, not the theme's
            lines = [f"icon_theme={icon}" if l.startswith("icon_theme=") else pal if l.startswith("color_scheme_path=") else l
                     for l in lines]
            conf.write_text("\n".join(lines) + "\n")


FONTCONFIG = HOME / ".config/fontconfig/fonts.conf"


def write_fontconfig(font, mono):
    """sans-serif / system-ui / monospace -> chosen fonts, for everything that asks fontconfig
    (browsers, Electron apps, Discord, VSCodium...). ~/.config/fontconfig/local.conf is NOT read
    by fontconfig (only fonts.conf and conf.d/), that is why it never worked."""
    def alias(generic, first, *rest):
        fams = "".join(f"\n      <family>{f}</family>" for f in (first, *rest))
        return f"""  <alias binding="strong">
    <family>{generic}</family>
    <prefer>{fams}
    </prefer>
  </alias>
"""
    FONTCONFIG.parent.mkdir(parents=True, exist_ok=True)
    FONTCONFIG.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
                          "<!-- generated by ~/.config/themes/theme.py (Personalization -> Font) -->\n<fontconfig>\n"
                          + alias("sans-serif", font, "Adwaita Sans", "Noto Sans", "Noto Color Emoji")
                          + alias("system-ui", font, "Adwaita Sans", "Noto Sans")
                          + alias("serif", "Noto Serif", "DejaVu Serif")
                          + alias("monospace", mono, "Adwaita Mono", "Noto Sans Mono", "Symbols Nerd Font Mono")
                          + "".join(f"""  <!-- pixel font: hard edges, no smoothing (sharp at its native sizes) -->
  <match target="font">
    <test name="family"><string>{f}</string></test>
    <edit name="antialias" mode="assign"><bool>false</bool></edit>
    <edit name="hinting" mode="assign"><bool>false</bool></edit>
  </match>
""" for f in PIXEL_FONTS)
                          + "</fontconfig>\n")


def set_desktop_fonts(font, mono, size, mono_size):
    write_fontconfig(font, mono)
    gsettings("font-name", f"{font} {size}")
    gsettings("monospace-font-name", f"{mono} {mono_size}")
    for ini in (HOME / ".config/gtk-3.0/settings.ini", HOME / ".config/gtk-4.0/settings.ini"):
        if ini.exists():
            ini.write_text(re.sub(r"(?m)^gtk-font-name=.*$", f"gtk-font-name={font} {size}", ini.read_text()))
    for conf in (HOME / ".config/qt6ct/qt6ct.conf", HOME / ".config/qt5ct/qt5ct.conf"):
        if conf.exists():
            # general="Family,12,..." / fixed="Family,12,..." -> swap only the family
            # field 2 is pointSizeF: fractional sizes keep pixel fonts on their grid
            t = re.sub(r'(?m)^(general=")[^,]*,[^,]*', lambda m: f"{m.group(1)}{font},{size}", conf.read_text())
            t = re.sub(r'(?m)^(fixed=")[^,]*,[^,]*', lambda m: f"{m.group(1)}{mono},{mono_size}", t)
            conf.write_text(t)


MANGO = Path.home() / ".config/MangoHud/MangoHud.conf"
MANGO_FULL = Path.home() / ".local/state/themes/mangohud.full.conf"   # the template render, before the settings.toml choices


def write_mangohud(fresh=False):
    """MangoHud.conf = the rendered full config (template: colours) + mango_* choices from settings.toml."""
    if fresh or not MANGO_FULL.exists():   # fresh: render.lua has just rendered MangoHud.conf
        if not MANGO.exists():
            return
        MANGO_FULL.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MANGO, MANGO_FULL)
    try:
        cfg = tomllib.loads(SETTINGS.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        cfg = {}
    preset = cfg.get("mango_preset", "full")
    keep = {"fps": {"fps"},
            "basic": {"fps", "gpu_stats", "gpu_temp", "cpu_stats", "cpu_temp"}}.get(preset)   # None = everything
    toggles = {"display_server", "wine", "engine_version", "vulkan_driver", "present_mode", "gpu_stats", "gpu_temp",
               "gpu_core_clock", "gpu_mem_clock", "gpu_power", "gpu_voltage", "vram", "cpu_stats", "cpu_temp",
               "cpu_mhz", "ram", "fps", "show_fps_limit"}
    metrics = cfg.get("mango_metrics")   # the checkbox constructor: a list of ids; overrides the preset
    if isinstance(metrics, list):
        keep = {str(m) for m in metrics}
    toggles |= {"fps_metrics"}
    pos = cfg.get("mango_pos", "top-left")
    lim = str(cfg.get("mango_fps_limit", "0"))
    method = cfg.get("mango_limit_method", "")
    binds = {"toggle_hud": cfg.get("mango_bind_hud", ""), "toggle_fps_limit": cfg.get("mango_bind_limit", ""),
             "toggle_preset": cfg.get("mango_bind_preset", ""), "toggle_logging": cfg.get("mango_bind_log", "")}
    binds = {k: v for k, v in binds.items() if isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_+]+", v)}
    out, seen = [], set()
    for line in MANGO_FULL.read_text().splitlines():
        k = line.split("=")[0].strip()
        if keep is not None and k in toggles and k not in keep:
            continue
        if k == "frame_timing" and keep is not None and "frame_timing" not in keep:
            line = "frame_timing=0"
        elif k == "position":
            line = f"position={pos}"
        elif k == "font_size":
            line = f"font_size={int(cfg.get('mango_font', 20))}"
        elif k == "background_alpha":
            line = f"background_alpha={float(cfg.get('mango_alpha', 0.45))}"
        elif k == "fps_limit":
            rest = [x for x in line.split("=", 1)[1].split(",") if x != lim]
            line = "fps_limit=" + ",".join([lim] + rest)
        elif k in binds:
            line = f"{k}={binds[k]}"
        elif k == "fps_limit_method":
            line = f"fps_limit_method={method}" if method in ("early", "late") else line
        seen.add(k)
        out.append(line)
    if method in ("early", "late") and "fps_limit_method" not in seen:
        out.append(f"fps_limit_method={method}")
    out += [f"{k}={v}" for k, v in binds.items() if k not in seen]
    # my presets (Settings -> Gaming -> Overlay): "Name|id,id" strings; cycled in a game by toggle_preset when mango_cycle is on
    mine = [x.split("|", 1) for x in cfg.get("mango_presets", []) if isinstance(x, str) and "|" in x][:8]
    presets_conf = MANGO.parent / "presets.conf"
    if cfg.get("mango_cycle") in (True, "on") and mine:
        flags = sorted(toggles - {"fps_metrics"})
        sections = []
        for i, (_name, ids) in enumerate(mine, 1):
            on = {m for m in ids.split(",") if m}
            sections.append(f"[preset {i}]\n" + "\n".join(f"{k}={1 if k in on else 0}" for k in flags) + f"\nframe_timing={1 if 'frame_timing' in on else 0}\n")
        presets_conf.write_text("\n".join(sections))
        out = [l for l in out if not l.startswith("preset=")]
        out.append("preset=" + ",".join(str(i) for i in range(1, len(mine) + 1)))
    MANGO.write_text("\n".join(out) + "\n")


def apply(tid, notify=True):
    # one apply at a time, the newest pick wins: LWTS previews themes live, so a quick scroll starts
    # several runs; in parallel the slowest one finished last and left half the desktop on an old theme
    token = f"{os.getpid()} {tid}"
    APPLY_WANT.parent.mkdir(parents=True, exist_ok=True)
    APPLY_WANT.write_text(token)
    with open(APPLY_LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if APPLY_WANT.read_text() != token:   # a newer pick is queued behind us: skip this one
            return
        _apply(tid, notify)


def wallpaper_latest(orig):
    # same rule as apply(): previews fire many `wallpaper-set` runs, each renders a copy (slow); unserialized, the slowest
    # finished last and left an OLD wallpaper on screen. One at a time, the newest request wins.
    token = f"{os.getpid()} {orig}"
    WALL_WANT.parent.mkdir(parents=True, exist_ok=True)
    WALL_WANT.write_text(token)
    with open(APPLY_LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if WALL_WANT.read_text() != token:
            return
        set_wallpaper(orig)


def _apply(tid, notify):
    data = render_data(tid)
    RENDER_JSON.parent.mkdir(parents=True, exist_ok=True)
    RENDER_JSON.write_text(json.dumps(data, indent=1))
    subprocess.run([str(RENDERER), str(RENDER_JSON)], stdout=subprocess.DEVNULL)
    set_desktop_mode(data["is_dark_mode"])
    set_desktop_fonts(data["ui"]["font"], data["ui"]["mono"], data["ui"]["size_pt"], data["ui"]["mono_ui_pt"])
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(tid + "\n")
    refresh_wallpaper()
    write_mangohud(fresh=True)
    if notify and not os.environ.get("THEME_QUIET"):   # LWTS previews themes live: no toast per step
        subprocess.run(["notify-send", "-a", "Theme", "Тема", data["theme"]["name"]], stderr=subprocess.DEVNULL)


def escape_markup(text):
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def rofi_pick(rows, prompt, selected=0, theme_str=None, markup=False, grid=False):
    """rofi -dmenu list (or the picture grid); returns the picked index or None (Esc)."""
    cmd = ["rofi", "-dmenu", "-i", "-p", prompt, "-format", "i", "-selected-row", str(selected)]
    if grid:
        cmd += ["-theme", "grid"]
    if theme_str:
        cmd += ["-theme-str", theme_str]
    if markup:
        cmd.append("-markup-rows")
    r = subprocess.run(cmd, input="\n".join(rows), capture_output=True, text=True)
    out = r.stdout.strip()
    return int(out) if r.returncode == 0 and out.isdigit() else None


def restart_waybar():
    """GTK keeps the old font on already drawn labels after a CSS reload -> restart the bar.
    launch.sh only respawns after a crash, so a normal kill ends it; start it again via Hyprland."""
    if subprocess.run(["pgrep", "-x", "waybar"], capture_output=True).returncode != 0:
        return  # no waybar (the Quickshell bar follows the theme/font live)
    subprocess.run(["pkill", "-x", "waybar"])
    subprocess.run(["sleep", "0.3"])
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(["hyprctl", "eval", 'hl.exec_cmd("bash ~/.config/waybar/launch.sh")'], stdout=subprocess.DEVNULL)


def personalize():
    """Main personalization menu; each item opens its own picker, Esc there comes back here."""
    row = 0
    while True:
        cur, cfg = current_theme(), settings()
        name = next((n for t, n, _ in all_themes() if t == cur), cur or "—")
        wall = Path(current_wallpaper()).stem or "—"
        rc = cfg["recolor"]
        items = [("Theme", name), ("Wallpaper", wall), ("Recolor wallpaper", rc), ("Opacity", f"{cfg['opacity']:.2f}"),
                 ("Font", cfg["font"]), ("Terminal font", cfg["mono"]),
                 ("Bar font", cfg["bar_font"] or "same as Font"),
                 ("Bar opacity", "same as Opacity" if cfg["bar_opacity"] is None else f"{cfg['bar_opacity']:.2f}"),
                 ("Border opacity", f"{cfg['border_opacity']:.2f}")]
        rows = [f"{k}<span alpha='55%'>   ·   {escape_markup(v)}</span>" for k, v in items]
        row = rofi_pick(rows, "Personalization", row, f"listview {{ lines: {len(items)}; }}", markup=True)
        if row is None:
            return
        if row == 0:
            menu(cur)
        elif row == 1:
            subprocess.run(["python3", str(HOME / ".config/rofi/wallpaper-menu.py")])
        elif row == 2:
            modes = [f"{m}" + ("  ✓" if m == cfg["recolor"] else "") for m in RECOLOR_MODES]
            i = rofi_pick(modes, "Recolor", RECOLOR_MODES.index(cfg["recolor"]), "listview { lines: 3; }")
            if i is not None and RECOLOR_MODES[i] != cfg["recolor"]:
                set_setting("recolor", f'"{RECOLOR_MODES[i]}"')
                refresh_wallpaper()
        elif row == 3:
            now = f"{cfg['opacity']:.2f}"
            steps = [s + ("  ✓" if s == now else "") for s in OPACITY_STEPS]
            sel = OPACITY_STEPS.index(now) if now in OPACITY_STEPS else 0
            i = rofi_pick(steps, "Opacity", sel, "listview { lines: 8; }")
            if i is not None and OPACITY_STEPS[i] != now:
                set_setting("opacity", OPACITY_STEPS[i])
                apply(cur, notify=False)
                subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL)  # window rules read the opacity
        elif row in (4, 5):
            key, fonts = ("font", FONTS_UI) if row == 4 else ("mono", FONTS_MONO)
            now = cfg[key]
            # grid of sample cards, like the theme menu
            rows_f = [f + ("  ✓" if f == now else "") + f"\0icon\x1f{font_preview(f, row == 5)}" for f in fonts]
            i = rofi_pick(rows_f, "Font" if row == 4 else "Terminal font", fonts.index(now) if now in fonts else 0,
                          f"listview {{ columns: 4; lines: 2; }} element {{ padding: 6px; spacing: 4px; }} "
                          f"element-icon {{ size: {FONT_CARD[0]}px; }} window {{ width: 820px; }}",
                          grid=True)
            if i is not None and fonts[i] != now:
                set_setting(key, f'"{fonts[i]}"')
                apply(cur, notify=False)
                if row == 4:
                    restart_waybar()
        elif row == 6:
            now = cfg["bar_font"]
            # "same as Font" first, then the interface fonts as sample cards
            rows_f = ["same as Font" + ("  ✓" if not now else "")] + \
                     [f + ("  ✓" if f == now else "") + f"\0icon\x1f{font_preview(f, False)}" for f in FONTS_UI]
            i = rofi_pick(rows_f, "Bar font", FONTS_UI.index(now) + 1 if now in FONTS_UI else 0,
                          f"listview {{ columns: 4; lines: 2; }} element {{ padding: 6px; spacing: 4px; }} "
                          f"element-icon {{ size: {FONT_CARD[0]}px; }} window {{ width: 820px; }}",
                          grid=True)
            if i is not None:
                pick = "" if i == 0 else FONTS_UI[i - 1]
                if pick != now:
                    set_setting("bar_font", f'"{pick}"')
                    apply(cur, notify=False)
                    restart_waybar()
        elif row == 7:
            # glass bar: its own opacity (waybar layer is blurred by Hyprland, rules.lua "waybar-blur")
            now = None if cfg["bar_opacity"] is None else f"{cfg['bar_opacity']:.2f}"
            opts = [None, *OPACITY_STEPS]
            labels = ["same as Opacity"] + [f"{st}" + ("  ·  glass" if st == "0.60" else "") for st in OPACITY_STEPS]
            labels = [lb + ("  ✓" if o == now else "") for lb, o in zip(labels, opts)]
            i = rofi_pick(labels, "Bar opacity", opts.index(now) if now in opts else 0, "listview { lines: 9; }")
            if i is not None and opts[i] != now:
                set_setting("bar_opacity", f"{opts[i]}" if opts[i] else '""')
                apply(cur, notify=False)
        elif row == 8:
            # window borders (active; inactive = a third), read by core/general.lua from generated-colors.lua
            now = f"{cfg['border_opacity']:.2f}"
            steps = [st + ("  ✓" if st == now else "") for st in BORDER_STEPS]
            i = rofi_pick(steps, "Border opacity", BORDER_STEPS.index(now) if now in BORDER_STEPS else 2,
                          "listview { lines: 8; }")
            if i is not None and BORDER_STEPS[i] != now:
                set_setting("border_opacity", BORDER_STEPS[i])
                apply(cur, notify=False)
                subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    cur = current_theme()
    if cmd not in ("set", "json", "list", "current") and STATE.exists() and STATE.read_text().strip() == "material":
        apply(FALLBACK_THEME, notify=False)   # saved theme was the removed "material": re-render a preset
    if cmd == "list":
        for tid, name, mode in all_themes():
            print(f"{'*' if tid == cur else ' '} {tid:24} {name} ({mode})")
    elif cmd == "menu":
        menu(cur)
    elif cmd == "current":
        print(cur)
    elif cmd == "personalize":
        personalize()
    elif cmd == "display" and len(sys.argv) > 2:
        print(display(sys.argv[2]))
    elif cmd == "wallpaper-set" and len(sys.argv) > 2:
        # niri: LWTS Wallpaper.set() -> here. Puts the wallpaper on screen (state files), then the theme follows it
        wallpaper_latest(sys.argv[2])
    elif cmd == "mangohud":
        write_mangohud()  # after changing mango_* in settings.toml
    elif cmd == "set" and len(sys.argv) > 2:
        apply(resolve(" ".join(sys.argv[2:])))
    elif cmd == "json" and len(sys.argv) > 2:
        print(json.dumps(render_data(resolve(" ".join(sys.argv[2:]))), indent=1))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
