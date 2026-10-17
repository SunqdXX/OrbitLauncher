// Embedding OrbitView inside a window/drawer your shell already owns, with
// colours bound live to your shell's palette. Here a plain PanelWindow stands
// in for "your drawer" and a QtObject for "your colour service".

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Orbit

ShellRoot {
    // Stand-in for e.g. caelestia's Colours.palette or end_4's Appearance.colors
    QtObject {
        id: myPalette

        property color primary: "#ffb4ab"
        property color surfaceContainer: "#271d1b"
        property color onSurface: "#f1dfdb"
    }

    PanelWindow {
        id: drawer

        property bool open: true

        visible: open
        color: "transparent"
        implicitWidth: view.implicitWidth
        implicitHeight: view.implicitHeight
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        OrbitView {
            id: view

            config: OrbitConfig {
                primary: myPalette.primary
                surfaceContainer: myPalette.surfaceContainer
                textColour: myPalette.onSurface
                planet: "mars"
                size: 560
            }
            onRequestClose: drawer.open = false
            Component.onCompleted: focusSearch()
        }
    }
}
