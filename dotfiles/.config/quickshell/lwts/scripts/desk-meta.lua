#!/usr/bin/luajit
-- desk-meta <folder>: what the icon layer cannot see through its folder model (desktop/DeskIconLayer.qml).
-- Tab separated lines: icon <file> <Icon= of a .desktop file> | link <file> (a symbolic link)
local dir = arg[1]
if not dir or dir == "" then os.exit(1) end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end
local function read(cmd) local h = io.popen(cmd .. " 2>/dev/null"); local d = h:read("*a"); h:close(); return d end
for name in read("find " .. q(dir) .. " -maxdepth 1 -type l -printf '%f\\n'"):gmatch("[^\n]+") do print("link\t" .. name) end
for name in read("ls -1A -- " .. q(dir)):gmatch("[^\n]+") do
  if name:match("%.desktop$") then
    local f = io.open(dir .. "/" .. name, "r")
    if f then
      for l in f:lines() do local ic = l:match("^Icon=(.+)$"); if ic then print("icon\t" .. name .. "\t" .. ic); break end end
      f:close()
    end
  end
end
