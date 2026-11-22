#!/usr/bin/luajit
-- install.lua: put LWTS (the dotfiles/ folder of this repo) into $HOME.
--   ./install.lua                 show the plan, ask, install
--   ./install.lua --dry-run       show the plan only, change nothing
--   ./install.lua --yes           no questions (still makes the backup)
--   ./install.lua --no-packages   skip pacman (not Arch, or packages already there)
--   ./install.lua --optional      also install the [optional] packages of packages.txt
--   ./install.lua --dev           also install the owner's dev tools (lwts, lwts-sync-git, lwts-check, lwts-smoke, lwts-shot, lwts-click): they work on ~/Projects/LWTS
--   ./install.lua --uninstall [STAMP]  put back what the install replaced, remove what it added
--                                 (STAMP = backup folder name; default = the newest not yet restored)
-- Every file the install replaces is copied first to
--   ~/.local/state/lwts/install-backups/<stamp>/files/<same path>
-- A file changed by you after the install is never touched by --uninstall.
-- Needs only luajit and the usual coreutils (find, cp, chmod, sha256sum, xargs); pacman only for packages.

local HOME = os.getenv("HOME")
if not HOME or HOME == "" then io.stderr:write("HOME is not set\n") os.exit(1) end

local function q(s) return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'" end
local function ok(r) return r == 0 or r == true end
local function run(c) return ok(os.execute(c)) end
local function cap(c) local p = io.popen(c); local o = p:read("*a"); p:close(); return o end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end; local d = f:read("*a"); f:close(); return d end
local function write(p, d) local f = assert(io.open(p, "wb")); f:write(d); f:close() end
local function lines(s) local t = {} for l in s:gmatch("[^\n]+") do t[#t + 1] = l end return t end
local function say(f, ...) print(string.format(f, ...)) end
local function die(f, ...) io.stderr:write("ошибка: " .. string.format(f, ...) .. "\n") os.exit(1) end
local function dirname(p) return p:match("^(.*)/[^/]*$") or "." end
local function mkdir(p) if not run("mkdir -p -- " .. q(p)) then die("не могу создать папку %s", p) end end

local function usage()
  print("использование: ./install.lua [--dry-run] [--yes] [--no-packages] [--optional] [--dev] | --uninstall [STAMP]")
end

local opt = { dry = false, yes = false, pkgs = true, optional = false, dev = false, uninstall = false }
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "-n" or a == "--dry-run" then opt.dry = true
  elseif a == "-y" or a == "--yes" then opt.yes = true
  elseif a == "--no-packages" then opt.pkgs = false
  elseif a == "--optional" then opt.optional = true
  elseif a == "--dev" then opt.dev = true
  elseif a == "--uninstall" then
    opt.uninstall = true
    if arg[i + 1] and arg[i + 1]:sub(1, 1) ~= "-" then opt.stamp = arg[i + 1]; i = i + 1 end
  elseif a == "-h" or a == "--help" then usage() os.exit(0)
  else usage() os.exit(1) end
  i = i + 1
end

if cap("id -u"):match("^0") then die("запускай от обычного пользователя, не от root (sudo зовётся только для pacman)") end

local REPO = (cap("cd " .. q(dirname(arg[0] or ".")) .. " && pwd"):gsub("\n", ""))
local SRC = REPO .. "/dotfiles"
local STATE = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/lwts/install-backups"

local function confirm(msg)
  if opt.yes then return true end
  io.write(msg .. " [y/N] ")
  local a = io.read()
  return a == "y" or a == "Y"
end

-- ---------------------------------------------------------------- uninstall
local function uninstall()
  local bk
  if opt.stamp then bk = STATE .. "/" .. opt.stamp
  else
    local l = lines(cap("find " .. q(STATE) .. " -mindepth 1 -maxdepth 1 -type d ! -name '*.restored' 2>/dev/null | sort"))
    bk = l[#l]
  end
  if not bk or not read(bk .. "/sums.txt") then die("нет бэкапа установки в %s", STATE) end
  local sums = {}
  for _, l in ipairs(lines(read(bk .. "/sums.txt"))) do
    local h, p = l:match("^(%x+)  (.+)$")
    if h then sums[p] = h end
  end
  local cur = {}
  for _, l in ipairs(lines(cap("cd " .. q(HOME) .. " && xargs -d '\\n' sha256sum 2>/dev/null < " .. q(bk .. "/all.txt")))) do
    local h, p = l:match("^(%x+)  (.+)$")
    if h then cur[p] = h end
  end
  local rm, back, kept = {}, {}, {}
  for _, p in ipairs(lines(read(bk .. "/new.txt") or "")) do
    if cur[p] == nil then -- already gone
    elseif cur[p] == sums[p] then rm[#rm + 1] = p else kept[#kept + 1] = p end
  end
  for _, p in ipairs(lines(read(bk .. "/replaced.txt") or "")) do
    if cur[p] == sums[p] then back[#back + 1] = p else kept[#kept + 1] = p end
  end
  say("бэкап: %s", bk)
  say("вернуть из бэкапа: %d, удалить добавленное: %d, не трогать (ты менял после установки): %d", #back, #rm, #kept)
  for _, p in ipairs(kept) do say("  оставлен: ~/%s", p) end
  if opt.dry then return end
  if #back + #rm == 0 then say("делать нечего") return end
  if not confirm("Откатить?") then say("отменено") return end
  for _, p in ipairs(back) do
    run("cp -a --no-dereference --remove-destination -- " .. q(bk .. "/files/" .. p) .. " " .. q(HOME .. "/" .. p))
  end
  for _, p in ipairs(rm) do os.remove(HOME .. "/" .. p) end
  run("mv -- " .. q(bk) .. " " .. q(bk .. ".restored"))
  say("готово. Личные файлы (outputs.kdl, lwts.kdl, settings.toml, sources.toml) не удалялись.")
end

if opt.uninstall then uninstall() os.exit(0) end

-- ---------------------------------------------------------------- packages
local function pkglist(want)
  local t, sec = {}, "core"
  for l in io.lines(REPO .. "/packages.txt") do
    l = l:gsub("#.*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local s = l:match("^%[(%w+)%]$")
    if s then sec = s elseif l ~= "" and sec == want then t[#t + 1] = l end
  end
  return t
end

local function packages()
  if not run("command -v pacman >/dev/null 2>&1") then
    say("пакеты: pacman не найден (не Arch). Поставь по списку в packages.txt сам.")
    return
  end
  local want = pkglist("core")
  if opt.optional then for _, p in ipairs(pkglist("optional")) do want[#want + 1] = p end end
  local qs = {}
  for _, p in ipairs(want) do qs[#qs + 1] = q(p) end
  local missing = lines(cap("pacman -T " .. table.concat(qs, " ") .. " 2>/dev/null"))
  if #missing == 0 then say("пакеты: всё уже стоит") return end
  say("пакеты к установке (%d): %s", #missing, table.concat(missing, " "))
  if opt.dry then return end
  if not confirm("Поставить через sudo pacman -S --needed?") then say("пакеты пропущены") return end
  local mq = {}
  for _, p in ipairs(missing) do mq[#mq + 1] = q(p) end
  if not run("sudo pacman -S --needed " .. table.concat(mq, " ")) then die("pacman не справился, установка остановлена (файлы ещё не тронуты)") end
end

-- ---------------------------------------------------------------- plan
local plan = { new = {}, replaced = {}, same = 0 }
local data = {}
local execs = {}
for _, p in ipairs(lines(cap("cd " .. q(SRC) .. " && find . -type f ! -name .uuid -perm /111 | sort"))) do execs[p:gsub("^%./", "")] = true end
-- .uuid files are written by fc-cache in font folders (they got into git by accident): never install them
local rels = lines(cap("cd " .. q(SRC) .. " && find . -type f ! -name .uuid | sort"))
-- the owner's dev tools only make sense with the author's own project tree: not installed for other people unless --dev
local HOME_FILES = { [".config/qt5ct/qt5ct.conf"] = 1, [".config/qt6ct/qt6ct.conf"] = 1,
  [".local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.lwts.service"] = 1 }
local DEV_ONLY = { [".local/bin/lwts"] = 1, [".local/bin/lwts-sync-git"] = 1, [".local/bin/lwts-check"] = 1,
  [".local/bin/lwts-smoke"] = 1, [".local/bin/lwts-shot"] = 1, [".local/bin/lwts-click"] = 1 }
if #rels == 0 then die("в %s нет файлов", SRC) end
for _, r in ipairs(rels) do
  local rel = (r:gsub("^%./", ""))
  if DEV_ONLY[rel] and not opt.dev then goto skip end
  local d = read(SRC .. "/" .. rel)
  -- these files keep a @HOME@ placeholder in git (lwts-sync-git writes it): put the real home in. An explicit list on purpose:
  -- other files may contain the text @HOME@ as code (lwts-sync-git itself)
  if HOME_FILES[rel] then d = d:gsub("@HOME@", function() return HOME end) end
  data[rel] = d
  local cur = read(HOME .. "/" .. rel)
  if cur == nil then plan.new[#plan.new + 1] = rel
  elseif cur == d then plan.same = plan.same + 1
  else plan.replaced[#plan.replaced + 1] = rel end
  ::skip::
end

local function warnings()
  local nc = read(HOME .. "/.config/niri/config.kdl")
  local replaces_niri = false
  for _, p in ipairs(plan.replaced) do if p == ".config/niri/config.kdl" then replaces_niri = true end end
  if nc and replaces_niri and not nc:find('include "lwts.kdl"', 1, true) then
    print("\nВНИМАНИЕ: ~/.config/niri/config.kdl заменится конфигом LWTS (копия в бэкапе).")
    print("  Твои мониторы, ввод и бинды из старого конфига не переедут сами:")
    print("  мониторы перенеси в ~/.config/niri/outputs.kdl (пример: outputs.example.kdl), остальное смотри в бэкапе.")
  end
  if run("command -v noctalia >/dev/null 2>&1 || pacman -Qq noctalia-shell >/dev/null 2>&1") then
    print("\nВНИМАНИЕ: Noctalia установлена. Две оболочки сразу не нужны: LWTS стартует из своего config.kdl,")
    print("  а автозапуск Noctalia пропадёт вместе со старым конфигом.")
  end
end

say("LWTS: из %s в %s", SRC, HOME)
say("файлов к установке: %d (новых %d, заменится %d, уже совпадают %d)", #plan.new + #plan.replaced + plan.same, #plan.new, #plan.replaced, plan.same)
for n, p in ipairs(plan.replaced) do
  if n > 40 then say("  ... и ещё %d", #plan.replaced - 40) break end
  say("  заменится: ~/%s", p)
end
warnings()
print()
if opt.pkgs then packages() else say("пакеты: пропущены (--no-packages)") end
if opt.dry then say("\nтолько просмотр (--dry-run): ничего не изменено") os.exit(0) end
if #plan.new + #plan.replaced == 0 then say("\nфайлы уже совпадают, копировать нечего") end
if #plan.new + #plan.replaced > 0 and not confirm("\nУстановить файлы? Заменяемое сначала копируется в бэкап.") then say("отменено") os.exit(0) end

-- ---------------------------------------------------------------- install
local stamp = os.date("%Y-%m-%d_%H%M%S")
local bk = STATE .. "/" .. stamp
local todo = {}
for _, p in ipairs(plan.new) do todo[#todo + 1] = p end
for _, p in ipairs(plan.replaced) do todo[#todo + 1] = p end

if #todo > 0 then
  mkdir(bk .. "/files")
  for _, rel in ipairs(plan.replaced) do
    mkdir(dirname(bk .. "/files/" .. rel))
    if not run("cp -a --no-dereference -- " .. q(HOME .. "/" .. rel) .. " " .. q(bk .. "/files/" .. rel)) then
      die("не смог сделать бэкап %s, ничего не записано дальше", rel)
    end
  end
  local made, ex = {}, {}
  for _, rel in ipairs(todo) do
    local dest = HOME .. "/" .. rel
    local dir = dirname(dest)
    if not made[dir] then mkdir(dir) made[dir] = true end
    os.remove(dest) -- unlinks a symlink instead of writing through it; a regular file is rewritten anyway
    write(dest, data[rel])
    if execs[rel] then ex[#ex + 1] = rel end
  end
  write(bk .. "/new.txt", table.concat(plan.new, "\n") .. "\n")
  write(bk .. "/replaced.txt", table.concat(plan.replaced, "\n") .. "\n")
  write(bk .. "/all.txt", table.concat(todo, "\n") .. "\n")
  if #ex > 0 then
    write(bk .. "/exec.txt", table.concat(ex, "\n") .. "\n")
    run("cd " .. q(HOME) .. " && xargs -d '\\n' chmod 755 < " .. q(bk .. "/exec.txt"))
  end
  run("cd " .. q(HOME) .. " && xargs -d '\\n' sha256sum < " .. q(bk .. "/all.txt") .. " > " .. q(bk .. "/sums.txt"))
end

-- local files that must exist but are not in git (niri fails on a missing include; an empty file is fine)
local stubs = { ".config/niri/outputs.kdl", ".config/niri/lwts.kdl", ".config/themes/settings.toml" }
for _, rel in ipairs(stubs) do
  if read(HOME .. "/" .. rel) == nil then
    mkdir(dirname(HOME .. "/" .. rel))
    write(HOME .. "/" .. rel, "")
    say("создан пустой личный файл: ~/%s", rel)
  end
end
if read(HOME .. "/.config/lwts/sources.toml") == nil then -- module catalog shipped in dotfiles/.local/share/lwts/modules
  mkdir(HOME .. "/.config/lwts")
  write(HOME .. "/.config/lwts/sources.toml", 'local = "' .. HOME .. '/.local/share/lwts/modules"\n')
  say("создан ~/.config/lwts/sources.toml (каталог модулей)")
end

-- cursor themes lwts-black / lwts-white are generated from the Adwaita cursors (26 MB), not shipped; the generated niri config asks for lwts-black
if read(HOME .. "/.local/share/icons/lwts-black/index.theme") == nil then
  if run("test -d /usr/share/icons/Adwaita/cursors") then
    io.write("курсоры lwts-black и lwts-white: генерирую из Adwaita... ")
    io.flush()
    print(run("luajit " .. q(HOME .. "/.local/bin/lwts-cursor-gen") .. " >/dev/null 2>&1") and "ok" or "не вышло, запусти ~/.local/bin/lwts-cursor-gen сам")
  else
    print("курсоры: нет /usr/share/icons/Adwaita (пакет adwaita-icon-theme), lwts-cursor-gen не запущен")
  end
end

if run("command -v fc-cache >/dev/null 2>&1") then run("fc-cache -f " .. q(HOME .. "/.local/share/fonts") .. " >/dev/null 2>&1") end

-- ---------------------------------------------------------------- check
if run("command -v niri >/dev/null 2>&1") then
  io.write("\nniri validate: ")
  io.flush()
  if run("niri validate -c " .. q(HOME .. "/.config/niri/config.kdl") .. " >/dev/null 2>&1") then print("конфиг в порядке")
  else print("ОШИБКА, запусти `niri validate` и посмотри строку") end
else
  print("\nniri не найден: поставь пакеты (без --no-packages) или сам")
end
if run("command -v pacman >/dev/null 2>&1") then -- things the shell cannot work without (found by an audit of what it runs)
  local need, miss = { "xdg-desktop-portal-gnome", "python-gobject", "python-numpy", "pipewire", "wireplumber", "quickshell" }, {}
  for _, p in ipairs(need) do if not run("pacman -Qq " .. p .. " >/dev/null 2>&1") then miss[#miss + 1] = p end end
  if #miss > 0 then
    say("\nНЕ СТОИТ: %s", table.concat(miss, " "))
    print("  без них не заработают трансляция экрана (портал), темы или сам шелл: sudo pacman -S --needed " .. table.concat(miss, " "))
  end
end
for _, c in ipairs({ "quickshell", "luajit" }) do
  if not run("command -v " .. c .. " >/dev/null 2>&1") then say("не найден: %s", c) end
end

print()
if #todo > 0 then say("бэкап: %s", bk) say("откат:  ./install.lua --uninstall") end
print("дальше:")
print("  1. мониторы: `niri msg outputs`, потом ~/.config/niri/outputs.kdl (пример: outputs.example.kdl в той же папке)")
print("  2. выйди из сессии и зайди в Niri заново (шелл стартует из config.kdl), или сразу: niri msg action spawn -- qs -c lwts")
print("  3. сервисы, если ещё не включены: sudo systemctl enable --now NetworkManager bluetooth power-profiles-daemon")
print("  4. портал трансляции экрана подхватится после перезахода в сессию (или: systemctl --user restart xdg-desktop-portal)")
