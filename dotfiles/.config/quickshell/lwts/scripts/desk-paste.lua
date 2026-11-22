#!/usr/bin/luajit
-- desk-paste <folder>: puts the clipboard into a folder as files (desktop menu > Paste, services/Desk.qml).
-- Copied files are copied in (a taken name gets " 2"), an image becomes "Pasted <time>.png", text becomes "Note <time>.txt".
local dir = arg[1]
if not dir or dir == "" then os.exit(1) end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end
local function exists(p) return os.execute("test -e " .. q(p)) == 0 end
local function fresh(name)
  local p, i = dir .. "/" .. name, 2
  while exists(p) do p = dir .. "/" .. name .. " " .. i; i = i + 1 end
  return p
end
local function read(cmd) local h = io.popen(cmd); local d = h:read("*a"); h:close(); return d end
os.execute("mkdir -p " .. q(dir))
local types = read("wl-paste --list-types 2>/dev/null")
local function has(t) return types:find(t, 1, true) ~= nil end
local function files(list, move)
  for u in list:gmatch("[^\r\n]+") do
    local path = u:match("^file://(.*)$")
    if path then
      path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      local base = path:match("([^/]+)/*$")
      if base and exists(path) then os.execute((move and "mv -n -- " or "cp -r -- ") .. q(path) .. " " .. q(fresh(base))) end
    end
  end
end
if has("x-special/gnome-copied-files") then   -- first line copy | cut, then the uris (Nautilus, desk-clip cut)
  local l = read("wl-paste -n -t x-special/gnome-copied-files 2>/dev/null")
  local move = l:match("^(%a+)") == "cut"
  files(l, move)
  if move then os.execute("wl-copy --clear") end
elseif has("text/uri-list") then
  files(read("wl-paste -n -t text/uri-list 2>/dev/null"), false)
elseif has("image/png") then
  os.execute("wl-paste -t image/png > " .. q(fresh("Pasted " .. os.date("%F_%H-%M-%S") .. ".png")))
elseif has("text/plain") then
  local f = io.open(fresh("Note " .. os.date("%F_%H-%M-%S") .. ".txt"), "wb")
  if f then f:write(read("wl-paste -n -t text/plain 2>/dev/null")); f:close() end
end
