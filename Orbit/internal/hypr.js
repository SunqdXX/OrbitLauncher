.pragma library

// Shell command that blurs behind the launcher on Hyprland through a runtime
// layerrule (never written to hyprland.conf). Tries the 0.53+ rule syntax
// first, then the legacy one.
function blurCommand(namespace, blur, ignoreAlpha) {
    const ns = String(namespace).replace(/[^A-Za-z0-9_.-]/g, "");
    const on = blur ? 1 : 0;
    const a = Math.max(0, Math.min(1, ignoreAlpha)).toFixed(2);
    const legacy = blur ? `hyprctl keyword layerrule 'blur, ${ns}' >/dev/null; hyprctl keyword layerrule 'ignorealpha ${a}, ${ns}' >/dev/null` : `hyprctl keyword layerrule 'unset, ${ns}' >/dev/null`;
    return `hyprctl keyword layerrule 'blur ${on}, match:namespace ${ns}' | grep -q '^ok' && hyprctl keyword layerrule 'ignore_alpha ${a}, match:namespace ${ns}' >/dev/null || { ${legacy}; }`;
}
