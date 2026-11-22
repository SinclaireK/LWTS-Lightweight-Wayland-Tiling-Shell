"""Shared by gen_*.py: write a sound as .oga levelled to one perceived loudness.
Level = max momentary (400 ms, K-weighted) loudness measured by ffmpeg's ebur128 on the clip padded with silence; every sound is
brought to TARGET_M (gain clamped, true peak kept under PEAK), so a tick and a chord feel equally loud."""
import os, re, struct, subprocess, tempfile, wave
TARGET_M = -21.0            # LUFS momentary max - comfortable at the default 60-80 % volume
PEAK = 0.7                  # -3 dBFS: headroom for the lossy encoder overshoot
GAIN_MIN, GAIN_MAX = -24.0, 14.0

def _wav(path, samples, rate):
    with wave.open(path, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))

def momentary_max(samples, rate):
    pad = [0.0] * int(rate * 0.6)
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "m.wav"); _wav(w, samples + pad, rate)
        r = subprocess.run(["ffmpeg", "-nostats", "-i", w, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True)
    vals = [float(v) for v in re.findall(r"\sM:\s*(-?\d+(?:\.\d+)?)", r.stderr) if float(v) > -100]
    return max(vals) if vals else -70.0

def level(samples, rate):
    m = momentary_max(samples, rate)
    gain = max(GAIN_MIN, min(GAIN_MAX, TARGET_M - m)); g = 10 ** (gain / 20)
    peak = max(abs(v) for v in samples) * g
    if peak > PEAK: g *= PEAK / peak
    return [v * g for v in samples], m, gain

def write_oga(path, samples, rate):
    out, m, gain = level(samples, rate)
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "x.wav"); _wav(w, out, rate)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", w, "-c:a", "libvorbis", "-q:a", "3", path], check=True)
    return m, gain
