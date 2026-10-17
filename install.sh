#!/usr/bin/env bash
# Install Orbit.
#
#   ./install.sh                 per-user install into ~/.local (no root needed)
#   sudo ./install.sh --system   system-wide into /usr (also makes `import Orbit` work in every quickshell config)
#   ./install.sh --prefix DIR    any other prefix
#   ./install.sh --uninstall     remove what this script installed (same flags pick the location)
#
# Nothing outside the prefix is touched. Your ~/.config/orbit is created on the
# first run of `orbit`, never by this script.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="$HOME/.local"
qmldir=""
uninstall=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) prefix="/usr"; qmldir="/usr/lib/qt6/qml" ;;
        --prefix) prefix="$2"; shift ;;
        --qml-dir) qmldir="$2"; shift ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; exit 1 ;;
    esac
    shift
done

share="$prefix/share/orbit"
bin="$prefix/bin"

if [[ $uninstall -eq 1 ]]; then
    rm -rf "$share"
    rm -f "$bin/orbit"
    [[ -n "$qmldir" ]] && rm -rf "$qmldir/Orbit"
    rm -f "$prefix/share/licenses/orbit/LICENSE"
    rmdir "$prefix/share/licenses/orbit" 2>/dev/null || true
    echo "Orbit removed from $prefix (your ~/.config/orbit was left alone)"
    exit 0
fi

command -v qs >/dev/null 2>&1 || echo "warning: quickshell (qs) is not installed yet - Orbit needs it to run" >&2

install -d "$share" "$bin"
install -m644 "$src/standalone/shell.qml" "$src/standalone/orbit.conf" "$share/"
rm -rf "$share/Orbit"
cp -r --no-preserve=ownership "$src/Orbit" "$share/Orbit"
find "$share/Orbit" -type d -exec chmod 755 {} + ; find "$share/Orbit" -type f -exec chmod 644 {} +
install -m755 "$src/bin/orbit" "$bin/orbit"
install -Dm644 "$src/LICENSE" "$prefix/share/licenses/orbit/LICENSE"

if [[ -n "$qmldir" ]]; then
    # System-wide QML module, so any quickshell config can just `import Orbit`
    rm -rf "$qmldir/Orbit"
    ln -s "$share/Orbit" "$qmldir/Orbit"
fi

echo "Orbit installed to $prefix"
case ":$PATH:" in
    *":$bin:"*) ;;
    *) echo "note: $bin is not in your PATH - add it, or run $bin/orbit" ;;
esac
cat <<EOF

Next:
  orbit               open it (first run writes ~/.config/orbit/orbit.conf + planets)
  orbit doctor        check everything is in place

Hyprland bind (hyprland.conf):
  bind = SUPER, A, exec, orbit
EOF
