#!/usr/bin/env bash
# caffeine holds a block inhibitor that would refuse the suspend
pf="$XDG_RUNTIME_DIR/caffeine-inhibit.pid"
[ -f "$pf" ] && kill "$(cat "$pf")"
rm -f "$pf"
pkill -RTMIN+9 -x waybar
systemctl suspend
