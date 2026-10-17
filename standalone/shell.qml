//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=basic
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// The standalone Orbit launcher, run by the `orbit` command:
//   qs -p <this dir>    (ORBIT_CONFIG / ORBIT_ONESHOT are set by the wrapper)

import QtQuick
import Quickshell
import "Orbit"

ShellRoot {
    id: shell

    settings.watchFiles: false

    readonly property bool oneshot: Quickshell.env("ORBIT_ONESHOT") === "1"
    readonly property string configPath: Quickshell.env("ORBIT_CONFIG") || `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/orbit/orbit.conf`

    OrbitWindow {
        id: orbit

        config: OrbitConfig {
            source: shell.configPath
        }
        shortcutName: shell.oneshot ? "" : "orbit"

        // One-shot mode: open right away and exit once the close animation ends
        // (quickshell does not wire Qt.quit(), so end our own process)
        onDismissed: if (shell.oneshot) Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)])
        Component.onCompleted: if (shell.oneshot) Qt.callLater(() => orbit.open = true)
    }
}
