#!/usr/bin/luajit
-- Next event from a schedule: calendar.lua <url or file> [hours between downloads, default 6]
-- Formats: iCalendar (.ics: Google / Outlook / Moodle export; RRULE repeats are NOT expanded) or a CIST CSV export.
-- A URL is cached in ~/.cache/lwts/; offline = the last copy. cp1251 is converted to UTF-8.
-- JSON: list = today's events [{s,e,t,p,on}]; value = title (+ place), sub = "now till 11:05" / "in 40 min · 09:30" / "Mon 14.11 09:30"; alert = within 15 min.
local src, hours = arg[1], tonumber(arg[2]) or 6
if not src or src == "" then print('{"value":"No source","sub":"set a URL in widgets.json"}') return end
local function sh(c) local p = io.popen(c); local o = p:read("*a"); p:close(); return o end
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local path = src
if src:match("^https?://") then
  local dir = os.getenv("HOME") .. "/.cache/lwts"; os.execute("mkdir -p " .. q(dir))
  path = dir .. "/cal-" .. sh("printf %s " .. q(src) .. " | md5sum"):sub(1, 12)
  local age = tonumber(sh("s=$(stat -c %Y " .. q(path) .. " 2>/dev/null) && echo $(( $(date +%s) - s ))")) or 1e9
  if age > hours * 3600 then
    os.execute("curl -fsLm 40 -A lwts-calendar " .. q(src) .. " -o " .. q(path .. ".new") .. " && mv " .. q(path .. ".new") .. " " .. q(path) .. " || rm -f " .. q(path .. ".new"))
  end
end
local body = sh("f=" .. q(path) .. "; [ -f \"$f\" ] || exit; if iconv -f utf-8 -t utf-8 \"$f\" >/dev/null 2>&1; then cat \"$f\"; else iconv -f cp1251 -t utf-8 \"$f\"; fi")
if body == "" then print('{"value":"No data","sub":"source unreachable"}') return end

local utcOff = os.time() - os.time(os.date("!*t"))
local ev = {}
local function add(s, e, title, place) if s then ev[#ev + 1] = { s = s, e = e or s + 3600, title = title or "", place = place or "" } end end
if body:find("BEGIN:VCALENDAR", 1, true) then
  body = body:gsub("\r?\n[ \t]", "")   -- unfold
  local function ics(v)
    if not v then return nil end
    local y, mo, d, H, M, S, z = v:match("(%d%d%d%d)(%d%d)(%d%d)T?(%d?%d?)(%d?%d?)(%d?%d?)(Z?)")
    if not y then return nil end
    local t = os.time({ year = y, month = mo, day = d, hour = tonumber(H) or 0, min = tonumber(M) or 0, sec = tonumber(S) or 0 })
    return z == "Z" and t + utcOff or t
  end
  for blk in body:gmatch("BEGIN:VEVENT(.-)END:VEVENT") do
    add(ics(blk:match("\nDTSTART[^:\n]*:([^\r\n]+)")), ics(blk:match("\nDTEND[^:\n]*:([^\r\n]+)")),
        (blk:match("\nSUMMARY[^:\n]*:([^\r\n]+)") or ""):gsub("\\,", ","), (blk:match("\nLOCATION[^:\n]*:([^\r\n]+)") or ""):gsub("\\,", ","))
  end
else   -- CIST CSV: "Тема","Дата начала","Время начала","Дата завершения","Время завершения",... (13 columns)
  local f = {}
  for v in body:gmatch('"(.-)"') do f[#f + 1] = v end
  local function t(d, h) local dd, mm, yy = (d or ""):match("(%d+)%.(%d+)%.(%d+)"); local H, M = (h or ""):match("(%d+):(%d+)")
    return dd and H and os.time({ year = yy, month = mm, day = dd, hour = H, min = M }) or nil end
  for i = 14, #f - 12, 13 do
    local subj, kind, room = f[i]:match("^(%S+)%s+(%S+)%s+(%S+)")
    add(t(f[i + 1], f[i + 2]), t(f[i + 3], f[i + 4]), subj and (subj .. " " .. kind) or f[i], room ~= "DL" and room or "")
  end
end
local now, best = os.time(), nil
for _, x in ipairs(ev) do if x.e > now and (not best or x.s < best.s) then best = x end end
if not best then print('{"value":"Nothing ahead","sub":"","on":false}') return end
local m = math.floor((best.s - now) / 60)
local sub = m <= 0 and ("now till " .. os.date("%H:%M", best.e)) or m < 60 and ("in " .. m .. " min · " .. os.date("%H:%M", best.s))
  or os.date("%Y%m%d", best.s) == os.date("%Y%m%d", now) and ("today " .. os.date("%H:%M", best.s)) or os.date("%a %d.%m %H:%M", best.s)
local function esc(x) return (x:gsub('\\', '\\\\'):gsub('"', '\\"')) end
local value = best.title .. (best.place ~= "" and (" · " .. best.place) or "")
-- the time drop's day block: events per day for the next 21 days, days = { "YYYY-MM-DD": [{s,e,t,p,on}] } (s/e = HH:MM, on = running now); list = today's
local byDay, keys = {}, {}
local first, last = os.date("%Y-%m-%d", now), os.date("%Y-%m-%d", now + 21 * 86400)
table.sort(ev, function(a, b) return a.s < b.s end)
for _, x in ipairs(ev) do
  local k = os.date("%Y-%m-%d", x.s)
  if k >= first and k <= last and #(byDay[k] or {}) < 8 then
    if not byDay[k] then byDay[k] = {}; keys[#keys + 1] = k end
    byDay[k][#byDay[k] + 1] = string.format('{"s":"%s","e":"%s","t":"%s","p":"%s","on":%s}', os.date("%H:%M", x.s), os.date("%H:%M", x.e), esc(x.title), esc(x.place), tostring(x.s <= now and x.e > now))
  end
end
table.sort(keys)
local days = {}
for _, k in ipairs(keys) do days[#days + 1] = string.format('"%s":[%s]', k, table.concat(byDay[k], ",")) end
local items = byDay[first] and table.concat(byDay[first], ",") or ""
print(string.format('{"value":"%s","sub":"%s","on":%s,"alert":%s,"list":[%s],"days":{%s}}', esc(value), esc(sub), tostring(m <= 0), tostring(m > 0 and m <= 15), items, table.concat(days, ",")))
