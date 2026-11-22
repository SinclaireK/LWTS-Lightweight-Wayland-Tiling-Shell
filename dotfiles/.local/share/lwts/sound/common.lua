-- Shared by gen_*.lua: write a sound as .oga levelled to one perceived loudness.
-- Level = max momentary (400 ms, K-weighted) loudness measured by ffmpeg's ebur128 on the clip padded with silence; every sound is
-- brought to TARGET_M (gain clamped, true peak kept under PEAK), so a tick and a chord feel equally loud.
local ffi = require("ffi")
local bit = require("bit")
local M = {}
local TARGET_M = -21.0            -- LUFS momentary max - comfortable at the default 60-80 % volume
local PEAK = 0.7                  -- -3 dBFS: headroom for the lossy encoder overshoot
local GAIN_MIN, GAIN_MAX = -24.0, 14.0
local TWO32 = 4294967296

-- Python's random.Random(int) (MT19937, init_by_array, 53-bit random()), so the noise is the same as in the old gen_*.py.
-- 32-bit words are kept as non-negative doubles; a 32x32 multiply is split in 16-bit halves to stay exact below 2^53.
local function u32(x) return x % TWO32 end
local function mul32(a, b) return (((a - a % 65536) / 65536 * b % TWO32) * 65536 + (a % 65536) * b) % TWO32 end
local Random = {}
Random.__index = Random
function M.Random(seed)
  local mt = {}
  mt[0] = 19650218
  for i = 1, 623 do mt[i] = u32(mul32(1812433253, bit.bxor(mt[i - 1], bit.rshift(mt[i - 1], 30)) % TWO32) + i) end
  local key, i, j = { math.abs(seed) % TWO32 }, 1, 0
  for _ = 1, 624 do
    mt[i] = u32(bit.bxor(mt[i], mul32(bit.bxor(mt[i - 1], bit.rshift(mt[i - 1], 30)) % TWO32, 1664525)) % TWO32 + key[j + 1] + j)
    i, j = i + 1, j + 1
    if i >= 624 then mt[0] = mt[623]; i = 1 end
    if j >= #key then j = 0 end
  end
  for _ = 1, 623 do
    mt[i] = u32(bit.bxor(mt[i], mul32(bit.bxor(mt[i - 1], bit.rshift(mt[i - 1], 30)) % TWO32, 1566083941)) % TWO32 - i)
    i = i + 1
    if i >= 624 then mt[0] = mt[623]; i = 1 end
  end
  mt[0] = 0x80000000
  return setmetatable({ mt = mt, pos = 624 }, Random)
end
function Random:word()
  local mt = self.mt
  if self.pos >= 624 then
    for k = 0, 623 do
      local y = bit.bor(bit.band(mt[k], 0x80000000), bit.band(mt[(k + 1) % 624], 0x7fffffff)) % TWO32
      mt[k] = bit.bxor(mt[(k + 397) % 624], bit.rshift(y, 1), y % 2 == 1 and 0x9908b0df or 0) % TWO32
    end
    self.pos = 0
  end
  local y = mt[self.pos]; self.pos = self.pos + 1
  y = bit.bxor(y, bit.rshift(y, 11)) % TWO32
  y = bit.bxor(y, bit.band(bit.lshift(y, 7), 0x9d2c5680)) % TWO32
  y = bit.bxor(y, bit.band(bit.lshift(y, 15), 0xefc60000)) % TWO32
  return bit.bxor(y, bit.rshift(y, 18)) % TWO32
end
function Random:random() local a, b = math.floor(self:word() / 32), math.floor(self:word() / 64); return (a * 67108864 + b) / 9007199254740992 end
function Random:uniform(a, b) return a + (b - a) * self:random() end

local function wav(path, samples, rate)
  local n = #samples
  local buf = ffi.new("int16_t[?]", n)
  for i = 1, n do buf[i - 1] = math.max(-1, math.min(1, samples[i])) * 32767 end   -- truncates toward zero, like int()
  local function le(v, bytes) local s = {}; for k = 1, bytes do s[k] = string.char(v % 256); v = math.floor(v / 256) end; return table.concat(s) end
  local f = assert(io.open(path, "wb"))
  f:write("RIFF", le(36 + 2 * n, 4), "WAVEfmt ", le(16, 4), le(1, 2), le(1, 2), le(rate, 4), le(rate * 2, 4), le(2, 2), le(16, 2), "data", le(2 * n, 4))
  f:write(ffi.string(buf, 2 * n)); f:close()
end

local function momentary_max(samples, rate)
  local padded = {}
  for i = 1, #samples do padded[i] = samples[i] end
  for i = 1, math.floor(rate * 0.6) do padded[#padded + 1] = 0.0 end
  local w = os.tmpname()
  wav(w, padded, rate)
  local p = io.popen("ffmpeg -nostats -i '" .. w .. "' -af ebur128 -f null - 2>&1")
  local out = p:read("*a"); p:close(); os.remove(w)
  local best
  for v in out:gmatch("%sM:%s*(%-?%d+%.?%d*)") do
    v = tonumber(v)
    if v > -100 and (not best or v > best) then best = v end
  end
  return best or -70.0
end

local function level(samples, rate)
  local m = momentary_max(samples, rate)
  local gain = math.max(GAIN_MIN, math.min(GAIN_MAX, TARGET_M - m)); local g = 10 ^ (gain / 20)
  local peak = 0
  for i = 1, #samples do local a = math.abs(samples[i]); if a > peak then peak = a end end
  peak = peak * g
  if peak > PEAK then g = g * PEAK / peak end
  local out = {}
  for i = 1, #samples do out[i] = samples[i] * g end
  return out, m, gain
end

function M.write_oga(path, samples, rate)
  local out, m, gain = level(samples, rate)
  local w = os.tmpname()
  wav(w, out, rate)
  local ok = os.execute("ffmpeg -v error -y -i '" .. w .. "' -c:a libvorbis -q:a 3 '" .. path .. "'")
  os.remove(w)
  assert(ok == 0 or ok == true, "ffmpeg failed for " .. path)
  return m, gain
end

return M
