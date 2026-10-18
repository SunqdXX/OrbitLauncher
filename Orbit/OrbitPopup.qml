pragma ComponentBehavior: Bound

import QtQuick

// Open/close animation, optional backdrop and the lazily loaded launcher.
// Shared by the standalone window (src/Main.qml) and the quickshell
// OrbitWindow; the window around it only has to follow `wantsVisible`.
Item {
    id: root

    required property OrbitConfig config
    property bool open: false
    property real maxHeight: 1450

    // The window should exist while open and during the close animation
    readonly property bool wantsVisible: open || (offsetScale < 1 && !_forceHidden)
    readonly property bool backdrop: config.backdropOpacity > 0
    readonly property OrbitView view: content.item as OrbitView
    readonly property real contentWidth: view ? view.implicitWidth : 804
    readonly property real contentHeight: view ? view.implicitHeight : 870

    signal launched(var entry)
    signal dismissed      // the close animation has finished

    property real offsetScale: open ? 0 : 1

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.config.anim("defaultSpatial").duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.config.anim("defaultSpatial").curve
        }
    }

    property bool _shown: false
    property bool _forceHidden: false

    onOffsetScaleChanged: if (offsetScale >= 1 && !open) finishClose()

    onOpenChanged: {
        if (open) {
            _shown = true;
            _forceHidden = false;
            if (config.planet.trim().toLowerCase() === "random")
                config.rollPlanet();
            if (view)
                view.focusSearch();
        } else {
            closeFallback.restart();
            if (view)
                view.reset();
        }
    }

    function finishClose(): void {
        closeFallback.stop();
        if (!_shown)
            return;
        _shown = false;
        dismissed();
        // The view is unloaded with the window; hand its JS garbage back now
        Qt.callLater(gc);
    }

    // Animations only advance while the compositor draws us. Closed while hidden
    // (under a fullscreen game, on a sleeping output) the fade would never end,
    // so finish the close on a timer as well.
    Timer {
        id: closeFallback

        interval: root.config.anim("defaultSpatial").duration + 250
        onTriggered: if (!root.open) {
            root._forceHidden = true;
            root.finishClose();
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.backdrop
        color: root.config.backdropColour
        opacity: root.config.backdropOpacity * (1 - root.offsetScale)

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Loader {
        id: content

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.backdrop ? root.config.verticalOffset : 0
        active: root.wantsVisible

        opacity: 1 - root.offsetScale
        scale: 1 - root.offsetScale * 0.13

        sourceComponent: OrbitView {
            config: root.config
            maxHeight: root.maxHeight
            onRequestClose: root.open = false
            onLaunched: entry => root.launched(entry)
            Component.onCompleted: focusSearch()
        }
    }
}
