#!/usr/bin/luajit
-- desk-clip <cut|copy> <path>...: puts files on the clipboard (desktop icons menu > Cut / Copy; services/Desk.qml).
-- copy = text/uri-list (Nautilus, browsers, Telegram paste it as files); cut = x-special/gnome-copied-files "cut" (Nautilus and desk-paste move them).
local mode = arg[1]
if mode ~= "cut" and mode ~= "copy" then os.exit(1) end
local function enc(p) return (p:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end)) end
local lines = {}
for i = 2, #arg do lines[#lines + 1] = "file://" .. enc(arg[i]) end
if #lines == 0 then os.exit(1) end
local body, mime
if mode == "cut" then mime = "x-special/gnome-copied-files"; body = "cut\n" .. table.concat(lines, "\n")
else mime = "text/uri-list"; body = table.concat(lines, "\r\n") .. "\r\n" end
local h = io.popen("wl-copy -t " .. mime, "w")
h:write(body); h:close()
