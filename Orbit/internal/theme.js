.pragma library

// Reads a colour scheme produced by a theming tool and maps it onto Orbit's
// colour roles. Supported shapes, detected automatically:
//   caelestia  ~/.local/state/caelestia/scheme.json   { colours: { primary: "ccd7ff", ... } }
//   matugen    { colors: { dark: { primary: "#..." } } }  or  { colors: { primary: { dark: "#..." } } }
//   pywal      ~/.cache/wal/colors.json                 { special: {...}, colors: { color0..15 } }
//   flat       { primary: "#...", surface_container: "#...", ... }

function hex(v) {
    if (typeof v !== "string")
        return "";
    v = v.trim();
    if (/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(v))
        return "#" + v;
    return /^#[0-9a-fA-F]{6,8}$/.test(v) ? v : "";
}

// Material You role names, in whatever case style the tool used
function pick(src, names) {
    for (const n of names) {
        const variants = [n, n.replace(/_([a-z])/g, (_, c) => c.toUpperCase()), n.replace(/_/g, "")];
        for (const k of variants)
            if (src[k] !== undefined) {
                const h = hex(typeof src[k] === "object" ? (src[k].dark ?? src[k].default ?? src[k].color) : src[k]);
                if (h)
                    return h;
            }
    }
    return "";
}

function fromMaterial(src) {
    return {
        primary: pick(src, ["primary"]),
        surfaceContainer: pick(src, ["surface_container", "surfaceContainer"]),
        onSurface: pick(src, ["on_surface", "onSurface"]),
        onSurfaceVariant: pick(src, ["on_surface_variant", "onSurfaceVariant"]),
        outline: pick(src, ["outline"]),
        keyColour: pick(src, ["primary_palette_key_color", "primary_paletteKeyColor", "source_color", "primary"])
    };
}

function parse(text, mode) {
    let j;
    try {
        j = JSON.parse(text);
    } catch (e) {
        return { error: "theme file is not valid JSON: " + e.message };
    }
    const scheme = mode === "light" ? "light" : "dark";

    if (j.colours && typeof j.colours === "object")
        return fromMaterial(j.colours);

    if (j.special && j.colors && j.colors.color0) {
        const c = j.colors;
        return {
            primary: hex(c.color4),
            surfaceContainer: hex(c.color0),
            onSurface: hex(j.special.foreground),
            onSurfaceVariant: hex(c.color7),
            outline: hex(c.color8),
            keyColour: hex(c.color4)
        };
    }

    if (j.colors && typeof j.colors === "object") {
        if (j.colors[scheme] && typeof j.colors[scheme] === "object")
            return fromMaterial(j.colors[scheme]);
        // matugen per-colour layout: { primary: { dark: "#..", light: "#.." } }
        const flat = {};
        for (const k in j.colors) {
            const v = j.colors[k];
            flat[k] = typeof v === "object" ? (v[scheme] ?? v.default) : v;
        }
        return fromMaterial(flat);
    }

    return fromMaterial(j);
}

// Picks a planet from a colour's hue. This is the hue half of the original
// launcher's picker (the wallpaper-analysis tie-breakers need a C++ plugin).
function planetForColour(c) {
    const kh = c.hslHue * 360;
    const ks = c.hslSaturation;
    const kl = c.hslLightness;

    if (ks < 0.12 || kh < 0)
        return "moon";
    if (kh >= 32 && kh < 90 && ks < 0.42)
        return "saturn";
    if (kh >= 70 && kh < 190)
        return "earth";
    if (kh >= 250 && kh < 330 && kl < 0.2)
        return "serpulo";
    if (kh >= 190 && kh < 270)
        return kl >= 0.42 ? "uranus" : "neptune";
    if (kh < 32 || kh >= 345)
        return "sun";
    if (kh < 70)
        return "mars";
    return kh < 300 ? "neptune" : "sun";
}
