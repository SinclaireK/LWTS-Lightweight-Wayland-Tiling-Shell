#!/usr/bin/luajit
-- desk-link <folder> <target>: makes a link on the desktop (desktop menu > New > Link; services/Desk.qml).
-- An existing file / folder -> a symbolic link with the target's name; a URL or a bare domain -> a .desktop launcher (Exec=xdg-open <target>)
-- named after the site. A taken name gets " 2".
local dir, target = arg[1], arg[2]
if not dir or not target or target == "" then os.exit(1) end
local home = os.getenv("HOME")
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end
local function exists(p) return os.execute("test -e " .. q(p)) == 0 end
if target:sub(1, 2) == "~/" then target = home .. target:sub(2) end
local name
if target:sub(1, 1) == "/" and exists(target) then   -- a real path: a symlink, like a shortcut
  os.execute("mkdir -p " .. q(dir))
  local base = target:match("([^/]+)/*$") or "link"
  local out, n = dir .. "/" .. base, 2
  while exists(out) or os.execute("test -L " .. q(out)) == 0 do out = dir .. "/" .. base .. " " .. n; n = n + 1 end
  os.execute("ln -s -- " .. q(target) .. " " .. q(out))
  os.exit(0)
end
if target:match("^%a[%w+.-]*://") then name = target:match("^%a[%w+.-]*://([^/?#]+)")
elseif target:sub(1, 1) == "/" then name = target:match("([^/]+)/*$") or target
elseif target:match("^[%w.-]+%.%a%a+[/?#]?") and not target:find("%s") then target = "https://" .. target; name = target:match("^https://([^/?#]+)")
else name = target end
name = (name or target):gsub("^www%.", ""):gsub("/", "_")
local function esc(s) return (s:gsub('[\\"`$]', "\\%0"):gsub("%%", "%%%%")) end
os.execute("mkdir -p " .. q(dir))
local out, n = dir .. "/" .. name .. ".desktop", 2
while exists(out) do out = dir .. "/" .. name .. " " .. n .. ".desktop"; n = n + 1 end
local f = io.open(out, "w"); if not f then os.exit(1) end
f:write("[Desktop Entry]\nType=Application\nName=" .. name .. "\nExec=xdg-open \"" .. esc(target) .. "\"\nTerminal=false\nIcon=web-browser\n")
f:close()
os.execute("chmod +x " .. q(out))
