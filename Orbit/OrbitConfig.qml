pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "internal/conf.js" as Conf
import "internal/theme.js" as Theme

// Every knob Orbit has. The defaults reproduce the original caelestia launcher.
//
// Set properties directly from QML, point `source` at an orbit.conf, or both:
// keys present in the file win, and removing a key from the file puts the
// QML value back on the next reload.
QtObject {
    id: root

    // ---- file loading ---------------------------------------------------
    property string source: ""          // path to orbit.conf ("" = QML values only)
    property bool watchFile: true       // hot-reload when the file changes
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property list<string> errors: _errors
    signal reloaded

    // ---- size & layout --------------------------------------------------
    property real size: 0               // sphere diameter box in px, 0 = fit the screen like the original
    property real minSize: 420
    property real maxSize: 780
    property real padding: 12
    property real orbitRadius: 0.42     // icon orbit radius, fraction of the sphere box
    property real tileSize: 0.22        // icon tile edge, fraction of the orbit radius
    property real ringTileSize: 0.17    // same, for the flat ring layout
    property real iconScale: 0.72       // icon inside its tile
    property real tileRadius: 12
    property real searchWidth: 0.7      // search bar width, fraction of the sphere box
    property real searchHeight: 0       // 0 = sized by the font
    property real searchPadding: 9      // vertical padding inside the search bar
    property bool showLabels: true

    // ---- planet ----------------------------------------------------------
    property string planet: "moon"      // file name in planetsDir (extension optional), "auto" or "random"
    property string planetsDir: ""      // "" = the planets bundled with Orbit
    property string orbitStyle: "auto"  // sphere | rings | auto (rings for saturn)
    property real planetSpin: 30        // how much the planet texture turns with the orbit
    property real planetResolution: 1024
    property bool vignette: true
    property color planetBackground: "#101018"

    // ---- motion ----------------------------------------------------------
    property real idleSpeed: 0.12       // rad/s the orbit drifts on its own
    property real restPitch: -0.35      // tilt the orbit settles back to
    property real dragSensitivity: 1.6
    property bool animations: true
    property real animSpeed: 1          // 2 = twice as fast, 0.5 = half speed
    property int maxFps: 0              // 0 = every frame the compositor offers

    // ---- search bar ------------------------------------------------------
    property real searchOpacity: 0.92   // 0 = invisible pill, 1 = solid
    property string placeholder: qsTr("Search local orbit...")
    property string fontFamily: "Google Sans Flex"
    property real fontSize: 13
    property real labelFontSize: 13
    property real iconFontSize: 16

    // ---- colours ("" = take it from themeFile, then the built-in palette) --
    property string themeFile: ""       // caelestia / matugen / pywal JSON, hot-reloaded
    property string themeMode: "dark"
    property string primary: ""
    property string surfaceContainer: ""
    property string textColour: ""
    property string iconColour: ""
    property string placeholderColour: ""
    property string searchColour: ""    // "" = surfaceContainer lifted one layer, like caelestia
    property string tileColour: ""      // "" = surfaceContainer
    property real tileOpacity: 0.85
    property string labelBackground: "#0a0b14"
    property real labelOpacity: 0.75
    property string labelColour: "#e6e7f0"

    // ---- apps ------------------------------------------------------------
    property int maxApps: 48
    property list<string> favouriteApps: []
    property list<string> hiddenApps: []     // desktop ids or /regex/
    property string specialPrefix: ">"
    property list<string> launchPrefix: ["auto"]  // auto = `uwsm app --` inside a uwsm session
    property list<string> terminal: []       // [] = $TERMINAL, else kitty
    property bool closeOnLaunch: true
    property bool sortByFrequency: true
    property string stateDir: ""             // "" = $XDG_STATE_HOME/orbit

    // ---- window (OrbitWindow only) -----------------------------------------
    property string monitor: ""         // "" = focused; else output name or part of its description
    property real backdropOpacity: 0    // > 0 dims the screen behind the launcher
    property color backdropColour: "#000000"
    property string layer: "overlay"    // overlay | top
    property string namespace: "orbit"  // layer-shell namespace, for layerrules
    property bool blur: true            // Hyprland: blur behind the search pill (runtime layerrule, nothing is written)
    property real blurIgnoreAlpha: 0.87 // only pixels more opaque than this get blurred behind them
    property bool closeOnFocusLoss: true
    property real verticalOffset: 0
    property string iconTheme: ""       // read by the `orbit` wrapper, not by QML
    property string renderer: "gl"      // gl | software, read by the `orbit` wrapper

    // ---- resolved values (read these, not the raw strings above) --------------
    readonly property var themeColours: _theme
    readonly property color cPrimary: primary || _theme.primary || "#ccd7ff"
    readonly property color cSurfaceContainer: surfaceContainer || _theme.surfaceContainer || "#17191f"
    readonly property color cText: textColour || _theme.onSurface || "#e3e5f0"
    readonly property color cIcon: iconColour || _theme.onSurfaceVariant || "#a9abb5"
    readonly property color cPlaceholder: placeholderColour || _theme.outline || "#73757f"
    readonly property color cSearch: Qt.alpha(searchColour || lift(cSurfaceContainer), clamp01(searchOpacity))
    readonly property color cTile: tileColour || cSurfaceContainer
    readonly property color cLabelBackground: Qt.alpha(labelBackground, clamp01(labelOpacity))
    readonly property color cLabel: labelColour || cText
    readonly property color cKey: _theme.keyColour || cPrimary

    readonly property string resolvedStateDir: expand(stateDir) || ((Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`) + "/orbit")
    readonly property string resolvedPlanetsDir: expand(planetsDir) || Qt.resolvedUrl("planets").toString().replace(/^file:\/\//, "")
    readonly property string resolvedOrbitStyle: orbitStyle === "auto" ? (resolvedPlanet === "saturn" ? "rings" : "sphere") : orbitStyle
    readonly property string resolvedPlanet: {
        const p = planet.trim().toLowerCase();
        if (p === "auto")
            return Theme.planetForColour(cKey);
        if (p === "random")
            return _randomPlanet;
        return planet.trim() || "moon";
    }

    function expand(p: string): string {
        return Conf.expandHome(p, home);
    }

    function clamp01(v: real): real {
        return Math.max(0, Math.min(1, v));
    }

    // caelestia's Colours.layer(c, 2) for a dark scheme with blur on: brighten
    // by a luminance offset so the pill reads as a raised surface
    function lift(c: color): color {
        const lum = Math.sqrt(0.299 * c.r * c.r + 0.587 * c.g * c.g + 0.114 * c.b * c.b);
        if (lum === 0)
            return Qt.rgba(0.13, 0.14, 0.18, 1);
        const light = c.hslLightness > 0.5;
        const offset = (light ? -1 : 1) * (light ? 0.2 : 0.3) * 0.1 * 1.625;
        const s = (lum + offset) / lum;
        return Qt.rgba(Math.min(1, c.r * s), Math.min(1, c.g * s), Math.min(1, c.b * s), 1);
    }

    function anim(name: string): var {
        // Material 3 expressive curves and durations, as used by caelestia
        const curves = {
            standardSmall: [200, [0.2, 0, 0, 1, 1, 1]],
            defaultSpatial: [500, [0.38, 1.21, 0.22, 1, 1, 1]],
            slowSpatial: [650, [0.39, 1.29, 0.35, 0.98, 1, 1]],
            defaultEffects: [200, [0.34, 0.8, 0.34, 1, 1, 1]],
            standard: [400, [0.2, 0, 0, 1, 1, 1]]
        };
        const c = curves[name] ?? curves.standard;
        return {
            duration: animations ? Math.round(c[0] / Math.max(0.05, animSpeed)) : 0,
            curve: c[1]
        };
    }

    // ---- internals --------------------------------------------------------
    property var _theme: ({})
    property list<string> _errors: []
    property var _defaults: null
    property var _fileKeys: []
    property bool _fileReady: false
    property string _randomPlanet: "moon"
    property list<string> _knownPlanets: ["earth", "jupiter", "mars", "moon", "neptune", "saturn", "serpulo", "sun", "uranus"]

    function rollPlanet(): void {
        _randomPlanet = _knownPlanets[Math.floor(Math.random() * _knownPlanets.length)];
    }

    function apply(text: string): void {
        if (_defaults === null)
            return;
        const parsed = Conf.parse(text);
        const errs = parsed.errors.slice();

        // Keys that left the file go back to their QML value
        for (const k of _fileKeys)
            if (!(k in parsed.values))
                root[k] = _defaults[k];

        const applied = [];
        for (const k in parsed.values) {
            if (!(k in _defaults)) {
                errs.push(`unknown key "${k.replace(/[A-Z]/g, c => "_" + c.toLowerCase())}"`);
                continue;
            }
            const v = Conf.coerce(parsed.values[k], _defaults[k]);
            if (v === undefined) {
                errs.push(`bad value for "${k}": ${parsed.values[k]}`);
                continue;
            }
            root[k] = v;
            applied.push(k);
        }
        _fileKeys = applied;
        _errors = errs;
        for (const e of errs)
            console.warn(`orbit: ${source}: ${e}`);
        reloaded();
    }

    function reload(): void {
        file.reload();
        themeView.reload();
    }

    readonly property list<string> _configKeys: ["size", "minSize", "maxSize", "padding", "orbitRadius", "tileSize", "ringTileSize", "iconScale", "tileRadius", "searchWidth", "searchHeight", "searchPadding", "showLabels", "planet", "planetsDir", "orbitStyle", "planetSpin", "planetResolution", "vignette", "planetBackground", "idleSpeed", "restPitch", "dragSensitivity", "animations", "animSpeed", "maxFps", "searchOpacity", "placeholder", "fontFamily", "fontSize", "labelFontSize", "iconFontSize", "themeFile", "themeMode", "primary", "surfaceContainer", "textColour", "iconColour", "placeholderColour", "searchColour", "tileColour", "tileOpacity", "labelBackground", "labelOpacity", "labelColour", "maxApps", "favouriteApps", "hiddenApps", "specialPrefix", "launchPrefix", "terminal", "closeOnLaunch", "sortByFrequency", "stateDir", "monitor", "backdropOpacity", "backdropColour", "layer", "namespace", "blur", "blurIgnoreAlpha", "closeOnFocusLoss", "verticalOffset", "iconTheme", "renderer"]

    property FileView _file: FileView {
        id: file

        path: root.expand(root.source)
        watchChanges: root.watchFile
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root._fileReady = true;
            root.apply(text());
        }
        onLoadFailed: err => {
            if (root.source)
                console.warn(`orbit: cannot read config ${root.source} (${FileViewError.toString(err)}), using defaults`);
            root.apply("");
        }
    }

    property FileView _themeView: FileView {
        id: themeView

        path: root.expand(root.themeFile)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = Theme.parse(text(), root.themeMode);
            if (t.error) {
                console.warn(`orbit: ${root.themeFile}: ${t.error}`);
                return;
            }
            root._theme = t;
        }
        onLoadFailed: root._theme = {}
        onPathChanged: if (!path) root._theme = {}
    }

    Component.onCompleted: {
        const d = {};
        for (const k of _configKeys) {
            const v = root[k];
            // Snapshot lists as plain arrays and colours as strings so later writes round-trip
            d[k] = (v && typeof v === "object" && typeof v.length === "number") ? Array.from(v) : (typeof v === "object" && v !== null ? v.toString() : v);
        }
        _defaults = d;
        rollPlanet();
        // The file may have finished loading before the snapshot existed
        if (!source)
            apply("");
        else if (_fileReady)
            apply(file.text());
    }
}
