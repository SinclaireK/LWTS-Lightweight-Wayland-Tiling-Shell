#!/usr/bin/luajit
-- Adwaita -> Adwaita-lwts: blue folder tones get the theme accent's hue (S/L of the original kept).
-- usage: folder-recolor.lua '#rrggbb'   (accent = Material "primary" of the current theme)
local acc = arg[1]
if not (acc and acc:match("^#%x%x%x%x%x%x$")) then io.stderr:write("need #rrggbb\n") os.exit(1) end

local function rgb2hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l, h, s = (mx + mn) / 2, 0, 0
  if mx ~= mn then
    local d = mx - mn
    s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    if mx == r then h = (g - b) / d + (g < b and 6 or 0) elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, s, l
end
local function hsl2rgb(h, s, l)
  local function f(n)
    local k = (n + h / 30) % 12
    local a = s * math.min(l, 1 - l)
    return l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
  end
  return math.floor(f(0) * 255 + 0.5), math.floor(f(8) * 255 + 0.5), math.floor(f(4) * 255 + 0.5)
end

local ar, ag, ab = tonumber(acc:sub(2, 3), 16), tonumber(acc:sub(4, 5), 16), tonumber(acc:sub(6, 7), 16)
local ah, as = rgb2hsl(ar, ag, ab)
local k = math.min(1, as / 0.77)   -- the original blue #62a0ea has S = 0.77: a calm accent gives calmer folders

local function recolor(hex)
  local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
  local h, s, l = rgb2hsl(r, g, b)
  if h < 195 or h > 235 or s < 0.3 then return hex end   -- only the blue family
  return string.format("#%02x%02x%02x", hsl2rgb(ah, s * k, l))
end

local home = os.getenv("HOME")
local src = "/usr/share/icons/Adwaita/scalable/places"
local dst = home .. "/.local/share/icons/Adwaita-lwts"
os.execute(("mkdir -p '%s/scalable/places'"):format(dst))
local f = io.open(dst .. "/index.theme", "w")
f:write("[Icon Theme]\nName=Adwaita-lwts\nComment=Adwaita folders in the accent colour of the current theme\nInherits=Adwaita\nDirectories=scalable/places\n\n[scalable/places]\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Places\n")
f:close()
local p = io.popen(("ls '%s'"):format(src))
for name in p:lines() do
  if name:match("%.svg$") then
    local i = io.open(src .. "/" .. name, "rb"); local t = i:read("*a"); i:close()
    t = t:gsub("#%x%x%x%x%x%x", recolor)
    local o = io.open(dst .. "/scalable/places/" .. name, "wb"); o:write(t); o:close()
  end
end
p:close()
