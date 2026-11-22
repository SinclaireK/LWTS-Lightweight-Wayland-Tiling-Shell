#!/usr/bin/luajit
-- `wl-paste --watch luajit clip-event.lua`: runs once per clipboard change with the new content on stdin.
-- Prints ONE JSON line for the shell (Clip.qml of the clipboard module): {"t":"text","s":"..."} or {"t":"image","f":"/path.png"}.
-- Skips copies from password managers (they mark them with the x-kde-passwordManagerHint type) and empty or huge ones.
local MAX_TEXT, MAX_IMAGE = 200000, 20 * 1024 * 1024

local p = io.popen("wl-paste --list-types 2>/dev/null")
local types = p and p:read("*a") or ""
if p then p:close() end
if types:find("x%-kde%-passwordManagerHint", 1) then os.exit(0) end

local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    return m[c] or string.format("\\u%04x", c:byte())
  end))
end

local data = io.read("*a") or ""
if data == "" then os.exit(0) end

local img = types:match("image/(png)") or types:match("image/(jpeg)") or types:match("image/(webp)")
if img and not types:find("text/plain", 1, true) then
  if #data > MAX_IMAGE then os.exit(0) end
  local dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/lwts-clip"
  os.execute("mkdir -p '" .. dir .. "'")
  local f = string.format("%s/%d-%d.%s", dir, os.time(), math.random(1000, 9999), img == "jpeg" and "jpg" or img)
  local h = io.open(f, "wb")
  if not h then os.exit(0) end
  h:write(data); h:close()
  io.write('{"t":"image","f":"', esc(f), '"}\n')
else
  if #data > MAX_TEXT or not data:find("%S") then os.exit(0) end
  io.write('{"t":"text","s":"', esc(data), '"}\n')
end
io.flush()
