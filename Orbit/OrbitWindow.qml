pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Orbit as a self-contained layer-shell popup. Drop one into any quickshell
// config and toggle it with `qs ipc call orbit toggle` or a Hyprland bind to
// `global, quickshell:orbit`. The window and everything in it is destroyed
// while closed, so an idle Orbit costs next to nothing.
PanelWindow {
    id: root

    property OrbitConfig config: OrbitConfig {}
    property bool open: false

    // Set either to "" to disable it (e.g. when your shell routes its own keybinds)
    property string ipcTarget: "orbit"
    property string shortcutName: "orbit"

    signal launched(var entry)
    signal dismissed      // fired once the close animation has finished

    function toggle(): void {
        open = !open;
    }
    function show(): void {
        open = true;
    }
    function hide(): void {
        open = false;
    }

    readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property bool backdrop: config.backdropOpacity > 0

    property real offsetScale: open ? 0 : 1

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.config.anim("defaultSpatial").duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.config.anim("defaultSpatial").curve
        }
    }

    property bool _shown: false
    onOffsetScaleChanged: if (offsetScale >= 1 && !open) finishClose()

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

    property bool _forceHidden: false

    // Pick the output when opening, so the launcher never jumps between screens
    function pickScreen(): var {
        const screens = Quickshell.screens;
        const want = config.monitor.trim().toLowerCase();
        if (want) {
            const m = screens.find(s => s.name.toLowerCase() === want || `${s.manufacturer} ${s.model} ${s.serialNumber}`.toLowerCase().includes(want));
            if (m)
                return m;
        }
        if (onHyprland && Hyprland.focusedMonitor) {
            const m = screens.find(s => s.name === Hyprland.focusedMonitor.name);
            if (m)
                return m;
        }
        return screens[0] ?? null;
    }

    onOpenChanged: {
        if (open) {
            _shown = true;
            _forceHidden = false;
            screen = pickScreen();
            applyBlur(); // cheap, and survives a `hyprctl reload` wiping runtime rules
            if (config.planet.trim().toLowerCase() === "random")
                config.rollPlanet();
            if (content.item)
                content.item.focusSearch();
        } else {
            closeFallback.restart();
            if (content.item)
                content.item.reset();
        }
    }

    visible: open || (offsetScale < 1 && !_forceHidden)
    color: "transparent"

    WlrLayershell.namespace: config.namespace
    WlrLayershell.layer: config.layer === "top" ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None : (onHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)

    // Without a backdrop the surface is only as big as the launcher, centred on
    // the output; with one it covers the output so it can dim and catch clicks
    anchors.top: true
    anchors.bottom: backdrop
    anchors.left: backdrop
    anchors.right: backdrop
    margins.top: backdrop ? 0 : Math.max(0, Math.round(((screen?.height ?? 1080) - implicitHeight) / 2 + config.verticalOffset))

    implicitWidth: content.item ? content.item.implicitWidth : 804
    implicitHeight: content.item ? content.item.implicitHeight : 870

    // Same treatment caelestia gives its drawers: a runtime layerrule (never
    // written to hyprland.conf). Tries the 0.53+ syntax, then the legacy one.
    function applyBlur(): void {
        if (!onHyprland)
            return;
        const ns = config.namespace.replace(/[^A-Za-z0-9_.-]/g, "");
        const on = config.blur ? 1 : 0;
        const a = Math.max(0, Math.min(1, config.blurIgnoreAlpha)).toFixed(2);
        const legacy = config.blur ? `hyprctl keyword layerrule 'blur, ${ns}' >/dev/null; hyprctl keyword layerrule 'ignorealpha ${a}, ${ns}' >/dev/null` : `hyprctl keyword layerrule 'unset, ${ns}' >/dev/null`;
        Quickshell.execDetached(["sh", "-c", `hyprctl keyword layerrule 'blur ${on}, match:namespace ${ns}' | grep -q '^ok' && hyprctl keyword layerrule 'ignore_alpha ${a}, match:namespace ${ns}' >/dev/null || { ${legacy}; }`]);
    }

    Connections {
        target: root.config
        function onBlurChanged(): void {
            root.applyBlur();
        }
        function onBlurIgnoreAlphaChanged(): void {
            root.applyBlur();
        }
        function onNamespaceChanged(): void {
            root.applyBlur();
        }
    }

    HyprlandFocusGrab {
        active: root.onHyprland && root.open && root.config.closeOnFocusLoss
        windows: [root]
        onCleared: root.open = false
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
        active: root.visible

        opacity: 1 - root.offsetScale
        scale: 1 - root.offsetScale * 0.13

        sourceComponent: OrbitView {
            config: root.config
            maxHeight: (root.screen?.height ?? 1440) + 10
            onRequestClose: root.open = false
            onLaunched: entry => root.launched(entry)
            Component.onCompleted: focusSearch()
        }
    }

    IpcHandler {
        target: root.ipcTarget
        enabled: root.ipcTarget !== ""

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open = true;
        }
        function close(): void {
            root.open = false;
        }
        function isOpen(): bool {
            return root.open;
        }
        function reload(): void {
            root.config.reload();
        }
    }

    Loader {
        active: root.onHyprland && root.shortcutName !== ""
        sourceComponent: GlobalShortcut {
            name: root.shortcutName
            description: "Toggle the Orbit launcher"
            onPressed: root.toggle()
        }
    }
}
