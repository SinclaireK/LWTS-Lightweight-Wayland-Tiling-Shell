#!/usr/bin/env python3
"""Day/night schedule for the night light and the light/dark theme.

  daynight.py apply     put both into the state the schedule wants now, plan the next switch
  daynight.py status    what is scheduled and when

Settings (~/.config/themes/settings.toml, edited from the launcher: Tab -> ⚙):
  nightlight_mode / darkmode_mode = "manual" | "sun" | "time"
  nightlight_night / nightlight_day, darkmode_night / darkmode_day = "HH:MM"   ("time" mode)
  nightlight_temp = 4000, day_theme / night_theme = palette ids, latitude / longitude ("sun" mode)

No polling: after each run a transient systemd user timer (rice-daynight) is set for the next
switch. Realtime timers that elapsed during suspend fire right after resume.
Manual toggles hold until the next scheduled switch.
"""
import datetime as dt
import math
import os
import sys
import tomllib
from pathlib import Path

HOME = Path.home()
SETTINGS = HOME / ".config/themes/settings.toml"
PALETTES = HOME / ".config/themes/palettes"
STATE = HOME / ".local/state/theme/current"
NIGHTLIGHT = HOME / ".config/waybar/scripts/nightlight.sh"
UNIT = "rice-daynight"
MODES = ("manual", "sun", "time")
DEFAULTS = {
    "nightlight_mode": "manual", "nightlight_night": "21:00", "nightlight_day": "07:00", "nightlight_temp": 4000,
    "darkmode_mode": "manual", "darkmode_night": "20:00", "darkmode_day": "07:00",
    "day_theme": "garnet-light", "night_theme": "garnet-dark",
    # optional per period ("" = keep): wallpaper file name in ~/Pictures/Wallpapers, recolor off|soft|full
    "day_wallpaper": "", "night_wallpaper": "", "day_recolor": "", "night_recolor": "",
    "latitude": 49.99, "longitude": 36.23,  # Kharkiv
}


def cfg():
    try:
        raw = tomllib.loads(SETTINGS.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        raw = {}
    c = DEFAULTS | {k: raw[k] for k in DEFAULTS if k in raw}
    for k in ("nightlight_mode", "darkmode_mode"):
        if c[k] not in MODES:
            c[k] = "manual"
    return c


def sun_times(day, lat, lon):
    """Local sunrise and sunset (NOAA approximation, ~1 min). None near polar day/night."""
    g = 2 * math.pi / 365 * (day.timetuple().tm_yday - 1)
    eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                       - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
            + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    la = math.radians(lat)
    x = math.cos(math.radians(90.833)) / (math.cos(la) * math.cos(decl)) - math.tan(la) * math.tan(decl)
    if not -1 <= x <= 1:
        return None
    ha = math.degrees(math.acos(x))
    midnight = dt.datetime.combine(day, dt.time(), dt.timezone.utc)
    rise = midnight + dt.timedelta(minutes=720 - 4 * (lon + ha) - eqtime)
    sset = midnight + dt.timedelta(minutes=720 - 4 * (lon - ha) - eqtime)
    return rise.astimezone(), sset.astimezone()


def hm(day, text):
    h, m = (int(x) for x in text.split(":"))
    return dt.datetime.combine(day, dt.time(h, m)).astimezone()


def bounds(c, what, day):
    """(day starts, night starts) for `what` = "nightlight" | "darkmode" on a date."""
    if c[f"{what}_mode"] == "sun":
        st = sun_times(day, c["latitude"], c["longitude"])
        if st:
            return st
    return hm(day, c[f"{what}_day"]), hm(day, c[f"{what}_night"])


def schedule(c, what, now):
    """(is night now, next switch time) or None for manual mode."""
    if c[f"{what}_mode"] == "manual":
        return None
    today = now.date()
    d0, n0 = bounds(c, what, today)
    night = not (d0 <= now < n0) if d0 < n0 else (n0 <= now < d0)
    times = [t for t in (d0, n0, *bounds(c, what, today + dt.timedelta(days=1))) if t > now]
    return night, min(times)


def plan(when):
    import subprocess
    subprocess.run(["systemctl", "--user", "stop", f"{UNIT}.timer"], capture_output=True)
    if when is None:
        return
    env = [f"--setenv={k}={os.environ[k]}" for k in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY")
           if k in os.environ]
    subprocess.run(["systemd-run", "--user", "--quiet", f"--unit={UNIT}", "--collect",
                    f"--on-calendar={when.strftime('%Y-%m-%d %H:%M:%S')}", "--timer-property=AccuracySec=1s",
                    *env, "python3", str(Path(__file__).resolve()), "apply"], capture_output=True)


def apply():
    import subprocess
    c, now = cfg(), dt.datetime.now().astimezone()
    nexts = []
    nl = schedule(c, "nightlight", now)
    if nl:
        want = "on" if nl[0] else "off"
        if subprocess.run(["bash", str(NIGHTLIGHT), "status"], capture_output=True, text=True).stdout.strip() != want:
            subprocess.run(["bash", str(NIGHTLIGHT), "set", want])
        nexts.append(nl[1])
    dm = schedule(c, "darkmode", now)
    if dm:
        target = c["night_theme"] if dm[0] else c["day_theme"]
        cur = STATE.read_text().strip() if STATE.exists() else ""
        # game mode: don't switch the theme mid-game; game-mode.lua re-runs this at the end
        if (Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "game-mode").exists():
            target = cur
        period = "night" if dm[0] else "day"
        period_file = HOME / ".local/state/daynight-period"
        in_game = (Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "game-mode").exists()
        # wallpaper / recolour of the period: only when the period changes, so a wallpaper picked by
        # hand during the day is not reset on every settings change
        new_period = not in_game and (period_file.read_text().strip() if period_file.exists() else "") != period
        rc = c[f"{period}_recolor"] if new_period else ""
        if rc in ("off", "soft", "full"):
            sys.path.insert(0, str(Path(__file__).parent))
            import theme
            theme.set_setting("recolor", f'"{rc}"')
        if (PALETTES / f"{target}.toml").exists() and (cur != target or rc):
            sys.path.insert(0, str(Path(__file__).parent))
            import theme  # heavy (Pillow), only when something really changes
            theme.apply(target, notify=False)
        wall = HOME / "Pictures/Wallpapers" / c[f"{period}_wallpaper"] if c[f"{period}_wallpaper"] else None
        if new_period and wall and wall.exists():
            subprocess.Popen(["bash", str(HOME / ".config/hypr/hyprland/core/scripts/next-wallpaper.sh"), "set", str(wall)],
                             start_new_session=True)
        if new_period:
            period_file.write_text(period + "\n")
        nexts.append(dm[1])
    plan(min(nexts) if nexts else None)


def status():
    c, now = cfg(), dt.datetime.now().astimezone()
    st = sun_times(now.date(), c["latitude"], c["longitude"])
    if st:
        print(f"sun today: rise {st[0]:%H:%M}, set {st[1]:%H:%M}")
    for what in ("nightlight", "darkmode"):
        s = schedule(c, what, now)
        print(f"{what}: {c[what + '_mode']}" + (f", {'night' if s[0] else 'day'} now, next switch {s[1]:%a %H:%M}"
                                               if s else ""))


if __name__ == "__main__":
    {"apply": apply, "status": status}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
