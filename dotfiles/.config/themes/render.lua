#!/usr/bin/luajit
-- Renders the theme templates (what `matugen json` used to do) from ~/.cache/themes/current.json.
-- Usage: render.lua [current.json]
-- Test env: LWTS_RENDER_ROOT=<dir> writes outputs under <dir> instead of $HOME; LWTS_RENDER_NOHOOKS=1 skips post hooks.
-- Template syntax (exactly what the templates use):
--   {{ path }} / {{ path | filter: args | ... }}, paths: colors.<role>.<default|dark|light>.<hex|hex_stripped|rgb|red|green|blue>,
--   term.*, term_strip.*, ui.*, theme.name, mode, image, loop vars; filters: replace, saturate (hsl), auto_lightness
--   <* for name, value in colors *> ... <* endfor *>
local HOME = os.getenv("HOME")
local ROOT = os.getenv("LWTS_RENDER_ROOT") or HOME
local TPL = HOME .. "/.config/themes/templates/"

-- { template, output (relative to $HOME), post hook }
local JOBS = {
  { TPL .. "alacritty.toml", ".config/alacritty/colors.toml" },
  { TPL .. "btop.theme", ".config/btop/themes/matugen.theme", "pkill -USR2 btop || true" },
  -- in the background: `spicetify apply` takes ~2.5 s and held the whole theme switch
  { TPL .. "spicetify.ini", ".config/spicetify/Themes/Sleek/color.ini",
    "pgrep -x spicetify > /dev/null || setsid -f spicetify apply -n > /dev/null 2>&1" },
  { TPL .. "vscode-colors", ".cache/matugen/vscode-colors" },
  { TPL .. "vscode-colors.json", ".cache/matugen/vscode-colors.json" },
  { TPL .. "fish-colors.fish", ".config/fish/conf.d/matugen-colors.fish" },
  { TPL .. "telegram.tdesktop-theme", ".config/telegram-theme/matugen.tdesktop-theme" },
  { TPL .. "midnight-discord.css", ".var/app/com.discordapp.Discord/config/Vencord/themes/matugen-discord.theme.css" },
  { TPL .. "steam-adwaita.css", ".local/share/Steam/millennium/themes/adwaita/adwaita/colorthemes/matugen/matugen.css" },
  { TPL .. "steam-material.css", ".local/share/Steam/millennium/themes/Material-Theme/css/main/colors/matugen.css" },
  { TPL .. "fastfetch.jsonc", ".config/fastfetch/config.jsonc" },
  { TPL .. "mangohud-colors.conf", ".config/MangoHud/MangoHud.conf" },
  { TPL .. "gtk-colors.css", ".config/gtk-4.0/colors.css" },
  { TPL .. "gtk-colors.css", ".config/gtk-3.0/colors.css" },
  { TPL .. "soundcloud.css", ".local/share/helium-matugen/soundcloud.css" },
}

local function die(msg) io.stderr:write("render.lua: " .. msg .. "\n") os.exit(1) end

-- JSON decoder; objects keep key order in obj.__keys
local function json_decode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local val
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == '"' then pos = i + 1 return table.concat(out) end
      if c == "" then die("json: unterminated string") end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
        if e == "u" then
          local cp = tonumber(s:sub(i + 2, i + 5), 16)
          i = i + 6
          if cp >= 0xD800 and cp < 0xDC00 and s:sub(i, i + 1) == "\\u" then
            local lo = tonumber(s:sub(i + 2, i + 5), 16)
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            i = i + 6
          end
          local ch
          if cp < 0x80 then ch = string.char(cp)
          elseif cp < 0x800 then ch = string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
          elseif cp < 0x10000 then ch = string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
          else ch = string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
          out[#out + 1] = ch
        else
          out[#out + 1] = map[e] or die("json: bad escape")
          i = i + 2
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
  end
  function val()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local o = { __keys = {} }
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return o end
      while true do
        ws()
        local k = str()
        ws()
        if s:sub(pos, pos) ~= ":" then die("json: expected ':'") end
        pos = pos + 1
        o[k] = val()
        o.__keys[#o.__keys + 1] = k
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return o end
        if d ~= "," then die("json: expected ',' or '}'") end
      end
    elseif c == "[" then
      local a = {}
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1 return a end
      while true do
        a[#a + 1] = val()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return a end
        if d ~= "," then die("json: expected ',' or ']'") end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local n = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      if not n or n == "" then die("json: bad value at " .. pos) end
      pos = pos + #n
      return tonumber(n)
    end
  end
  return val()
end

-- colour maths (HSL, like matugen's saturate/auto_lightness)
local function hex2rgb(h) return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) end
local function round(x) return math.floor(x + 0.5 + 1e-6) end  -- ties round up like matugen (f32 maths)
local function rgb2hex(r, g, b) return string.format("#%02x%02x%02x", round(r), round(g), round(b)) end

local function rgb2hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l, h, s = (mx + mn) / 2, 0, 0
  if mx ~= mn then
    local d = mx - mn
    s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    if mx == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h, s, l
end

local function hsl2rgb(h, s, l)
  if s == 0 then return l * 255, l * 255, l * 255 end
  local function hue(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return hue(p, q, h + 1 / 3) * 255, hue(p, q, h) * 255, hue(p, q, h - 1 / 3) * 255
end

local function clamp01(x) return math.max(0, math.min(1, x)) end
local function to_hsl(v) if type(v) == "table" then return v[1], v[2], v[3] end return rgb2hsl(hex2rgb(v)) end

-- filters get (value, args, ctx)
local FILTERS = {
  replace = function(v, a) -- plain-text replace
    local from, to = a[1], a[2]
    local out, i = {}, 1
    while true do
      local s, e = v:find(from, i, true)
      if not s then out[#out + 1] = v:sub(i) break end
      out[#out + 1] = v:sub(i, s - 1) .. to
      i = e + 1
    end
    return table.concat(out)
  end,
  -- colour filters keep the colour as float HSL between steps (matugen does not round to hex in a chain)
  saturate = function(v, a)
    if a[2] ~= "hsl" then die("saturate: only the 'hsl' form is supported") end
    local h, s, l = to_hsl(v)
    return { h, clamp01(s + a[1] / 100), l }
  end,
  auto_lightness = function(v, a, ctx) -- dark colour (L < 0.5): lighter, light colour: darker
    local h, s, l = to_hsl(v)
    local d = a[1] / 100
    return { h, s, clamp01(l < 0.5 and l + d or l - d) }
  end,
}

local function parse_args(s)
  local args = {}
  for item in (s .. ","):gmatch("%s*(.-)%s*,") do
    local q = item:match('^"(.*)"$')
    if q then args[#args + 1] = q
    elseif tonumber(item) then args[#args + 1] = tonumber(item)
    elseif item ~= "" then args[#args + 1] = item end
  end
  return args
end

local function split_pipes(expr) -- split on | outside quotes
  local parts, cur, q = {}, {}, false
  for ch in expr:gmatch(".") do
    if ch == '"' then q = not q end
    if ch == "|" and not q then parts[#parts + 1] = table.concat(cur) cur = {}
    else cur[#cur + 1] = ch end
  end
  parts[#parts + 1] = table.concat(cur)
  return parts
end

local function color_format(entry, fmt)
  local hex = entry.color
  if fmt == "hex" then return hex end
  if fmt == "hex_stripped" then return hex:sub(2) end
  local r, g, b = hex2rgb(hex)
  if fmt == "rgb" then return string.format("rgb(%d, %d, %d)", r, g, b) end
  if fmt == "red" then return tostring(r) end
  if fmt == "green" then return tostring(g) end
  if fmt == "blue" then return tostring(b) end
  die("unknown colour format '" .. fmt .. "'")
end

local function lookup(path, scope, tplname)
  local node = scope
  local segs = {}
  for p in path:gmatch("[^.]+") do segs[#segs + 1] = p end
  for i, seg in ipairs(segs) do
    -- last segment of a colour entry ({color=...}) is a format
    if type(node) == "table" and node.color and not node[seg] and i == #segs then
      return color_format(node, seg)
    end
    if type(node) ~= "table" or node[seg] == nil then die(tplname .. ": unknown value '" .. path .. "'") end
    node = node[seg]
  end
  if type(node) == "table" then die(tplname .. ": '" .. path .. "' is not a value") end
  return tostring(node)
end

local function eval(expr, scope, ctx, tplname)
  local parts = split_pipes(expr)
  local v = lookup(parts[1]:match("^%s*(.-)%s*$"), scope, tplname)
  for i = 2, #parts do
    local name, args = parts[i]:match("^%s*([%w_]+)%s*:?%s*(.-)%s*$")
    local f = FILTERS[name] or die(tplname .. ": unsupported filter '" .. tostring(name) .. "'")
    v = f(v, parse_args(args), ctx)
  end
  if type(v) == "table" then v = rgb2hex(hsl2rgb(v[1], v[2], v[3])) end
  return v
end

local function sub_vars(text, scope, ctx, tplname)
  return (text:gsub("{{(.-)}}", function(e) return eval(e, scope, ctx, tplname) end))
end

local function render(text, data, tplname)
  local ctx = { dark = data.is_dark_mode }
  local out = {}
  local pos = 1
  while true do
    local s, e, name, val, src = text:find("<%*%s*for%s+([%w_]+)%s*,%s*([%w_]+)%s+in%s+([%w_]+)%s*%*>", pos)
    if not s then out[#out + 1] = sub_vars(text:sub(pos), data, ctx, tplname) break end
    out[#out + 1] = sub_vars(text:sub(pos, s - 1), data, ctx, tplname)
    local bs, be = text:find("<%*%s*endfor%s*%*>", e + 1)
    if not bs then die(tplname .. ": for without endfor") end
    local body = text:sub(e + 1, bs - 1)
    local coll = data[src] or die(tplname .. ": unknown collection " .. src)
    local keys = {}
    for _, k in ipairs(coll.__keys) do keys[#keys + 1] = k end
    table.sort(keys) -- matugen iterates by name
    for _, k in ipairs(keys) do
      local scope = setmetatable({ [name] = k, [val] = coll[k] }, { __index = data })
      out[#out + 1] = sub_vars(body, scope, ctx, tplname)
    end
    pos = be + 1
  end
  return table.concat(out)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then die("cannot read " .. path) end
  local s = f:read("*a")
  f:close()
  return s
end

local function main()
  local json_path = arg[1] or (HOME .. "/.cache/themes/current.json")
  local data = json_decode(read(json_path))
  local nohooks = os.getenv("LWTS_RENDER_NOHOOKS") == "1"
  local failed = 0
  for _, job in ipairs(JOBS) do
    local tpl, rel, hook = job[1], job[2], job[3]
    local ok, res = pcall(function() return render(read(tpl), data, tpl:match("[^/]+$")) end)
    if ok then
      local out = ROOT .. "/" .. rel
      os.execute(string.format("mkdir -p '%s'", out:match("^(.*)/[^/]*$")))
      local f = io.open(out, "wb")
      if f then
        f:write(res)
        f:close()
        if hook and not nohooks then os.execute(hook) end
      else
        io.stderr:write("render.lua: cannot write " .. out .. "\n")
        failed = failed + 1
      end
    else
      io.stderr:write(tostring(res) .. "\n")
      failed = failed + 1
    end
  end
  os.exit(failed == 0 and 0 or 1)
end

-- die() inside pcall must not kill the process: turn it into an error
local real_exit = os.exit
die = function(msg) error("render.lua: " .. msg, 0) end
main_ok, main_err = pcall(main)
if not main_ok then io.stderr:write(tostring(main_err) .. "\n") real_exit(1) end
