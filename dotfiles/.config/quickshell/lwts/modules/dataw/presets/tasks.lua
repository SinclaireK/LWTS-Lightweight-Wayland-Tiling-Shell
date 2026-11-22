#!/usr/bin/luajit
-- Tasks / reminders from a markdown checklist: "- [ ] text @2026-11-14 18:00" (date/time optional). tasks.lua [file]
-- Prints JSON: value = the most urgent open task, sub = "N open · due ...", alert when overdue.
local path = arg[1] or (os.getenv("HOME") .. "/Documents/Notes/Tasks.md")
local f = io.open(path, "r")
if not f then print('{"value":"No tasks file","sub":"' .. path:gsub(os.getenv("HOME"), "~") .. '"}') return end
local now, open = os.time(), {}
for line in f:lines() do
  local text = line:match("^%s*[-*] %[ %]%s+(.+)$")
  if text then
    local y, mo, d, rest = text:match("@(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
    local due
    if y then
      local h, mi = rest:match("^%s+(%d%d?):(%d%d)")
      due = os.time({ year = y, month = mo, day = d, hour = h or 23, min = mi or 59 })
      text = text:gsub("%s*@%d%d%d%d%-%d%d%-%d%d.*$", "")
    end
    open[#open + 1] = { text = text, due = due }
  end
end
f:close()
table.sort(open, function(a, b) return (a.due or math.huge) < (b.due or math.huge) end)
local function esc(s) return (s:gsub('\\', '\\\\'):gsub('"', '\\"')) end
if #open == 0 then print('{"value":"All done","sub":"","on":false}') return end
local t, sub, alert = open[1], #open .. " open", false
if t.due then
  local m = math.floor((t.due - now) / 60)
  if m < 0 then sub = sub .. " · overdue"; alert = true
  elseif m < 60 then sub = sub .. " · in " .. m .. " min"
  elseif m < 1440 then sub = sub .. " · in " .. math.floor(m / 60) .. " h"
  else sub = sub .. " · " .. os.date("%d.%m", t.due) end
end
print(string.format('{"value":"%s","sub":"%s","on":true,"alert":%s}', esc(t.text), esc(sub), tostring(alert)))
