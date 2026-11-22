#!/usr/bin/luajit
-- mangohud-preview: a REAL MangoHud frame for Settings -> Gaming -> Overlay.
-- Starts vkcube under MangoHud with the current ~/.config/MangoHud/MangoHud.conf on a throw-away headless monitor
-- (a window on a hidden workspace gets no frames), photographs that window with grim and removes the monitor again.
-- Result: ~/.cache/lwts/mangohud-preview.png ; exit 0 = ok, 1 = missing tool, 2 = nothing to capture.
-- The vkcube window rule is in hypr/hyprland/core/rules.lua ("mangohud-preview": float, 960x540, monitor mhprev, no focus).

local HOME = os.getenv("HOME")
local OUT = HOME .. "/.cache/lwts/mangohud-preview.png"
local CONF = HOME .. "/.cache/lwts/mangohud-preview.conf"
local MON = "mhprev"

local function sh(cmd) local p = io.popen(cmd .. " 2>/dev/null"); local o = p:read("*a"); p:close(); return o end
local function ok(cmd) local r = os.execute(cmd .. " >/dev/null 2>&1"); return r == 0 or r == true end
local function have(bin) return ok("command -v " .. bin) end

for _, b in ipairs { "vkcube", "grim", "hyprctl", "mangohud" } do
  if not have(b) then io.stderr:write("missing: ", b, "\n"); os.exit(1) end
end
os.execute("mkdir -p '" .. HOME .. "/.cache/lwts'")

-- the preview config = the real one without no_display, and a frame cap so the cube does not run at 6000 fps
local src = io.open(HOME .. "/.config/MangoHud/MangoHud.conf"); local text = src and src:read("*a") or ""; if src then src:close() end
local cap = text:match("\nfps_limit=(%d+)") or text:match("^fps_limit=(%d+)")
local lines = {}
for l in (text .. "\n"):gmatch("(.-)\n") do
  if not l:match("^no_display") and not l:match("^fps_limit=") then lines[#lines + 1] = l end
end
lines[#lines + 1] = "fps_limit=" .. ((cap and cap ~= "0") and cap or "144")
local cf = io.open(CONF, "w"); cf:write(table.concat(lines, "\n"), "\n"); cf:close()

local created = false
-- a previous run killed half-way (panel closed, shell reload) leaves its cube and monitor behind
os.execute("pkill -x vkcube; hyprctl output remove " .. MON .. " >/dev/null 2>&1")
os.execute("sleep 0.2")
if not sh("hyprctl monitors -j"):find('"name": "' .. MON .. '"', 1, true) then
  os.execute("hyprctl output create headless " .. MON .. " >/dev/null 2>&1"); created = true
  os.execute("sleep 0.4")
end
os.execute("hyprctl eval 'hl.monitor({ output = \"" .. MON .. "\", mode = \"1920x1080@60\", position = \"20000x0\", scale = 1 })' >/dev/null 2>&1")

os.execute("hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd(\"env MANGOHUD=1 MANGOHUD_CONFIGFILE=" .. CONF
  .. " vkcube --wsi wayland --width 960 --height 540 --c 1000000000\"))' >/dev/null 2>&1")

local id
for _ = 1, 25 do   -- up to 5 s for the window
  os.execute("sleep 0.2")
  local clients = sh("hyprctl clients -j")
  for obj in clients:gmatch('{%s*"address".-"stableId": "%x+"') do
    if obj:find('"title": "vkcube"', 1, true) then id = obj:match('"stableId": "(%x+)"') end
  end
  if id then break end
end

local done = false
if id then
  os.execute("sleep 1.3")   -- stats and the frametime graph need a moment
  done = ok("grim -T " .. id .. " '" .. OUT .. ".tmp' && mv '" .. OUT .. ".tmp' '" .. OUT .. "'")
end
os.execute("pkill -x vkcube")
os.execute("sleep 0.2")
if created then os.execute("hyprctl output remove " .. MON .. " >/dev/null 2>&1") end
os.exit(done and 0 or 2)
