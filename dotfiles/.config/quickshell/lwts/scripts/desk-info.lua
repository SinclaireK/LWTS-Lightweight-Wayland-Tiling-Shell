#!/usr/bin/luajit
-- desk-info <path>: what the desktop icon menu needs to know about one file (services/Desk.qml, Open with / Properties).
-- Prints tab separated lines: type <mime> | size <bytes> | mtime <epoch> | items <n> (folders) | app <id> <name> <desktop file> <1 = default>
local path = arg[1]
if not path or path == "" then os.exit(1) end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end
local function read(cmd) local h = io.popen(cmd .. " 2>/dev/null"); local d = h:read("*a"); h:close(); return d end
local mime = read("gio info -a standard::content-type " .. q(path)):match("standard::content%-type:%s*(%S+)") or "application/octet-stream"
print("type\t" .. mime)
local size, mtime = read("stat -c '%s\t%Y' -- " .. q(path)):match("^(%d+)\t(%d+)")
if size then print("size\t" .. size); print("mtime\t" .. mtime) end
if mime == "inode/directory" then print("items\t" .. (read("ls -A -- " .. q(path)):gsub("[^\n]", ""):len())) end
local home = os.getenv("HOME")
local dirs = { home .. "/.local/share/applications", "/usr/local/share/applications", "/usr/share/applications",
               home .. "/.local/share/flatpak/exports/share/applications", "/var/lib/flatpak/exports/share/applications" }
local function find(id)
  for _, d in ipairs(dirs) do local f = io.open(d .. "/" .. id, "r"); if f then return d .. "/" .. id, f end end
end
local out = read("gio mime " .. q(mime))
local default = out:match("Default application for [^:]*:%s*(%S+)")
local seen, list = {}, {}
local function add(id) if id and not seen[id] then seen[id] = true; list[#list + 1] = id end end
add(default)
for id in out:gmatch("\n\t(%S+%.desktop)") do add(id) end
for _, id in ipairs(list) do
  local p, f = find(id)
  if p then
    local name, hidden
    for l in f:lines() do
      if not name then name = l:match("^Name=(.*)$") end
      if l:match("^NoDisplay=true") then hidden = true end
      if l:match("^%[") and name and l ~= "[Desktop Entry]" then break end
    end
    f:close()
    if not hidden then print("app\t" .. id .. "\t" .. (name or id) .. "\t" .. p .. "\t" .. (id == default and "1" or "0")) end
  end
end
