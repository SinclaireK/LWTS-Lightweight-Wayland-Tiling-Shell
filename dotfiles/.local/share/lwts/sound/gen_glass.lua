#!/usr/bin/luajit
-- LWTS Glass: soft, rounded interface sounds in the spirit of macOS / iOS (glassy taps, pops, sonar, bottle, tri-chime) - original
-- synthesis, named by how they sound. Run: luajit gen_glass.lua -> ~/.local/share/sounds/lwts/<name>.oga
package.path = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/?.lua;" .. package.path
local common = require("common")
local R = 32000
local OUT = os.getenv("HOME") .. "/.local/share/sounds/lwts"
local TAU = 2 * math.pi
local floor, sin, exp = math.floor, math.sin, math.exp

local function fin(x, peak, fade)
  peak = peak or 0.8; fade = fade or 0.03
  local n = #x; local m = 1e-9
  for i = 1, n do local a = math.abs(x[i]); if a > m then m = a end end
  local f, a = floor(R * fade), floor(R * 0.002)
  for i = 0, n - 1 do
    local g = peak / m * (i < a and i / a or 1.0) * (i > n - f and (n - i) / f or 1.0)
    x[i + 1] = x[i + 1] * g
  end
  return x
end

-- parts: { {ratio, amp, extra_decay} } -> a struck, ringing tone
local function partials(f, dur, parts, decay)
  local n = floor(R * dur); local out = {}
  for i = 1, n do out[i] = 0.0 end
  for _, p in ipairs(parts) do
    local ratio, amp, xd = p[1], p[2], p[3]
    local w = TAU * f * ratio / R; local d = decay + xd
    for i = 0, n - 1 do out[i + 1] = out[i + 1] + amp * sin(w * i) * exp(-d * i / R) end
  end
  return out
end

local function glide(f0, f1, dur, decay, amp)
  amp = amp or 1.0
  local n = floor(R * dur); local ph = 0.0; local out = {}
  for i = 0, n - 1 do
    local t = i / n; ph = ph + TAU * (f0 + (f1 - f0) * t) / R
    out[i + 1] = amp * sin(ph) * exp(-decay * i / R)
  end
  return out
end

-- low-passed noise minus a slower low-pass = a rough band
local function noise_band(dur, f_lo, f_hi, decay, seed)
  local rnd = common.Random(seed or 3); local n = floor(R * dur)
  local a, b = math.min(0.99, TAU * f_hi / R), math.min(0.99, TAU * f_lo / R)
  local p, q, out = 0.0, 0.0, {}
  for i = 0, n - 1 do
    local v = rnd:uniform(-1, 1); p = p + a * (v - p); q = q + b * (p - q); out[i + 1] = (p - q) * exp(-decay * i / R)
  end
  return out
end

-- parts: { {start_s, samples} }
local function mix(parts)
  local n = 0
  for _, p in ipairs(parts) do n = math.max(n, floor(R * p[1]) + #p[2]) end
  local out = {}
  for i = 1, n do out[i] = 0.0 end
  for _, p in ipairs(parts) do
    local o = floor(R * p[1]); local x = p[2]
    for i = 1, #x do out[o + i] = out[o + i] + x[i] end
  end
  return out
end

local function bell(f, dur, amp, decay)
  dur = dur or 0.5; amp = amp or 1.0; decay = decay or 7.0
  return partials(f, dur, { { 1, 1.0 * amp, 0 }, { 2.0, 0.35 * amp, 4 }, { 3.01, 0.18 * amp, 9 }, { 4.2, 0.08 * amp, 14 } }, decay)
end

local S = {}
local function add(name, samples) S[#S + 1] = { name, samples } end
add("glass-tap",   fin(partials(1760, 0.55, { { 1, 1.0, 0 }, { 2.76, 0.45, 6 }, { 5.4, 0.25, 12 }, { 8.9, 0.1, 20 } }, 6.0)))
add("ping-up",     fin(mix({ { 0, glide(1180, 1320, 0.5, 5.5) }, { 0, glide(2360, 2640, 0.5, 9.0, 0.3) } })))
add("soft-pop",    fin(glide(760, 240, 0.11, 22.0)))
add("tiny-tink",   fin(partials(3100, 0.18, { { 1, 1.0, 0 }, { 2.4, 0.5, 10 }, { 4.1, 0.3, 20 } }, 26.0)))
add("deep-sonar",  fin(mix({ { 0, glide(560, 540, 1.1, 3.2) }, { 0.28, glide(560, 540, 0.9, 4.0, 0.45) }, { 0.52, glide(560, 540, 0.7, 5.0, 0.2) } })))
add("bottle-blow", fin(mix({ { 0, noise_band(0.5, 90, 900, 4.0, 5) }, { 0, glide(470, 470, 0.5, 5.0, 0.7) } }), 0.7))
add("wood-tick",   fin(partials(930, 0.12, { { 1, 1.0, 0 }, { 1.73, 0.5, 10 }, { 2.9, 0.2, 20 } }, 38.0)))
add("tri-chime",   fin(mix({ { 0.00, bell(1318.5, 0.5) }, { 0.11, bell(1568.0, 0.5) }, { 0.22, bell(2093.0, 0.8) } })))
add("hero-rise",   fin(mix({ { 0.00, glide(523.25, 523.25, 0.35, 2.5) }, { 0.13, glide(783.99, 783.99, 0.35, 2.5) }, { 0.26, glide(1046.5, 1046.5, 0.7, 2.2) },
                             { 0.26, glide(1318.5, 1318.5, 0.7, 2.6, 0.5) } })))
add("funk-thud",   fin(mix({ { 0, glide(190, 70, 0.22, 11.0) }, { 0, noise_band(0.02, 200, 3000, 60.0, 8) } })))
add("morse-pair",  fin(mix({ { 0, glide(880, 880, 0.08, 10.0) }, { 0.12, glide(880, 880, 0.12, 10.0) } })))
do   -- purr-low: a tone with a 26 Hz tremolo
  local g, out = glide(110, 110, 0.6, 3.0), {}
  for i = 0, floor(R * 0.6) - 1 do out[i + 1] = g[i + 1] * (0.65 + 0.35 * sin(TAU * 26 * i / R)) end
  add("purr-low", fin(out))
end
add("low-fall",    fin(mix({ { 0, glide(310, 140, 0.55, 5.0) }, { 0, glide(620, 280, 0.55, 8.0, 0.25) } })))
do   -- whoosh-up: noise swelling in
  local x = noise_band(0.28, 400, 6000, 2.0, 11)
  for i = 0, #x - 1 do x[i + 1] = x[i + 1] * (i / (R * 0.28)) ^ 0.7 end
  add("whoosh-up", fin(x, 0.6))
end
add("snap-click",  fin(mix({ { 0, noise_band(0.03, 300, 5000, 90.0, 21) }, { 0.02, glide(1500, 900, 0.06, 40.0, 0.5) } })))
do   -- sparkle-up: four rising bells
  local parts = {}
  for i, f in ipairs({ 1568.0, 1975.5, 2349.3, 3135.9 }) do parts[i] = { (i - 1) * 0.045, bell(f, 0.45, 1.0 - (i - 1) * 0.12, 9.0) } end
  add("sparkle-up", fin(mix(parts)))
end
add("keycap-tap",  fin(mix({ { 0, noise_band(0.025, 500, 4500, 110.0, 31) }, { 0, glide(300, 200, 0.03, 70.0, 0.4) } }), 0.55))
add("glass-pair",  fin(mix({ { 0, partials(1480, 0.45, { { 1, 1.0, 0 }, { 2.76, 0.4, 6 }, { 5.4, 0.2, 12 } }, 7.0) },
                             { 0.1, partials(1976, 0.5, { { 1, 1.0, 0 }, { 2.76, 0.4, 6 }, { 5.4, 0.2, 12 } }, 7.0) } })))

os.execute("mkdir -p '" .. OUT .. "'")
local manifest = {}
for _, s in ipairs(S) do
  common.write_oga(OUT .. "/" .. s[1] .. ".oga", s[2], R)
  manifest[#manifest + 1] = "glass\tphrase\t" .. s[1] .. "\n"
end
local f = assert(io.open(OUT .. "/manifest-glass.tsv", "w")); f:write(table.concat(manifest)); f:close()
print(#S, "sounds ->", OUT)
