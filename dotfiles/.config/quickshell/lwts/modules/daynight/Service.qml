// Instantiates the Night singleton at start (state file + wlsunset).
import QtQuick
import Quickshell
Scope { property bool up: Night.active || true }
