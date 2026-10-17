.pragma library

// Parser for orbit.conf: wofi/kitty style `key = value` lines.
//
//   # comment              (also `;` and trailing ` # ...` after a value)
//   planet = saturn
//   search_opacity = 0.6
//   favourite_apps = firefox, kitty
//   placeholder = "Search, # and all"   (quote to keep # or , literally)
//
// Keys are snake_case in the file and camelCase on OrbitConfig.

function camel(key) {
    return key.trim().toLowerCase().replace(/[-_]+([a-z0-9])/g, (_, c) => c.toUpperCase());
}

// A comment is " #..." after the value; a leading # is part of it (colours)
function stripComment(value) {
    value = value.trim();
    let quote = "";
    for (let i = 0; i < value.length; i++) {
        const c = value[i];
        if (quote) {
            if (c === quote)
                quote = "";
        } else if (c === '"' || c === "'") {
            quote = c;
        } else if (c === "#" && i > 0 && /\s/.test(value[i - 1])) {
            return value.slice(0, i);
        }
    }
    return value;
}

function unquote(s) {
    s = s.trim();
    if (s.length >= 2 && (s[0] === '"' || s[0] === "'") && s[s.length - 1] === s[0])
        return s.slice(1, -1);
    return s;
}

// Split a list on commas that are not inside quotes
function splitList(value) {
    const out = [];
    let cur = "", quote = "";
    for (const c of value) {
        if (quote) {
            if (c === quote)
                quote = "";
            cur += c;
        } else if (c === '"' || c === "'") {
            quote = c;
            cur += c;
        } else if (c === ",") {
            out.push(unquote(cur));
            cur = "";
        } else {
            cur += c;
        }
    }
    if (cur.trim() || out.length)
        out.push(unquote(cur));
    return out.filter(s => s.length > 0);
}

// Turn the raw text into a typed value, using the current default to decide the type
function coerce(raw, current) {
    const s = raw.trim();
    if (Array.isArray(current) || (current && typeof current === "object" && typeof current.length === "number"))
        return s === "" || s === "none" || s === "[]" ? [] : splitList(s);
    if (typeof current === "boolean") {
        const l = s.toLowerCase();
        if (["true", "yes", "on", "1"].includes(l))
            return true;
        if (["false", "no", "off", "0"].includes(l))
            return false;
        return undefined;
    }
    if (typeof current === "number") {
        const l = s.toLowerCase();
        if (l === "auto" || l === "")
            return 0;
        const n = Number(l.replace(/px$|%$/, ""));
        if (isNaN(n))
            return undefined;
        return l.endsWith("%") ? n / 100 : n;
    }
    return unquote(s);
}

// Returns { values: {camelKey: rawString}, errors: [string] }
function parse(text) {
    const values = {};
    const errors = [];
    const lines = (text || "").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line || line.startsWith("#") || line.startsWith(";") || line.startsWith("["))
            continue;
        const eq = line.indexOf("=");
        if (eq <= 0) {
            errors.push(`line ${i + 1}: expected "key = value"`);
            continue;
        }
        values[camel(line.slice(0, eq))] = stripComment(line.slice(eq + 1)).trim();
    }
    return { values, errors };
}

function expandHome(path, home) {
    if (!path)
        return path;
    if (path === "~")
        return home;
    if (path.startsWith("~/"))
        return home + path.slice(1);
    return path.replace(/\$HOME|\$\{HOME\}/g, home);
}
