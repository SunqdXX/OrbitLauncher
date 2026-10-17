// Offscreen render test: draws OrbitView into an image without showing anything.
// Renders on the top layer (input passes through) and grabs to a PNG:
//   ORBIT_OUT=/tmp/x.png ORBIT_SEARCH=fire qs -p tests/render
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Orbit"

ShellRoot {
    id: shell
    settings.watchFiles: false

    // Top layer so the compositor keeps drawing it (a covered background surface
    // gets no frames, and grabToImage would wait forever). No keyboard focus and
    // an empty input mask: it shows briefly but never takes clicks or keys.
    PanelWindow {
        id: win
        color: Quickshell.env("ORBIT_BG") || "#0d0e12"
        implicitWidth: view.implicitWidth
        implicitHeight: view.implicitHeight
        WlrLayershell.layer: WlrLayer.Top
        mask: Region {}
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "orbit-test"
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.left: true

        OrbitView {
            id: view
            config: OrbitConfig {
                id: cfg
                source: Quickshell.env("ORBIT_CONFIG") ?? ""
                stateDir: Quickshell.env("ORBIT_STATE") ?? ""
            }
            maxHeight: 1450
        }
    }

    Timer {
        running: true
        interval: Number(Quickshell.env("ORBIT_DELAY") || 2500)
        onTriggered: {
            const s = Quickshell.env("ORBIT_SEARCH");
            if (s) view.searchField.text = s;
            later.start();
        }
    }
    Timer {
        id: later
        interval: 1500
        onTriggered: view.grabToImage(r => {
            r.saveToFile(Quickshell.env("ORBIT_OUT") || "/tmp/orbit.png");
            console.log("ORBIT-RESULTS", view.results.length, view.orbitApps.slice(0, 5).map(a => a.name).join(", "));
            const sp = view.sphere; console.log("ORBIT-SPHERE", sp.yaw, sp.pitch, sp.fCount, sp.orbitR, sp.width, JSON.stringify(sp.project(sp.basePoint(0, sp.fCount))));
            console.log("ORBIT-TILES", sp.children.filter(c => c.slot !== undefined).slice(0,6).map(c => `${c.width.toFixed(0)}x${c.height.toFixed(0)} s=${c.scale.toFixed(2)} want=${(0.5+0.7*c.depth).toFixed(2)} hov=${c.children[3] ? c.children[3].containsMouse : "?"} z=${c.z.toFixed(2)} vis=${c.visible} chW=${c.children[0].width.toFixed(0)} img=${c.children[0].children[0].width}`).join(" | "));
            console.log("ORBIT-ERRORS", JSON.stringify(cfg.errors));
            Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)]);
        })
    }
}
