pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "internal/hypr.js" as Hypr

// Orbit inside a quickshell config: a layer-shell popup you drop into your own
// ShellRoot. Toggle it with `qs ipc call orbit toggle` or a Hyprland bind to
// `global, quickshell:orbit`. The window and everything in it is destroyed
// while closed. (The standalone `orbit` binary does not use this file.)
PanelWindow {
    id: root

    property OrbitConfig config: OrbitConfig {}
    property alias open: popup.open

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

    QuickshellBackend {
        id: qsBackend
    }

    Component.onCompleted: if (!config.backend) config.backend = qsBackend

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

    Connections {
        target: popup

        function onOpenChanged(): void {
            if (popup.open) {
                root.screen = root.pickScreen();
                root.applyBlur(); // cheap, and survives a `hyprctl reload` wiping runtime rules
            }
        }
    }

    visible: popup.wantsVisible
    color: "transparent"

    WlrLayershell.namespace: config.namespace
    WlrLayershell.layer: config.layer === "top" ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None : (onHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)

    // Without a backdrop the surface is only as big as the launcher, centred on
    // the output; with one it covers the output so it can dim and catch clicks
    anchors.top: true
    anchors.bottom: popup.backdrop
    anchors.left: popup.backdrop
    anchors.right: popup.backdrop
    margins.top: popup.backdrop ? 0 : Math.max(0, Math.round(((screen?.height ?? 1080) - implicitHeight) / 2 + config.verticalOffset))

    implicitWidth: popup.contentWidth
    implicitHeight: popup.contentHeight

    function applyBlur(): void {
        if (onHyprland)
            Quickshell.execDetached(["sh", "-c", Hypr.blurCommand(config.namespace, config.blur, config.blurIgnoreAlpha)]);
    }

    HyprlandFocusGrab {
        active: root.onHyprland && root.open && root.config.closeOnFocusLoss
        windows: [root]
        onCleared: root.open = false
    }

    OrbitPopup {
        id: popup

        anchors.fill: parent
        config: root.config
        maxHeight: (root.screen?.height ?? 1440) + 10
        onLaunched: entry => root.launched(entry)
        onDismissed: root.dismissed()
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
