#!/usr/bin/luajit
-- desk-compress <zip|tar.gz> <path>...: packs the files next to them (desktop icon menu > Compress; services/Desk.qml).
-- Name: the file's own name (or "Archive" for several) + the extension; a taken name gets " 2".
local kind = arg[1]
if kind ~= "zip" and kind ~= "tar.gz" or #arg < 2 then os.exit(1) end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end
local function exists(p) return os.execute("test -e " .. q(p)) == 0 end
local dir = arg[2]:match("^(.*)/[^/]+/*$") or "."
local names = {}
for i = 2, #arg do names[#names + 1] = q("./" .. arg[i]:match("([^/]+)/*$"))  -- "./": a name starting with - is not taken for an option
end
local base = #arg == 2 and arg[2]:match("([^/]+)/*$") or "Archive"
local out, n = base .. "." .. kind, 2
while exists(dir .. "/" .. out) do out = base .. " " .. n .. "." .. kind; n = n + 1 end
local cmd = (kind == "zip" and "zip -r -q " or "tar -czf ") .. q(out) .. " "
os.execute("cd " .. q(dir) .. " && " .. cmd .. table.concat(names, " "))
