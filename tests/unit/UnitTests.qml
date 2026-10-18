// Unit tests: config parser, theme files, planet picker, search, sorting,
// launching. Backend-agnostic: native.qml runs them inside the orbit binary,
// shell.qml inside quickshell. tests/run.sh sets ORBIT_TEST_DIR (a scratch
// directory) and XDG_DATA_HOME (fake desktop entries).

import QtQuick
import "Orbit"
import "Orbit/internal/conf.js" as Conf
import "Orbit/internal/theme.js" as Theme

Item {
    id: t

    required property var backend
    signal done

    readonly property string dir: backend.env("ORBIT_TEST_DIR")
    property int passed: 0
    property int failed: 0

    function eq(name, got, want) {
        const g = JSON.stringify(got), w = JSON.stringify(want);
        if (g === w) {
            passed++;
            console.log(`PASS ${name}`);
        } else {
            failed++;
            console.log(`FAIL ${name}: got ${g}, want ${w}`);
        }
    }
    function ok(name, cond, info) {
        eq(name + (cond ? "" : ` (${info ?? ""})`), !!cond, true);
    }

    function finish() {
        console.log(`RESULT ${t.backend.kind}: ${passed} passed, ${failed} failed`);
        done();
    }

    // ---- pure parser tests --------------------------------------------------
    function parserTests() {
        const p = Conf.parse(`
# comment
; also a comment
planet = saturn
search_opacity = 0.5   # trailing comment
label_background = #0a0b14
label_colour = #e6e7f0 # with comment
placeholder = "Find, # anything"
favourite_apps = firefox, kitty , "a,b"
hidden_apps =
size = auto
Max-Apps = 12
broken line
`);
        eq("parse planet", p.values.planet, "saturn");
        eq("parse trailing comment", p.values.searchOpacity, "0.5");
        eq("parse leading # colour", p.values.labelBackground, "#0a0b14");
        eq("parse colour + comment", p.values.labelColour, "#e6e7f0");
        eq("parse quoted # and ,", Conf.coerce(p.values.placeholder, ""), "Find, # anything");
        eq("parse list", Conf.coerce(p.values.favouriteApps, []), ["firefox", "kitty", "a,b"]);
        eq("parse empty list", Conf.coerce(p.values.hiddenApps, []), []);
        eq("parse auto number", Conf.coerce(p.values.size, 0), 0);
        eq("parse key case/dashes", p.values.maxApps, "12");
        eq("parse error reported", p.errors.length, 1);
        eq("coerce bool yes", Conf.coerce("yes", false), true);
        eq("coerce bool off", Conf.coerce("off", true), false);
        eq("coerce bool junk", Conf.coerce("maybe", true), undefined);
        eq("coerce number junk", Conf.coerce("abc", 1), undefined);
        eq("coerce px", Conf.coerce("600px", 0), 600);
        eq("coerce percent", Conf.coerce("60%", 0), 0.6);
        eq("coerce none list", Conf.coerce("none", ["auto"]), []);
        eq("expand ~", Conf.expandHome("~/x", "/home/u"), "/home/u/x");
        eq("expand $HOME", Conf.expandHome("$HOME/y", "/home/u"), "/home/u/y");
    }

    function themeTests() {
        const cae = Theme.parse(JSON.stringify({ name: "dynamic", colours: { primary: "ccd7ff", surfaceContainer: "17191f", onSurface: "e3e5f0", onSurfaceVariant: "a9abb5", outline: "73757f", primary_paletteKeyColor: "68779b" } }));
        eq("theme caelestia primary", cae.primary, "#ccd7ff");
        eq("theme caelestia key", cae.keyColour, "#68779b");
        eq("theme caelestia surface", cae.surfaceContainer, "#17191f");

        const mat2 = Theme.parse(JSON.stringify({ colors: { dark: { primary: "#aabbcc", surface_container: "#111111", on_surface: "#eeeeee" }, light: { primary: "#000000" } } }));
        eq("theme matugen dark", mat2.primary, "#aabbcc");
        eq("theme matugen snake", mat2.surfaceContainer, "#111111");
        const mat2l = Theme.parse(JSON.stringify({ colors: { dark: { primary: "#aabbcc" }, light: { primary: "#010203" } } }), "light");
        eq("theme matugen light mode", mat2l.primary, "#010203");

        const mat3 = Theme.parse(JSON.stringify({ colors: { primary: { dark: "#123456", light: "#654321" }, on_surface: { dark: "#fafafa" } } }));
        eq("theme matugen per-colour", mat3.primary, "#123456");
        eq("theme matugen per-colour 2", mat3.onSurface, "#fafafa");

        const wal = Theme.parse(JSON.stringify({ special: { background: "#000000", foreground: "#ffffff" }, colors: { color0: "#101010", color4: "#3355ff", color7: "#cccccc", color8: "#777777" } }));
        eq("theme pywal primary", wal.primary, "#3355ff");
        eq("theme pywal text", wal.onSurface, "#ffffff");

        const flat = Theme.parse(JSON.stringify({ primary: "#ff0000", surfaceContainer: "#00ff00" }));
        eq("theme flat", [flat.primary, flat.surfaceContainer], ["#ff0000", "#00ff00"]);

        ok("theme bad json", !!Theme.parse("{nope").error);
    }

    function planetTests() {
        eq("planet grey -> moon", Theme.planetForColour(Qt.color("#808080")), "moon");
        eq("planet green -> earth", Theme.planetForColour(Qt.color("#2fa84f")), "earth");
        eq("planet light blue -> uranus", Theme.planetForColour(Qt.color("#7fb2ff")), "uranus");
        eq("planet dark blue -> neptune", Theme.planetForColour(Qt.color("#102a66")), "neptune");
        eq("planet red -> sun", Theme.planetForColour(Qt.color("#e03020")), "sun");
        eq("planet orange -> mars", Theme.planetForColour(Qt.color("#e08a20")), "mars");
        eq("planet beige -> saturn", Theme.planetForColour(Qt.color("#b8a982")), "saturn");
        eq("planet dark purple -> serpulo", Theme.planetForColour(Qt.color("#2a0f40")), "serpulo");
    }

    // ---- config object tests (file loading, hot reload) ------------------------
    OrbitConfig {
        id: cfg

        backend: t.backend
        source: t.dir + "/unit.conf"
        stateDir: t.dir + "/state"
        planet: "earth"      // QML value: restored when the file stops setting it
        maxApps: 30
    }

    OrbitApps {
        id: apps

        config: cfg
    }

    property int stage: 0

    function configTests() {
        eq("config file overrides QML", cfg.planet, "saturn");
        eq("config number", cfg.searchOpacity, 0.25);
        eq("config list", Array.from(cfg.favouriteApps), ["orbit-test-b"]);
        eq("config QML value kept", cfg.maxApps, 30);
        eq("config rings for saturn", cfg.resolvedOrbitStyle, "rings");
        ok("config unknown key reported", cfg.errors.some(e => e.includes("bogus_key")), JSON.stringify(cfg.errors));
        eq("config search alpha", Number(cfg.cSearch.a.toFixed(2)), 0.25);
        eq("config explicit colour", cfg.cPrimary.toString(), "#ff00ff");
        eq("config tilde expand", cfg.resolvedPlanetsUrl, "file://" + t.backend.env("HOME") + "/planets-test");
        // Rewrite the file without planet/primary: QML values must come back
        stage = 1;
        // Like an editor: write a temp file and rename it over (own writes are not reported)
        t.backend.exec(["sh", "-c", "cp unit2.conf unit.conf.tmp && mv unit.conf.tmp unit.conf"], t.dir);
    }

    function reloadTests() {
        eq("reload picks up change", cfg.searchOpacity, 1);
        eq("reload removed key restored", cfg.cPrimary.toString(), "#ccd7ff");
        eq("reload auto planet from primary", cfg.resolvedPlanet, "uranus");
        eq("reload favourites restored", Array.from(cfg.favouriteApps), []);
        stage = 2;
        searchTests();
    }

    function searchTests() {
        const ids = apps.entries.map(e => e.id);
        ok("entries include test apps", ids.includes("orbit-test-a") && ids.includes("orbit-test-b"), ids.length);
        ok("hidden app filtered", !ids.includes("orbit-test-hidden"));
        ok("hidden regex filtered", !ids.includes("orbit-test-regexhidden"));
        ok("NoDisplay filtered", !ids.includes("orbit-test-nodisplay"));
        if (t.backend.kind === "native") {
            // Desktop entry spec details the native parser handles itself
            ok("Hidden=true filtered", !ids.includes("orbit-test-hiddenkey"));
            ok("TryExec missing filtered", !ids.includes("orbit-test-tryexec"));
            ok("OnlyShowIn other desktop filtered", !ids.includes("orbit-test-onlyshow"));
            ok("NotShowIn other desktop kept", ids.includes("orbit-test-notshow"));
            ok("subdir id uses dashes", ids.includes("orbit-sub-nested"), ids.filter(i => i.startsWith("orbit-")));
            const q = apps.entries.find(e => e.id === "orbit-test-quoted");
            eq("Exec quoting and field codes", q ? Array.from(q.command) : null, ["sh", "-c", "echo \"hi there\" $HOME", "--flag"]);
            eq("Exec %c becomes the name", (apps.entries.find(e => e.id === "orbit-test-fieldc")?.command ?? []).slice(-1), ["Field C"]);
            eq("user entry overrides system id", apps.entries.filter(e => e.id === "orbit-test-b").map(e => e.name), ["OrbitBeta"]);
        }

        const r = apps.search("orbitalpha");
        eq("search by name", r[0]?.id, "orbit-test-a");
        eq("search fuzzy", apps.search("orbtalph")[0]?.id, "orbit-test-a");
        eq("search >k keywords", apps.search(">k zebrakeyword")[0]?.id, "orbit-test-b");
        eq("search >c categories", apps.search(">c orbitcategory")[0]?.id, "orbit-test-b");
        eq("search >t terminal only", apps.search(">t orbit").map(a => a.id).filter(i => i.startsWith("orbit-test")), ["orbit-test-term"]);
        eq("search empty returns all", apps.search("").length, apps.entries.length);
        eq("search no match", apps.search("zzzzqqqqxxxx").length, 0);

        eq("launch prefix none", apps.launchPrefix(), []);
        cfg.launchPrefix = ["uwsm", "app", "--"];
        eq("launch prefix custom", apps.launchPrefix(), ["uwsm", "app", "--"]);
        cfg.launchPrefix = ["none"];
        cfg.terminal = ["foot"];
        eq("terminal custom", apps.terminalCommand(), ["foot"]);

        // Launch a real entry: its Exec touches a marker file
        const a = apps.entries.find(e => e.id === "orbit-test-a");
        apps.launch(a);
        apps.launch(a);
        eq("frequency counted", apps.frequency["orbit-test-a"], 2);
        eq("frequent app sorts first", apps.sorted.filter(e => e.id.startsWith("orbit-test"))[0].id, "orbit-test-a");
        cfg.favouriteApps = ["orbit-test-b"];
        eq("favourite beats frequency", apps.sorted[0].id, "orbit-test-b");
        cfg.favouriteApps = [];
        checkLaunch.start();
    }

    Timer {
        id: checkLaunch

        interval: 800
        onTriggered: {
            const marker = t.backend.readFile(t.dir + "/launched-a");
            const hist = t.backend.readFile(t.dir + "/state/history.json");
            ok("launch ran the Exec line", marker.includes("ok"), marker);
            ok("history.json written", hist.replace(/\s/g, "").includes("\"orbit-test-a\":2"), hist);
            t.finish();
        }
    }

    Connections {
        target: cfg
        function onReloaded() {
            if (t.stage === 0 && cfg.planet === "saturn")
                Qt.callLater(t.configTests);
            else if (t.stage === 1 && cfg.searchOpacity === 1)
                Qt.callLater(t.reloadTests);
        }
    }

    Timer {
        // Safety net so a hung test never blocks the suite
        running: true
        interval: 15000
        onTriggered: {
            console.log(`FAIL timeout at stage ${t.stage}`);
            t.failed++;
            t.finish();
        }
    }

    Component.onCompleted: {
        parserTests();
        themeTests();
        planetTests();
        // If the file finished loading before Connections existed
        if (cfg.planet === "saturn" && stage === 0)
            Qt.callLater(configTests);
    }
}
