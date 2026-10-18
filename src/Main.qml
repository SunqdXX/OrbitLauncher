pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "Orbit"
import "Orbit/internal/hypr.js" as Hypr

// The standalone launcher window. `orbitBackend` and `orbitHost` come from
// src/main.cpp; everything visible is the shared Orbit module.
Window {
    id: win

    title: "Orbit"
    color: "transparent"
    visible: popup.wantsVisible

    // With a backdrop the surface covers the output (layer-shell anchors it, or
    // the host sizes it on X11); otherwise it is exactly the launcher's size
    width: popup.backdrop && screen ? screen.width : popup.contentWidth
    height: popup.backdrop && screen ? screen.height : popup.contentHeight

    OrbitConfig {
        id: cfg

        backend: orbitBackend
        source: orbitHost.configPath
    }

    OrbitPopup {
        id: popup

        anchors.fill: parent
        config: cfg
        maxHeight: (win.screen ? win.screen.height : 1440) + 10
        onOpenChanged: orbitHost.setOpen(open)
        onDismissed: orbitHost.dismissed()
    }

    function openLauncher(): void {
        if (popup.open)
            return;
        orbitBackend.refreshApps(); // pick up apps installed since last time (daemon)
        orbitHost.prepareWindow(win, cfg.layer, cfg.namespace, popup.backdrop, cfg.monitor);
        if (orbitHost.onHyprland)
            orbitBackend.exec(["sh", "-c", Hypr.blurCommand(cfg.namespace, cfg.blur, cfg.blurIgnoreAlpha)], "");
        popup.open = true;
        win.requestActivate();
    }

    function closeLauncher(): void {
        popup.open = false;
    }

    // Click outside (focus moves to another window) closes, like wofi/rofi
    property bool _wasActive: false

    onActiveChanged: {
        if (active)
            _wasActive = true;
        else if (popup.open && _wasActive && cfg.closeOnFocusLoss)
            closeLauncher();
    }

    onVisibleChanged: if (!visible) _wasActive = false

    Connections {
        target: orbitHost

        function onOpenRequested(): void {
            win.openLauncher();
        }
        function onCloseRequested(): void {
            win.closeLauncher();
        }
        function onToggleRequested(): void {
            if (popup.open)
                win.closeLauncher();
            else
                win.openLauncher();
        }
        function onReloadRequested(): void {
            cfg.reload();
        }
    }

    Component.onCompleted: if (orbitHost.oneshot) Qt.callLater(openLauncher)
}
