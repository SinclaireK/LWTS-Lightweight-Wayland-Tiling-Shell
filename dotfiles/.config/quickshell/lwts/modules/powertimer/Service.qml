// Keeps the PowerTimer singleton alive from shell start (reads a timer left running by a previous shell).
import QtQuick
import Quickshell
import qs.services
Scope { Component.onCompleted: PowerTimer.refresh() }
