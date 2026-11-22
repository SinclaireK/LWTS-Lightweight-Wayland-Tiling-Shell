#!/usr/bin/luajit
-- game-env: the files behind Settings -> Gaming -> Environment (read by ~/.local/bin/lwts-game and steam-launch).
--   game-env games                  installed Steam games: "<appid>\t<name>" (all libraries)
--   game-env get <global|appid>     the KEY=value lines
--   game-env set <global|appid> KEY VALUE
--   game-env del <global|appid> KEY
local HOME = os.getenv("HOME")
local DIR = HOME .. "/.config/lwts/game-env/"
local function die(m) io.stderr:write("game-env: ", m, "\n"); os.exit(2) end

local function read(path) local f = io.open(path); if not f then return nil end; local s = f:read("*a"); f:close(); return s end

local function scope(s) if s == "global" or (s and s:match("^%d+$") and #s <= 10) then return DIR .. s .. ".env" end die("bad scope") end
local function lines(path) local t = {}; for l in (read(path) or ""):gmatch("[^\n]+") do t[#t + 1] = l end; return t end
local function save(path, t)
  os.execute("mkdir -p '" .. DIR .. "'")
  if #t == 0 then os.remove(path); return end
  local f = assert(io.open(path .. ".tmp", "w")); f:write(table.concat(t, "\n"), "\n"); f:close(); os.rename(path .. ".tmp", path)
end

local cmd = arg[1]
if cmd == "games" then
  local libs = { HOME .. "/.local/share/Steam" }
  for p in (read(HOME .. "/.local/share/Steam/steamapps/libraryfolders.vdf") or ""):gmatch('"path"%s+"([^"]+)"') do libs[#libs + 1] = p end
  local seen, out = {}, {}
  for _, lib in ipairs(libs) do
    local p = io.popen("ls '" .. lib:gsub("'", "") .. "'/steamapps/appmanifest_*.acf 2>/dev/null")
    for f in p:lines() do
      local t = read(f) or ""
      local id, name = t:match('"appid"%s+"(%d+)"'), t:match('"name"%s+"([^"]*)"')
      if id and name and not seen[id] and not name:match("^Proton") and not name:match("^Steam Linux Runtime") and not name:match("^Steamworks")
         and not name:match("Redistributable") then seen[id] = true; out[#out + 1] = id .. "\t" .. name end
    end
    p:close()
  end
  table.sort(out, function(a, b) return a:match("\t(.*)"):lower() < b:match("\t(.*)"):lower() end)
  print(table.concat(out, "\n"))
elseif cmd == "get" then
  io.write(read(scope(arg[2])) or "")
elseif cmd == "set" then
  local path, key, val = scope(arg[2]), arg[3], arg[4]
  if not key or not key:match("^[%a_][%w_]*$") or #key > 64 then die("bad name") end
  if not val or #val > 200 or val:find("[%c]") then die("bad value") end
  local t, done = lines(path), false
  for i, l in ipairs(t) do if l:match("^" .. key .. "=") then t[i] = key .. "=" .. val; done = true end end
  if not done then t[#t + 1] = key .. "=" .. val end
  save(path, t)
elseif cmd == "del" then
  local path, key = scope(arg[2]), arg[3] or ""
  local t = {}
  for _, l in ipairs(lines(path)) do if not l:match("^" .. key:gsub("%p", "%%%0") .. "=") then t[#t + 1] = l end end
  save(path, t)
else
  die("usage: games | get <scope> | set <scope> KEY VALUE | del <scope> KEY")
end
