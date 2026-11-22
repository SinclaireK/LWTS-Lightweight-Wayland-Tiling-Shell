#!/usr/bin/luajit
-- LWTS Keys: piano / electric piano / synth pluck notes (C3..C6, chromatic) and short phrases built from them - the default LWTS sounds.
-- Run: luajit gen_keys.lua -> ~/.local/share/sounds/lwts/{piano,ep,pluck}-<note>.oga and the phrase files. Pure synthesis, no samples.
package.path = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/?.lua;" .. package.path
local common = require("common")
local R = 32000
local OUT = os.getenv("HOME") .. "/.local/share/sounds/lwts"
local NAMES = { "c", "cs", "d", "ds", "e", "f", "fs", "g", "gs", "a", "as", "b" }
local floor, sin, exp, sqrt, pi = math.floor, math.sin, math.exp, math.sqrt, math.pi

local function freq(name, octave)
  for i, n in ipairs(NAMES) do
    if n == name then return 440.0 * 2 ^ (((i - 1) + 12 * (octave - 4) - 9) / 12) end
  end
end

local function zeros(n) local t = {}; for i = 1, n do t[i] = 0.0 end; return t end

local function finish(x, peak)
  local n = #x; local m = 1e-9
  for i = 1, n do local a = math.abs(x[i]); if a > m then m = a end end
  local fade = floor(R * 0.05)
  for i = 0, n - 1 do
    local g = peak / m
    if i < floor(R * 0.002) then g = g * i / (R * 0.002) end
    if i > n - fade then g = g * (n - i) / fade end
    x[i + 1] = x[i + 1] * g
  end
  return x
end

local function piano(f, dur, vel)
  vel = vel or 1.0
  local n = floor(R * dur); local out = zeros(n)
  local B = 0.00012 * (f / 261.63) ^ 1.5                       -- string stiffness: slightly sharp upper partials
  for k = 1, 10 do
    local fk = k * f * sqrt(1 + B * k * k)
    if fk > 9000 then break end
    local a = vel / (k ^ 1.15)
    local rate = 1.6 + 1.1 * k + 0.0016 * f                    -- higher partials die faster
    local w1, w2 = 2 * pi * fk / R, 2 * pi * (fk + 0.35) / R   -- two slightly detuned strings
    for i = 0, n - 1 do
      out[i + 1] = out[i + 1] + a * 0.5 * (sin(w1 * i) + sin(w2 * i)) * exp(-rate * i / R)
    end
  end
  local rnd = common.Random(floor(f)); local hn = floor(R * 0.012)   -- hammer: a short soft noise
  local prev = 0.0
  for i = 0, math.min(hn, n) - 1 do
    prev = prev + 0.25 * (rnd:uniform(-1, 1) - prev); out[i + 1] = out[i + 1] + prev * 0.35 * vel * (1 - i / hn) ^ 2
  end
  return finish(out, 0.9)
end

local function epiano(f, dur, vel)   -- FM tine: sine carrier, decaying modulation, faint bell partial
  vel = vel or 1.0
  local n = floor(R * dur); local out = {}
  for i = 0, n - 1 do
    local t = i / R
    local idx = 1.8 * exp(-t * 7) + 0.25
    local v = sin(2 * pi * f * t + idx * sin(2 * pi * f * t)) + 0.12 * exp(-t * 14) * sin(2 * pi * f * 14 * t)
    out[i + 1] = v * vel * exp(-t * 3.0)
  end
  return finish(out, 0.55)
end

local function pluck(f, dur, vel)    -- synth pluck: saw partials with a closing "filter"
  vel = vel or 1.0
  local n = floor(R * dur); local out = zeros(n)
  for k = 1, 21 do
    local fk = k * f
    if fk > 9000 then break end
    local w = 2 * pi * fk / R; local rate = 2.2 + 1.5 * k
    for i = 0, n - 1 do out[i + 1] = out[i + 1] + vel / k * sin(w * i) * exp(-rate * i / R) end
  end
  return finish(out, 0.55)
end

-- parts: { {start_s, samples} } -> one buffer (clipped softly)
local function mix(parts)
  local n = 0
  for _, p in ipairs(parts) do n = math.max(n, floor(R * p[1]) + #p[2]) end
  local out = zeros(n)
  for _, p in ipairs(parts) do
    local o = floor(R * p[1]); local x = p[2]
    for i = 1, #x do out[o + i] = out[o + i] + x[i] end
  end
  local m = 1.0
  for i = 1, n do local a = math.abs(out[i]); if a > m then m = a end end
  for i = 1, n do out[i] = out[i] / m * 0.9 end
  return out
end

local function P(nm, o, d, v) return piano(freq(nm, o), d or 0.7, v or 1.0) end

os.execute("mkdir -p '" .. OUT .. "'")
local manifest = {}
-- 1. the note library, 3 timbres
for _, oct in ipairs({ 3, 4, 5, 6 }) do
  for _, nm in ipairs(NAMES) do
    if not (oct == 6 and nm ~= "c") then
      local f = freq(nm, oct)
      for _, k in ipairs({ { "piano", piano, 1.3 }, { "ep", epiano, 1.1 }, { "pluck", pluck, 0.7 } }) do
        common.write_oga(OUT .. "/" .. k[1] .. "-" .. nm .. oct .. ".oga", k[2](f, k[3]), R)
        manifest[#manifest + 1] = "keys\tnote\t" .. k[1] .. "-" .. nm .. oct .. "\n"
      end
    end
  end
end
-- 2. phrases - the LWTS defaults
local PH = {
  { "piano-rise",        mix({ { 0.0, P("e", 5, 0.5, 0.8) }, { 0.09, P("b", 5, 0.8, 0.9) } }) },                                 -- notification
  { "piano-low-alert",   mix({ { 0.0, P("a", 3, 0.8) }, { 0.16, P("a", 3, 0.8) }, { 0.32, P("e", 3, 1.0) } }) },                 -- urgent
  { "piano-fifth-up",    mix({ { 0.0, P("c", 5, 0.7) }, { 0.07, P("g", 5, 0.9) } }) },                                           -- charger in
  { "piano-fifth-down",  mix({ { 0.0, P("g", 5, 0.7) }, { 0.07, P("c", 5, 0.9) } }) },                                           -- charger out
  { "piano-tick",        P("c", 6, 0.18, 0.6) },                                                                                 -- volume
  { "pluck-snap",        mix({ { 0.0, pluck(freq("c", 6), 0.25, 0.9) }, { 0.03, pluck(freq("g", 5), 0.3, 0.6) } }) },            -- screenshot
}
do
  local parts = {}
  for i, nr in ipairs({ { "c", 5 }, { "e", 5 }, { "g", 5 }, { "c", 6 } }) do parts[i] = { (i - 1) * 0.11, P(nr[1], nr[2], 1.0 - (i - 1) * 0.1) } end
  PH[#PH + 1] = { "piano-arpeggio-up", mix(parts) }
end
PH[#PH + 1] = { "piano-chord",  mix({ { 0.0, P("c", 4, 1.2, 0.9) }, { 0.0, P("e", 4, 1.2, 0.8) }, { 0.0, P("g", 4, 1.2, 0.8) }, { 0.0, P("c", 5, 1.2, 0.7) } }) }
PH[#PH + 1] = { "ep-bell-pair", mix({ { 0.0, epiano(freq("g", 5), 0.8) }, { 0.12, epiano(freq("c", 6), 0.9) } }) }
PH[#PH + 1] = { "ep-chord",     mix({ { 0.0, epiano(freq("c", 4), 1.2) }, { 0.0, epiano(freq("e", 4), 1.2) }, { 0.0, epiano(freq("a", 4), 1.2) } }) }
for _, p in ipairs(PH) do
  common.write_oga(OUT .. "/" .. p[1] .. ".oga", p[2], R)
  manifest[#manifest + 1] = "keys\tphrase\t" .. p[1] .. "\n"
end
local f = assert(io.open(OUT .. "/manifest-keys.tsv", "w")); f:write(table.concat(manifest)); f:close()
print(#PH, "phrases ->", OUT)
