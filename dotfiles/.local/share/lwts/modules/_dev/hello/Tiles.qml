import QtQuick
QtObject { property var defs: ({ hello: { icon: "star", label: () => "Hello", on: () => false, act: () => console.warn("HELLO tile") } }) }
