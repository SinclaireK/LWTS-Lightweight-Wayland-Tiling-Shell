.pragma library
// Own dot-matrix glyphs for kinds of apps (7x7, '#' = lit) and the rule that picks a kind from desktop categories / a name.
// Used by UiKindIcon (Tasks rows, launcher search). Add a kind: draw it here, add its rule in `fromCategories` / `fromName`.
var glyphs = {
  browser:  [".#####.", "#..#..#", "#..#..#", "#######", "#..#..#", "#..#..#", ".#####."],
  terminal: ["#######", "#.....#", "#.#...#", "#..#..#", "#.#..##", "#.....#", "#######"],
  game:     [".......", ".#####.", "#.#.#.#", "###.#.#", "#.#.#.#", ".#####.", "......."],
  chat:     ["#######", "#.....#", "#.#.#.#", "#.....#", "#######", ".##....", ".#....."],
  video:    ["#######", "#.#...#", "#.##..#", "#.###.#", "#.##..#", "#.#...#", "#######"],
  music:    ["...####", "...#..#", "...#..#", "...#...", ".###...", ".###...", "......."],
  editor:   [".....##", "....###", "...###.", "..###..", ".###...", "##.#...", "##....."],
  code:     [".......", "..#.#..", ".#...#.", "#.....#", ".#...#.", "..#.#..", "......."],
  files:    [".......", "##.....", "#######", "#.....#", "#.....#", "#.....#", "#######"],
  system:   ["..#.#..", ".#####.", "##...##", ".#.#.#.", "##...##", ".#####.", "..#.#.."],
  office:   [".#####.", ".#...#.", ".#.#.#.", ".#...#.", ".#.#.#.", ".#...#.", ".#####."],
  graphics: ["#######", "#.....#", "#..#..#", "#.###.#", "##.#.##", "#######", "......."],
  network:  [".#####.", "#.....#", "..###..", ".#...#.", "...#...", ".......", "...#..."],
  ai:       ["...#...", "...#...", ".#.#.#.", "#######", ".#.#.#.", "...#...", "...#..."],
  other:    ["#######", "#.....#", "#.....#", "#..#..#", "#.....#", "#.....#", "#######"]
}
var names = Object.keys(glyphs)
// screens (the screen-share picker); added after `names` so they are not an app kind
glyphs.screen = ["#######", "#.....#", "#.....#", "#.....#", "#######", "..###..", ".#####."]
glyphs["screen-v"] = [".#####.", ".#...#.", ".#...#.", ".#...#.", ".#...#.", ".#####.", "..###.."]

// freedesktop Categories (any order) -> kind
function fromCategories(cats) {
  var c = (cats || []).map(function (x) { return String(x).toLowerCase() })
  function has() { for (var i = 0; i < arguments.length; i++) if (c.indexOf(arguments[i]) >= 0) return true; return false }
  if (has("webbrowser")) return "browser"
  if (has("terminalemulator", "consoleonly")) return "terminal"
  if (has("game", "emulator")) return "game"
  if (has("instantmessaging", "chat", "email", "telephony", "videoconference", "ircclient")) return "chat"
  if (has("video", "tv", "player") && !has("audio", "music")) return "video"
  if (has("audio", "music", "midi", "mixer")) return "music"
  if (has("texteditor")) return "editor"
  if (has("ide", "development", "debugger", "versioncontrol", "building", "translation")) return "code"
  if (has("filemanager", "filesystem", "archiving", "compression")) return "files"
  if (has("graphics", "photography", "2dgraphics", "3dgraphics", "rastergraphics", "vectorgraphics", "scanning", "viewer")) return "graphics"
  if (has("office", "spreadsheet", "wordprocessor", "presentation", "documentation", "calendar", "contactmanagement", "pdf")) return "office"
  if (has("network", "filetransfer", "p2p", "remoteaccess", "vpn", "webdevelopment")) return "network"
  if (has("system", "settings", "monitor", "packagemanager", "security", "hardwaresettings", "desktopsettings", "utility")) return "system"
  return ""
}

// process / app names with no desktop entry -> kind (first match wins)
var rules = [
  ["ai", /claude|ollama|opencode|codex|gemini|aider|llama|openai/],
  ["browser", /helium|firefox|chrom|brave|vivaldi|librewolf|zen-browser|epiphany|qutebrowser|webkit|msedge|opera/],
  ["terminal", /alacritty|kitty|foot|wezterm|konsole|xterm|tmux|screen|^(ba|z|fi)?sh$|fish|ssh|login|getty|agetty|nu$/],
  ["game", /steam|lutris|wine|proton|gamescope|heroic|dota|minecraft|bottles|retroarch|pcsx|ryujinx|yuzu|reaper|mangohud|gamemode|stalker|gamma|anomaly|xrengine/],
  ["chat", /telegram|discord|signal|element|slack|thunderbird|vesktop|teams|zoom|skype|whatsapp|matrix|evolution|geary/],
  ["video", /^mpv|vlc|obs|ffmpeg|totem|celluloid|haruna|kdenlive|handbrake|youtube|vidcap/],
  ["music", /spotify|mpd|ncmpcpp|cmus|rhythmbox|lollypop|easyeffects|playerctl|amberol|deadbeef/],
  ["editor", /^(n?vim|vi|nano|emacs|micro|helix|hx|gedit|kate|geany|obsidian|typora|sublime|marktext)$/],
  ["code", /^code|codium|cursor|zed|jetbrains|idea|pycharm|webstorm|clion|rustc|cargo|^node|npm|pnpm|yarn|bun$|deno|python|pip|^lua|luajit|gcc|g\+\+|clang|^cc1|^make|cmake|ninja|git|docker|podman|containerd|gdb|valgrind|tsserver|eslint|prettier|biome|vite|esbuild|go$|gopls|rust-analyzer|java|gradle|mvn/],
  ["files", /nautilus|dolphin|thunar|nemo|pcmanfm|yazi|ranger|lf$|nnn|mc$|ark$|file-roller|tracker|localsearch|baloo|udisks|gvfs|samba|smbd|nmbd|fuse|rclone|syncthing/],
  ["graphics", /gimp|inkscape|krita|blender|darktable|rawtherapee|figma|aseprite|feh|imv|swww|awww|wallpaper|mpvpaper|libreoffice-draw|shotwell|satty|grim|slurp|wf-recorder/],
  ["office", /libreoffice|soffice|onlyoffice|wps|evince|okular|zathura|calibre|foliate|abiword|gnumeric|masterpdf|xournal/],
  ["network", /networkmanager|nm-|wpa_supplicant|iwd|dhcp|dnsmasq|resolved|avahi|openvpn|wireguard|^wg|proton.?vpn|tailscale|cloudflared|nginx|apache|caddy|curl|wget|aria2|transmission|qbittorrent|deluge|nmap|ufw|firewalld|iptables|nftables|bluetooth|blueman|bluez/],
  ["system", /^systemd|dbus|polkit|udev|upower|pipewire|wireplumber|pulse|alsa|niri|quickshell|^qs$|lwts|greetd|agreety|kworker|ksoftirq|rcu|irqbalance|ananicy|dmemcg|snapper|limine|cron|chrony|timesyn|oomd|logind|journal|zram|thermald|power-profiles|powerd|ppd|tuned|auditd|xdg|gnome-keyring|ssh-agent|gpg-agent|at-spi|fcitx|ibus|xwayland|xwayland-satellite|portal|gvfsd|tumbler|pacman|yay|paru|flatpak|snap|plymouth|\(sd-pam\)|init|sd-pam|login|rtkit|tearing|nvidia|amdgpu|mesa|gpu|corectrl|lact/]
]
function fromName(name) {
  var n = String(name || "").toLowerCase()
  for (var i = 0; i < rules.length; i++) if (rules[i][1].test(n)) return rules[i][0]
  return "other"
}
