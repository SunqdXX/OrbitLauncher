pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "internal/fzf.js" as Fzf

// Desktop entries, launch history, search and launching.
QtObject {
    id: root

    required property OrbitConfig config

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
        return DesktopEntries.applications.values.filter(a => !a.noDisplay && !hidden.some(h => typeof h === "string" ? h === a.id : h.test(a.id)));
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
            return Quickshell.env("UWSM_FINALIZE_VARNAMES") ? ["uwsm", "app", "--"] : [];
        if (lp.length === 1 && lp[0] === "none")
            return [];
        return lp;
    }

    function terminalCommand(): list<string> {
        const t = Array.from(config.terminal);
        if (t.length)
            return t;
        const env = Quickshell.env("TERMINAL");
        return env ? env.split(" ").filter(s => s) : ["kitty"];
    }

    function launch(entry: DesktopEntry): void {
        if (!entry)
            return;
        const f = Object.assign({}, frequency);
        f[entry.id] = (f[entry.id] ?? 0) + 1;
        frequency = f;
        history.setText(JSON.stringify(f));

        const cmd = entry.runInTerminal ? [...terminalCommand(), ...entry.command] : [...entry.command];
        Quickshell.execDetached({
            command: [...launchPrefix(), ...cmd],
            workingDirectory: entry.workingDirectory || Quickshell.env("HOME")
        });
    }

    property FileView _history: FileView {
        id: history

        path: `${root.config.resolvedStateDir}/history.json`
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (j && typeof j === "object")
                    root.frequency = j;
            } catch (e) {
                console.warn("orbit: history.json is corrupt, starting fresh");
            }
        }
        onLoadFailed: err => {
            // First run: make sure the directory exists so the first launch can be saved
            if (err === FileViewError.FileNotFound)
                Quickshell.execDetached(["mkdir", "-p", root.config.resolvedStateDir]);
        }
    }
}
