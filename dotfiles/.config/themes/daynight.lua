#!/usr/bin/luajit
--[[ Day/night schedule for the night light and the light/dark theme (was daynight.py).
  The night light itself is native: this only flips ~/.local/state/nightlight, which modules/daynight/Night.qml watches (wlsunset).

  daynight.lua apply     put both into the state the schedule wants now, plan the next switch
  daynight.lua status    what is scheduled and when

Settings (~/.config/themes/settings.toml, edited from the launcher: Tab -> ⚙):
  nightlight_mode / darkmode_mode = "manual" | "sun" | "time"
  nightlight_night / nightlight_day, darkmode_night / darkmode_day = "HH:MM"   ("time" mode)
  nightlight_temp = 4000, day_theme / night_theme = palette ids, latitude / longitude ("sun" mode)

No polling: after each run a transient systemd user timer (rice-daynight) is set for the next
switch. Realtime timers that elapsed during suspend fire right after resume.
Manual toggles hold until the next scheduled switch.
The theme itself is switched by `theme.py set` (Pillow) — only when something really changes. ]]

local HOME = os.getenv("HOME")
local SELF = HOME .. "/.config/themes/daynight.lua"
local SETTINGS = HOME .. "/.config/themes/settings.toml"
local PALETTES = HOME .. "/.config/themes/palettes"
local THEME = HOME .. "/.config/themes/theme.py"
local STATE = HOME .. "/.local/state/theme/current"
local PERIOD = HOME .. "/.local/state/daynight-period"
local NIGHTLIGHT = HOME .. "/.local/state/nightlight"   -- on | off, watched by Night.qml
local GAME = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/game-mode"
local UNIT = "rice-daynight"
local MODES = { manual = true, sun = true, time = true }
local DEFAULTS = {
  nightlight_mode = "manual", nightlight_night = "21:00", nightlight_day = "07:00", nightlight_temp = 4000,
  darkmode_mode = "manual", darkmode_night = "20:00", darkmode_day = "07:00",
  day_theme = "garnet-light", night_theme = "garnet-dark",
  -- optional per period ("" = keep): wallpaper file name in ~/Pictures/Wallpapers, recolor off|soft|full
  day_wallpaper = "", night_wallpaper = "", day_recolor = "", night_recolor = "",
  latitude = 49.99, longitude = 36.23,  -- Kharkiv
}

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function read(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function write(path, s) local f = io.open(path, "w"); if f then f:write(s); f:close() end end
local function exists(path) local f = io.open(path, "r"); if f then f:close() end; return f ~= nil end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function out(cmd) local h = io.popen(cmd); local s = h:read("*a"); h:close(); return trim(s) end

-- flat `key = value` lines, as in rofi/settings.lua (settings.toml has no tables)
local function flat_toml(path)
  local t = {}
  for line in ((read(path) or "") .. "\n"):gmatch("([^\n]*)\n") do
    local key, val = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key then
      if val:sub(1, 1) == '"' then t[key] = val:match('^"([^"]*)"') or ""
      elseif val == "true" or val == "false" then t[key] = val == "true"
      else t[key] = tonumber(val:match("^[^#%s]+") or "") or val end
    end
  end
  return t
end

local function cfg()
  local raw, c = flat_toml(SETTINGS), {}
  for k, v in pairs(DEFAULTS) do if raw[k] ~= nil then c[k] = raw[k] else c[k] = v end end
  for _, k in ipairs({ "nightlight_mode", "darkmode_mode" }) do if not MODES[c[k]] then c[k] = "manual" end end
  return c
end

-- same as theme.set_setting(): replace `key = ...` keeping comments, or append
local function set_setting(key, value)
  local lines, found = {}, false
  for line in ((read(SETTINGS) or "") .. "\n"):gmatch("([^\n]*)\n") do
    if not found and line:match("^%s*" .. key .. "%s*=") then line, found = key .. " = " .. value, true end
    lines[#lines + 1] = line
  end
  while lines[#lines] == "" do lines[#lines] = nil end
  if not found then lines[#lines + 1] = key .. " = " .. value end
  write(SETTINGS, table.concat(lines, "\n") .. "\n")
end

-- a date is {y, m, d}; times are epoch seconds
local function date_of(t) local d = os.date("*t", t); return { d.year, d.month, d.day } end
local function next_day(day) return date_of(os.time({ year = day[1], month = day[2], day = day[3] + 1, hour = 12 })) end
local function yday(day) return os.date("*t", os.time({ year = day[1], month = day[2], day = day[3], hour = 12 })).yday end
local function hm(day, text)
  local h, m = text:match("^(%d+):(%d+)$")
  return os.time({ year = day[1], month = day[2], day = day[3], hour = tonumber(h), min = tonumber(m), sec = 0 })
end
local function utc_midnight(day)   -- days from civil (H. Hinnant): no timegm in Lua
  local y, m, d = day[1], day[2], day[3]
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return (era * 146097 + doe - 719468) * 86400
end

-- local sunrise and sunset (NOAA approximation, ~1 min); nil near polar day/night
local function sun_times(day, lat, lon)
  local g = 2 * math.pi / 365 * (yday(day) - 1)
  local eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                           - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
  local decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
               + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
  local la = math.rad(lat)
  local x = math.cos(math.rad(90.833)) / (math.cos(la) * math.cos(decl)) - math.tan(la) * math.tan(decl)
  if x < -1 or x > 1 then return nil end
  local ha = math.deg(math.acos(x))
  local mid = utc_midnight(day)
  return math.floor(mid + (720 - 4 * (lon + ha) - eqtime) * 60 + 0.5),
         math.floor(mid + (720 - 4 * (lon - ha) - eqtime) * 60 + 0.5)
end

-- (day starts, night starts) for `what` = "nightlight" | "darkmode" on a date
local function bounds(c, what, day)
  if c[what .. "_mode"] == "sun" then
    local rise, set = sun_times(day, c.latitude, c.longitude)
    if rise then return rise, set end
  end
  return hm(day, c[what .. "_day"]), hm(day, c[what .. "_night"])
end

-- is night now, next switch time; nil for manual mode
local function schedule(c, what, now)
  if c[what .. "_mode"] == "manual" then return nil end
  local today = date_of(now)
  local d0, n0 = bounds(c, what, today)
  local night
  if d0 < n0 then night = not (d0 <= now and now < n0) else night = n0 <= now and now < d0 end
  local d1, n1 = bounds(c, what, next_day(today))
  local soonest
  for _, t in ipairs({ d0, n0, d1, n1 }) do if t > now and (not soonest or t < soonest) then soonest = t end end
  return night, soonest
end

local function env_args()
  local env = {}
  for _, k in ipairs({ "NIRI_SOCKET", "WAYLAND_DISPLAY", "DISPLAY" }) do
    if os.getenv(k) then env[#env + 1] = "--setenv=" .. k .. "=" .. q(os.getenv(k)) end
  end
  return table.concat(env, " ")
end

local function plan(when)
  os.execute("systemctl --user stop " .. UNIT .. ".timer >/dev/null 2>&1")
  if not when then return end
  os.execute("systemd-run --user --quiet --unit=" .. UNIT .. " --collect --on-calendar=" .. q(os.date("%Y-%m-%d %H:%M:%S", when))
             .. " --timer-property=AccuracySec=1s " .. env_args() .. " /usr/bin/luajit " .. q(SELF) .. " apply >/dev/null 2>&1")
end

local function apply()
  local c, now, nexts = cfg(), os.time(), {}
  local night, at = schedule(c, "nightlight", now)
  if at then
    local want = night and "on" or "off"
    if trim(read(NIGHTLIGHT)) ~= want then write(NIGHTLIGHT, want .. "\n") end   -- Night.qml picks the change up
    nexts[#nexts + 1] = at
  end
  night, at = schedule(c, "darkmode", now)
  if at then
    local cur = trim(read(STATE))
    local in_game = exists(GAME)   -- game mode: don't switch the theme mid-game; game-mode.lua re-runs this at the end
    local target = in_game and cur or (night and c.night_theme or c.day_theme)
    local period = night and "night" or "day"
    -- wallpaper / recolour of the period: only when the period changes, so a wallpaper picked by
    -- hand during the day is not reset on every settings change
    local new_period = not in_game and trim(read(PERIOD)) ~= period
    local rc = new_period and c[period .. "_recolor"] or ""
    local recolor = rc == "off" or rc == "soft" or rc == "full"
    if recolor then set_setting("recolor", '"' .. rc .. '"') end
    if exists(PALETTES .. "/" .. target .. ".toml") and (cur ~= target or recolor) then
      os.execute("THEME_QUIET=1 python3 " .. q(THEME) .. " set " .. q(target))   -- no toast, as notify=False before
    end
    local wall = c[period .. "_wallpaper"] ~= "" and HOME .. "/Pictures/Wallpapers/" .. c[period .. "_wallpaper"] or nil
    if new_period and wall and exists(wall) then
      os.execute("qs -c lwts ipc call wallpaper set " .. q(wall) .. " >/dev/null 2>&1")
    end
    if new_period then write(PERIOD, period .. "\n") end
    nexts[#nexts + 1] = at
  end
  local soonest
  for _, t in ipairs(nexts) do if not soonest or t < soonest then soonest = t end end
  plan(soonest)
end

local function status()
  local c, now = cfg(), os.time()
  local rise, set = sun_times(date_of(now), c.latitude, c.longitude)
  if rise then print(("sun today: rise %s, set %s"):format(os.date("%H:%M", rise), os.date("%H:%M", set))) end
  for _, what in ipairs({ "nightlight", "darkmode" }) do
    local night, at = schedule(c, what, now)
    print(what .. ": " .. c[what .. "_mode"] .. (at and (", %s now, next switch %s"):format(night and "night" or "day", os.date("%a %H:%M", at)) or ""))
  end
end

local cmd = ({ apply = apply, status = status })[arg[1] or ""]
if cmd then cmd() else io.stderr:write("usage: daynight.lua apply | status\n"); os.exit(1) end
