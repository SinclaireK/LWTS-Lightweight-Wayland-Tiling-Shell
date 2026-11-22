// Keeps the Hw singleton alive; it only does work while Sound or System is open in Settings.
import QtQuick
import Quickshell
import qs.services
Scope { Component.onCompleted: Hw.card }
