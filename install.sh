#!/usr/bin/env bash
# Build and install Orbit.
#
#   ./install.sh                 per-user install into ~/.local (no root needed)
#   sudo ./install.sh --system   system-wide into /usr (also makes `import Orbit` work in every quickshell config)
#   ./install.sh --prefix DIR    any other prefix
#   ./install.sh --uninstall     remove what this script installed (same flags pick the location)
#
# Needs cmake, a C++17 compiler and Qt 6 (qt6-base qt6-declarative qt6-svg
# qt6-wayland). layer-shell-qt is optional but recommended on Wayland.
# Nothing outside the prefix is touched. Your ~/.config/orbit is created on the
# first run of `orbit`, never by this script.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="$HOME/.local"
qmldir=""
uninstall=0
build="${ORBIT_BUILD_DIR:-$src/build}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) prefix="/usr"; qmldir="/usr/lib/qt6/qml" ;;
        --prefix) prefix="$2"; shift ;;
        --qml-dir) qmldir="$2"; shift ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ $uninstall -eq 1 ]]; then
    rm -f "$prefix/bin/orbit"
    rm -rf "$prefix/share/orbit"
    [[ -n "$qmldir" && -L "$qmldir/Orbit" ]] && rm -f "$qmldir/Orbit"
    rm -f "$prefix/share/licenses/orbit/LICENSE"
    rmdir "$prefix/share/licenses/orbit" 2>/dev/null || true
    echo "Orbit removed from $prefix (your ~/.config/orbit was left alone)"
    exit 0
fi

for tool in cmake c++; do
    command -v "$tool" >/dev/null 2>&1 || { echo "install.sh: $tool is missing (Arch/Artix: pacman -S --needed base-devel cmake)" >&2; exit 1; }
done

gen=()
command -v ninja >/dev/null 2>&1 && gen=(-G Ninja)
[[ -f "$build/CMakeCache.txt" ]] && gen=()
if ! cmake -S "$src" -B "$build" "${gen[@]}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix"; then
    echo "install.sh: configure failed. Arch/Artix: pacman -S --needed qt6-base qt6-declarative qt6-svg qt6-wayland layer-shell-qt" >&2
    exit 1
fi
cmake --build "$build" --parallel
cmake --install "$build" --prefix "$prefix" > /dev/null
install -Dm644 "$src/LICENSE" "$prefix/share/licenses/orbit/LICENSE"

if [[ -n "$qmldir" ]]; then
    # System-wide QML module, so any quickshell config can just `import Orbit`
    rm -f "$qmldir/Orbit"
    ln -s "$prefix/share/orbit/Orbit" "$qmldir/Orbit"
fi

echo "Orbit installed to $prefix"
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "note: $prefix/bin is not in your PATH - add it, or run $prefix/bin/orbit" ;;
esac
cat <<EOT

Next:
  orbit               open it (first run writes ~/.config/orbit/orbit.conf + planets)
  orbit doctor        check everything is in place

Bind it to a key, e.g. Hyprland:  bind = SUPER, A, exec, orbit
KDE: System Settings > Shortcuts > Add Command > orbit
EOT
