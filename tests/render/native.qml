// Render test inside the orbit binary: draws OrbitView offscreen and saves a PNG.
//   QT_QPA_PLATFORM=offscreen ORBIT_MAIN_QML=tests/render/native.qml \
//     ORBIT_OUT=/tmp/x.png ORBIT_SEARCH=fire orbit -c some.conf daemon -F
import QtQuick
import "Orbit"

Window {
    id: win

    visible: true
    color: orbitBackend.env("ORBIT_BG") || "#0d0e12"
    width: view.implicitWidth
    height: view.implicitHeight

    OrbitView {
        id: view

        config: OrbitConfig {
            id: cfg

            backend: orbitBackend
            source: orbitHost.configPath
            stateDir: orbitBackend.env("ORBIT_STATE")
        }
        maxHeight: 1450
    }

    Timer {
        running: true
        interval: Number(orbitBackend.env("ORBIT_DELAY") || 2500)
        onTriggered: {
            const s = orbitBackend.env("ORBIT_SEARCH");
            if (s)
                view.searchField.text = s;
            later.start();
        }
    }

    Timer {
        id: later

        interval: 1500
        onTriggered: view.grabToImage(r => {
            r.saveToFile(orbitBackend.env("ORBIT_OUT") || "/tmp/orbit.png");
            console.log("ORBIT-RESULTS", view.results.length, view.orbitApps.slice(0, 5).map(a => a.name).join(", "));
            console.log("ORBIT-ERRORS", JSON.stringify(cfg.errors));
            Qt.quit();
        })
    }
}
