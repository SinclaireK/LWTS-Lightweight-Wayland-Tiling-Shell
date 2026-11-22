// Creates the Modes singleton at start (singletons are lazy), so its IPC target exists before the first tile read.
import QtQuick
QtObject { Component.onCompleted: Modes.mode }
