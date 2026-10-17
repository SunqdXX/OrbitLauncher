// The smallest quickshell config that hosts Orbit as a plugin.
// Copy the Orbit/ folder next to your shell.qml (or install system-wide), then
// add the OrbitWindow block below to your own ShellRoot.
//
//   toggle:  qs -c <your-config> ipc call orbit toggle
//   or bind: bind = SUPER, A, global, quickshell:orbit

import QtQuick
import Quickshell
import qs.Orbit

ShellRoot {
    OrbitWindow {
        config: OrbitConfig {
            // Share the standalone launcher's config file (optional)...
            source: Quickshell.env("HOME") + "/.config/orbit/orbit.conf"
            // ...and/or set things directly; the file wins for keys it sets
            planet: "saturn"
            searchOpacity: 0.6
        }
    }
}
