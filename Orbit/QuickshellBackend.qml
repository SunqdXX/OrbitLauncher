pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Backend for running Orbit inside a quickshell config. The standalone `orbit`
// binary provides the same functions natively (src/backend.cpp).
QtObject {
    id: root

    readonly property string kind: "quickshell"

    signal fileChanged(string path)

    readonly property var apps: DesktopEntries.applications.values.map(e => ({
                id: e.id,
                name: e.name,
                genericName: e.genericName,
                comment: e.comment,
                icon: e.icon,
                execString: e.execString,
                command: Array.from(e.command),
                workingDirectory: e.workingDirectory,
                runInTerminal: e.runInTerminal,
                categories: Array.from(e.categories),
                keywords: Array.from(e.keywords),
                startupClass: e.startupClass,
                noDisplay: e.noDisplay
            }))

    function refreshApps(): void {
        // quickshell keeps DesktopEntries up to date by itself
    }

    function iconUrl(name: string): string {
        return Quickshell.iconPath(name, "image-missing");
    }

    function env(name: string): string {
        return Quickshell.env(name) ?? "";
    }

    function exec(command: var, workingDirectory: string): void {
        Quickshell.execDetached({
            command: command,
            workingDirectory: workingDirectory
        });
    }

    function mkdirs(path: string): void {
        Quickshell.execDetached(["mkdir", "-p", path]);
    }

    function readFile(path: string): string {
        if (!path)
            return "";
        const v = _view(path);
        v.reload();
        return v.text() ?? "";
    }

    function writeFile(path: string, text: string): bool {
        _view(path).setText(text);
        return true;
    }

    function watch(path: string): void {
        if (path)
            _view(path);
    }

    function processId(): int {
        return Quickshell.processId;
    }

    property var _views: ({})

    property Component _viewComponent: Component {
        FileView {
            blockLoading: true
            printErrors: false
            atomicWrites: true
            watchChanges: true
        }
    }

    function _view(path: string): var {
        let v = _views[path];
        if (!v) {
            v = _viewComponent.createObject(root, {
                path: path
            });
            v.fileChanged.connect(() => root._changed(path));
            _views[path] = v;
        }
        return v;
    }

    // Editors replace the file (new inode), which ends a FileView's watch, and
    // the event can arrive before the new content: wait a moment, then start
    // over with a fresh FileView on the path
    property var _pending: ({})

    function _changed(path: string): void {
        _pending[path] = true;
        _debounce.restart();
    }

    property Timer _debounce: Timer {
        interval: 80
        onTriggered: {
            const paths = Object.keys(root._pending);
            root._pending = {};
            for (const p of paths) {
                const old = root._views[p];
                delete root._views[p];
                if (old)
                    old.destroy();
                root._view(p);
                root.fileChanged(p);
            }
        }
    }
}
