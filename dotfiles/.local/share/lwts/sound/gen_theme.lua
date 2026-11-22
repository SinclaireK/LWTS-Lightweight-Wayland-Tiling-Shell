#!/usr/bin/luajit
-- LWTS Retro: minimalist 8-bit sounds, named by how they sound.
-- Run: luajit gen_theme.lua -> ~/.local/share/sounds/lwts/<name>.oga. Pure tones, no samples, no licences.
package.path = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/?.lua;" .. package.path
local common = require("common")
local R = 44100
local OUT = os.getenv("HOME") .. "/.local/share/sounds/lwts"
local floor, sin, pi = math.floor, math.sin, math.pi
local N = { C4 = 261.63, G4 = 392.0, A4 = 440.0, E4 = 329.63, C5 = 523.25, D5 = 587.33, E5 = 659.25, F5 = 698.46, G5 = 783.99, A5 = 880.0, B5 = 987.77,
            C6 = 1046.5, D6 = 1174.7, E6 = 1318.5, G6 = 1568.0, A6 = 1760.0 }

-- notes: { {freq, ms, glide_to|nil} }; 4 ms attack, curved decay, `gap` ms of silence between notes
local function tone(notes, kind, vol, duty, gap)
  kind = kind or "square"; vol = vol or 0.28; duty = duty or 0.5; gap = gap or 12
  local out = {}
  for _, note in ipairs(notes) do
    local f, ms, g = note[1], note[2], note[3]
    local n = floor(R * ms / 1000); local ph = 0.0
    for i = 0, n - 1 do
      local t = i / n; local fr = f + (g and (g - f) * t or 0); ph = ph + fr / R; local p = ph % 1.0
      local v
      if kind == "square" then v = p < duty and 1.0 or -1.0
      elseif kind == "pulse" then v = p < 0.25 and 1.0 or -1.0
      elseif kind == "tri" then v = 4 * math.abs(p - 0.5) - 1
      else v = sin(2 * pi * p) end
      out[#out + 1] = v * math.min(1.0, i / (R * 0.004)) * (1 - t) ^ 1.6 * vol
    end
    for _ = 1, floor(R * gap / 1000) do out[#out + 1] = 0.0 end
  end
  return out
end

local function click(ms, vol)   -- noise burst for shutter / capture
  ms = ms or 40; vol = vol or 0.35
  local rnd = common.Random(7); local n = floor(R * ms / 1000); local out = {}
  for i = 0, n - 1 do out[i + 1] = rnd:uniform(-1, 1) * (1 - i / n) ^ 3 * vol end
  return out
end

local function seq(...)
  local o = {}
  for _, p in ipairs({ ... }) do for i = 1, #p do o[#o + 1] = p[i] end end
  return o
end

local n = N
local B2 = n.B5 * 2
-- sounds are named by how they sound; which event plays which is decided in Sounds.qml (defaults) and Settings -> System sounds
local SOUNDS = {
  { "blip-rise",      tone({ { n.E6, 55 }, { n.A6, 85 } }, "pulse", 0.22) },
  { "blip-fall",      tone({ { n.A6, 55 }, { n.E6, 70 } }, "pulse", 0.2) },
  { "triple-rise",    tone({ { n.G5, 70 }, { n.C6, 70 }, { n.E6, 110 } }, "pulse", 0.22) },
  { "ping",           tone({ { B2, 150 } }, "sine", 0.4) },
  { "double-ping",    tone({ { B2, 90 }, { B2, 140 } }, "sine", 0.4, nil, 60) },
  { "quad-ping",      tone({ { B2, 90 }, { B2, 90 }, { B2, 90 }, { B2, 90 } }, "sine", 0.4, nil, 70) },
  { "chirp-up",       tone({ { n.C6, 100, n.G6 } }, "tri", 0.45) },
  { "sweep-down",     tone({ { n.G6, 140, n.C5 } }, "tri", 0.4) },
  { "alarm-two-tone", tone({ { n.A5, 90 }, { n.E5, 90 }, { n.A5, 90 }, { n.E5, 140 } }, "pulse", 0.22) },
  { "buzz-low",       tone({ { n.C4 * 2, 90 }, { n.C4 * 2, 90 }, { n.C4, 200 } }, "pulse", 0.28) },
  { "question-rise",  tone({ { n.E5, 80 }, { n.B5, 140 } }, "tri", 0.45) },
  { "arp-up",         tone({ { n.C6, 45 }, { n.E6, 45 }, { n.G6, 80 } }, "pulse", 0.22) },
  { "arp-down",       tone({ { n.G6, 45 }, { n.E6, 45 }, { n.C6, 80 } }, "pulse", 0.22) },
  { "bright-run",     tone({ { n.C6, 60 }, { n.E6, 60 }, { n.G6, 130 } }, "square", 0.2) },
  { "soft-fall",      tone({ { n.E5, 90 }, { n.C5, 160 } }, "pulse", 0.28) },
  { "coin-up",        tone({ { n.B5, 55 }, { n.E6, 160 } }, "square", 0.2) },
  { "coin-down",      tone({ { n.E6, 55 }, { n.B5, 160 } }, "square", 0.2) },
  { "stairs-up",      tone({ { n.C5, 60 }, { n.G5, 60 }, { n.C6, 110 } }, "tri", 0.45) },
  { "stairs-down",    tone({ { n.C6, 60 }, { n.G5, 60 }, { n.C5, 140 } }, "tri", 0.45) },
  { "tick",           tone({ { n.A5, 35 } }, "sine", 0.35) },
  { "shutter",        seq(click(35), tone({ { n.E6, 60 } }, "tri", 0.3)) },
  { "melody-up",      tone({ { n.C5, 80 }, { n.E5, 80 }, { n.G5, 80 }, { n.C6, 200 } }, "tri", 0.45) },
  { "melody-down",    tone({ { n.C6, 80 }, { n.G5, 80 }, { n.E5, 80 }, { n.C5, 220 } }, "tri", 0.45) },
  { "test-tone",      tone({ { 440.0, 500 } }, "sine", 0.4) },
}

os.execute("mkdir -p '" .. OUT .. "'")
local manifest = {}
for _, s in ipairs(SOUNDS) do
  common.write_oga(OUT .. "/" .. s[1] .. ".oga", s[2], R)
  manifest[#manifest + 1] = "retro\tphrase\t" .. s[1] .. "\n"
end
local f = assert(io.open(OUT .. "/manifest-retro.tsv", "w")); f:write(table.concat(manifest)); f:close()
print(#SOUNDS, "sounds ->", OUT)
