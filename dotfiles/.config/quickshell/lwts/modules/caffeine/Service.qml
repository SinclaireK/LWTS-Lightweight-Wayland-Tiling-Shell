// The Wayland idle inhibitor (needs a window: the bar's) while Caffeine is on and not "dark screen only".
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
Scope { IdleInhibitor { window: Modules.ctx.bar; enabled: Caffeine.on && !Caffeine.darkOnly } }
