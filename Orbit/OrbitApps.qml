pragma ComponentBehavior: Bound

import QtQuick
import "internal/fzf.js" as Fzf

// Desktop entries, launch history, search and launching.
QtObject {
    id: root

    required property OrbitConfig config
    readonly property var backend: config.backend

    // id -> launch count, persisted in <stateDir>/history.json
    property var frequency: ({})

    readonly property var entries: {
        const hidden = config.hiddenApps.map(h => {
            if (h.length > 2 && h.startsWith("/") && h.endsWith("/"))
                try {
                    return new RegExp(h.slice(1, -1), "i");
                } catch (e) {
                    console.warn(`orbit: bad hidden_apps regex ${h}`);
                }
            return h.replace(/\.desktop$/, "");
        });
        return (backend ? backend.apps : []).filter(a => !a.noDisplay && !hidden.some(h => typeof h === "string" ? h === a.id : h.test(a.id)));
    }

    // Favourites first, then most launched, then by name: the order the orbit fills in
    readonly property var sorted: {
        const fav = config.favouriteApps.map(f => f.replace(/\.desktop$/, ""));
        const freq = frequency;
        const byFreq = config.sortByFrequency;
        return entries.slice().sort((a, b) => {
            const fa = fav.indexOf(a.id), fb = fav.indexOf(b.id);
            if (fa !== fb)
                return (fa < 0 ? Infinity : fa) - (fb < 0 ? Infinity : fb);
            if (byFreq) {
                const d = (freq[b.id] ?? 0) - (freq[a.id] ?? 0);
                if (d !== 0)
                    return d;
            }
            return a.name.localeCompare(b.name);
        });
    }

    readonly property var _finders: ({})

    function finder(keyList: var): var {
        const id = keyList.join(",");
        let f = _finders[id];
        if (!f || f.list !== sorted) {
            f = {
                list: sorted,
                fzf: new Fzf.Finder(sorted, {
                    selector: item => keyList.map(k => {
                        const v = item[k];
                        return v && typeof v === "object" && v.length !== undefined ? Array.from(v).join(" ") : (v ?? "");
                    }).join(" ")
                })
            };
            _finders[id] = f;
        }
        return f;
    }

    function query(text: string, keyList: var): var {
        text = text.trim().replace(/\s+/g, " ");
        if (!text)
            return sorted.slice();
        const f = finder(keyList);
        return f.fzf.find(text).sort((a, b) => {
            if (a.score === b.score)
                return (a.item.name ?? "").trim().length - (b.item.name ?? "").trim().length;
            return b.score - a.score;
        }).map(r => r.item);
    }

    // Same prefixes as the caelestia launcher: ">i " id, ">c " categories,
    // ">d " description, ">e " exec, ">w " window class, ">g " generic name,
    // ">k " keywords, ">t " terminal apps only
    function search(text: string): var {
        const p = config.specialPrefix;
        const modes = {
            i: ["id", "name"],
            c: ["categories", "name"],
            d: ["comment", "name"],
            e: ["execString", "name"],
            w: ["startupClass", "name"],
            g: ["genericName", "name"],
            k: ["keywords", "name"],
            t: ["name"]
        };
        if (p && text.startsWith(p) && text.length >= p.length + 2 && text[p.length + 1] === " ") {
            const m = text[p.length];
            if (modes[m]) {
                const res = query(text.slice(p.length + 2), modes[m]);
                return m === "t" ? res.filter(a => a.runInTerminal) : res;
            }
        }
        return query(text, ["name"]);
    }

    function launchPrefix(): list<string> {
        const lp = Array.from(config.launchPrefix);
        if (lp.length === 1 && lp[0] === "auto")
            return backend.env("UWSM_FINALIZE_VARNAMES") ? ["uwsm", "app", "--"] : [];
        if (lp.length === 1 && lp[0] === "none")
            return [];
        return lp;
    }

    function terminalCommand(): list<string> {
        const t = Array.from(config.terminal);
        if (t.length)
            return t;
        const env = backend.env("TERMINAL");
        return env ? env.split(" ").filter(s => s) : ["kitty"];
    }

    readonly property string historyPath: `${config.resolvedStateDir}/history.json`

    function launch(entry: var): void {
        if (!entry || !backend)
            return;
        const f = Object.assign({}, frequency);
        f[entry.id] = (f[entry.id] ?? 0) + 1;
        frequency = f;
        backend.writeFile(historyPath, JSON.stringify(f));

        const cmd = entry.runInTerminal ? [...terminalCommand(), ...entry.command] : [...entry.command];
        backend.exec([...launchPrefix(), ...cmd], entry.workingDirectory || backend.env("HOME"));
    }

    function loadHistory(): void {
        if (!backend)
            return;
        const text = backend.readFile(historyPath);
        if (!text) {
            // First run: create the directory so the first launch can be saved
            backend.mkdirs(config.resolvedStateDir);
            frequency = {};
            return;
        }
        try {
            const j = JSON.parse(text);
            frequency = j && typeof j === "object" ? j : {};
        } catch (e) {
            console.warn("orbit: history.json is corrupt, starting fresh");
            frequency = {};
        }
    }

    // Deferred: these can fire while `sorted` is being evaluated during creation
    onHistoryPathChanged: Qt.callLater(loadHistory)
    onBackendChanged: Qt.callLater(loadHistory)
    Component.onCompleted: Qt.callLater(loadHistory)
}
