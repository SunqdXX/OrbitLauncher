#!/usr/bin/env bash
# Orbit test suite.
#
#   tests/run.sh            build, unit, CLI, IPC/lifecycle, offscreen renders,
#                           install (nothing appears on screen)
#   tests/run.sh --live     also open real windows: layer-shell, X11 fallback,
#                           quickshell plugin examples
#
# Everything runs in a throwaway directory: your ~/.config, ~/.local/state and
# history are never read or written. ORBIT_BIN=path tests another binary.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live=0
for a in "$@"; do
    case "$a" in
        --live|--all) live=1 ;;
    esac
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/orbit-test.XXXXXX")"
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data"
export XDG_DATA_DIRS="$tmp/sysdata:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export ORBIT_SOCKET="$tmp/orbit.sock" QT_FORCE_STDERR_LOGGING=1
export QS_ICON_THEME="${QS_ICON_THEME:-hicolor}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME/applications/orbit-sub" "$tmp/sysdata/applications"

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32mPASS\e[0m %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  \e[31mFAIL\e[0m %s\n' "$*"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
section() { printf '\n\e[1m%s\e[0m\n' "$*"; }
wait_for() { local i; for i in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.1; done; return 1; }
qml_errors() { grep -E 'TypeError|ReferenceError|Binding loop|is not a type|Cannot (open|assign)|module .* not installed' "$@"; }

# ---- build ------------------------------------------------------------------------
section "build"
orbit="${ORBIT_BIN:-$root/build/orbit}"
if [[ -z "${ORBIT_BIN:-}" ]]; then
    if cmake -S "$root" -B "$root/build" > "$tmp/cmake.log" 2>&1 && cmake --build "$root/build" >> "$tmp/cmake.log" 2>&1; then
        ok "cmake build"
    else
        bad "cmake build"; tail -20 "$tmp/cmake.log"; exit 1
    fi
    check "configure has no warnings" bash -c "! grep -q 'CMake Warning' '$tmp/cmake.log'"
fi
if [[ -z "${ORBIT_BIN:-}" ]]; then
    # What someone without layer-shell-qt gets: must build and run as a plain window
    if cmake -S "$root" -B "$tmp/build-nols" -DORBIT_LAYER_SHELL=OFF > "$tmp/nols.log" 2>&1 && cmake --build "$tmp/build-nols" >> "$tmp/nols.log" 2>&1; then
        ok "build without layer-shell-qt"
        check "no-layer-shell build does not link it" bash -c "! ldd '$tmp/build-nols/orbit' | grep -q LayerShell"
        check "no-layer-shell doctor says so" bash -c "QT_QPA_PLATFORM=offscreen '$tmp/build-nols/orbit' doctor | grep -q 'not built in'"
        ( QT_QPA_PLATFORM=offscreen ORBIT_SOCKET="$tmp/nols.sock" timeout 10 "$tmp/build-nols/orbit" -c /dev/null > "$tmp/nols-run.log" 2>&1 & )
        check "no-layer-shell build opens" wait_for "[ \"\$(ORBIT_SOCKET='$tmp/nols.sock' '$tmp/build-nols/orbit' isopen 2>/dev/null)\" = true ]" 50
        ORBIT_SOCKET="$tmp/nols.sock" "$tmp/build-nols/orbit" kill > /dev/null
    else
        bad "build without layer-shell-qt"; tail -5 "$tmp/nols.log"
    fi
fi
check "qmllint: shared module is clean" bash -c "! /usr/lib/qt6/bin/qmllint '$root'/Orbit/Orbit{Apps,Config,Icon,Popup,Sphere,View}.qml 2>&1 | grep -qE '^(Warning|Error)'"
check "binary has no quickshell dependency" bash -c "! ldd '$orbit' | grep -qi quickshell"
[[ -z "${ORBIT_BIN:-}" ]] && check "quickshell files not embedded" bash -c "! grep -rq 'QuickshellBackend.qml</file>' '$root'/build/.qt/rcc/*.qrc"
pid_of() { pgrep -f "^$orbit( |\$)" | head -n1; }

# ---- fake desktop entries -----------------------------------------------------
desk() { printf '[Desktop Entry]\nType=Application\n%s\n' "$2" > "$XDG_DATA_HOME/applications/$1.desktop"; }
desk orbit-test-a "Name=OrbitAlpha
Exec=sh -c \"echo ok > $tmp/unit/launched-a\""
desk orbit-test-b "Name=OrbitBeta
Exec=true
Keywords=zebrakeyword;
Categories=OrbitCategory;"
desk orbit-test-term "Name=OrbitTerm
Exec=true
Terminal=true"
desk orbit-test-hidden "Name=OrbitHidden
Exec=true"
desk orbit-test-regexhidden "Name=OrbitRegexHidden
Exec=true"
desk orbit-test-nodisplay "Name=OrbitNoDisplay
Exec=true
NoDisplay=true"
desk orbit-test-hiddenkey "Name=OrbitHiddenKey
Exec=true
Hidden=true"
desk orbit-test-tryexec "Name=OrbitTryExec
Exec=true
TryExec=/nonexistent/orbit-binary"
desk orbit-test-onlyshow "Name=OrbitOnlyShow
Exec=true
OnlyShowIn=NoSuchDesktop;"
desk orbit-test-notshow "Name=OrbitNotShow
Exec=true
NotShowIn=NoSuchDesktop;"
desk orbit-test-quoted 'Name=OrbitQuoted
Exec=sh -c "echo \\"hi there\\" \\$HOME" --flag %U'
desk orbit-test-fieldc 'Name=Field C
Exec=printf %c'
desk orbit-sub/nested "Name=OrbitNested
Exec=true"
printf '[Desktop Entry]\nType=Application\nName=WrongBeta\nExec=false\n' > "$tmp/sysdata/applications/orbit-test-b.desktop"

# ---- unit tests (QML) -----------------------------------------------------------
section "unit tests"
mkdir -p "$tmp/unit"
unit_conf() {
    cat > "$tmp/unit/unit.conf" <<'EOF'
planet = saturn
search_opacity = 0.25
favourite_apps = orbit-test-b
primary = #ff00ff
planets_dir = ~/planets-test
hidden_apps = orbit-test-hidden, /^orbit-test-regexhidden$/
launch_prefix = none
bogus_key = 1
EOF
    printf 'search_opacity = 1\nplanet = auto\nhidden_apps = orbit-test-hidden, /^orbit-test-regexhidden$/\nlaunch_prefix = none\n' > "$tmp/unit/unit2.conf"
    rm -rf "$tmp/unit/state" "$tmp/unit/launched-a"
}
unit_report() {
    local log="$1" label="$2"
    grep -oE '(PASS|FAIL) .*' "$log" | grep -v '^PASS$' | while read -r line; do
        case "$line" in PASS*) printf '  \e[32mPASS\e[0m %s: %s\n' "$label" "${line#PASS }" ;; FAIL*) printf '  \e[31mFAIL\e[0m %s: %s\n' "$label" "${line#FAIL }" ;; esac
    done
    local up uf
    up=$(grep -cE 'qml: PASS ' "$log"); uf=$(grep -cE 'qml: FAIL ' "$log")
    grep -q RESULT "$log" || { uf=$((uf + 1)); echo "  $label unit run did not finish:"; grep -vE 'PASS|DEBUG' "$log" | head; }
    if qml_errors "$log" > /dev/null; then uf=$((uf + 1)); echo "  $label QML errors:"; qml_errors "$log" | head -5; fi
    pass=$((pass + up)); fail=$((fail + uf))
}
unit_conf
ORBIT_TEST_DIR="$tmp/unit" ORBIT_MAIN_QML="$root/tests/unit/native.qml" QT_QPA_PLATFORM=offscreen \
    timeout 30 "$orbit" -c "$tmp/unit/unit.conf" daemon -F > "$tmp/unit-native.log" 2>&1
unit_report "$tmp/unit-native.log" native
if command -v qs > /dev/null; then
    unit_conf
    ORBIT_TEST_DIR="$tmp/unit" bash -c "timeout 30 qs -p \"$root/tests/unit\" > \"$tmp/unit-qs.log\" 2>&1; :" 2>/dev/null
    sed -i 's/\x1b\[[0-9;]*m//g' "$tmp/unit-qs.log"
    unit_report "$tmp/unit-qs.log" quickshell
else
    printf '  skip  quickshell plugin unit tests (qs not installed)\n'
fi

# ---- CLI ----------------------------------------------------------------------
section "cli"
check "orbit --version" bash -c "'$orbit' --version | grep -q '^orbit [0-9]'"
check "orbit --help" bash -c "'$orbit' --help | grep -q daemon"
check "unknown command fails" bash -c "! '$orbit' frobnicate 2>/dev/null"
check "-c without a file fails" bash -c "! '$orbit' -c 2>/dev/null"
"$orbit" init > "$tmp/init.log" 2>&1
check "init writes orbit.conf" test -f "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "init copies 9 planets" bash -c "[ \$(ls '$XDG_CONFIG_HOME/orbit/planets' | wc -l) -eq 9 ]"
check "copied planets are byte-identical" bash -c "for f in '$root'/Orbit/planets/*; do cmp -s \"\$f\" '$XDG_CONFIG_HOME/orbit/planets/'\$(basename \"\$f\") || exit 1; done"
check "init points planets_dir at the copy" grep -q "^planets_dir = $XDG_CONFIG_HOME/orbit/planets\$" "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "init keeps the rest of the default config" bash -c "diff <(grep -v '^planets_dir' '$root/config/orbit.conf') <(grep -v '^planets_dir' '$XDG_CONFIG_HOME/orbit/orbit.conf')"
check "init refuses to overwrite" bash -c "'$orbit' init | grep -q 'already exists'"
echo "planet = mars" >> "$XDG_CONFIG_HOME/orbit/orbit.conf"
"$orbit" init -f > /dev/null 2>&1
check "init -f backs up the old config" bash -c "grep -l 'planet = mars' '$XDG_CONFIG_HOME'/orbit/orbit.conf.bak-*"
check "init -f resets the config" bash -c "! grep -q '^planet = mars' '$XDG_CONFIG_HOME/orbit/orbit.conf'"
check "init -f keeps user planets" bash -c "[ \$(ls '$XDG_CONFIG_HOME/orbit/planets' | wc -l) -eq 9 ]"
check "planets lists bundled + custom" bash -c "cp '$root/Orbit/planets/moon.jpg' '$XDG_CONFIG_HOME/orbit/planets/my-planet.jpg' && '$orbit' planets | grep -q my-planet"
check "planets without planets_dir lists built-in" bash -c "echo 'planet = earth' > '$tmp/noplanets.conf' && '$orbit' -c '$tmp/noplanets.conf' planets | grep -q '(built in)'"
QT_QPA_PLATFORM=offscreen "$orbit" doctor > "$tmp/doctor.log" 2>&1
check "doctor runs" grep -q 'layer-shell' "$tmp/doctor.log"
check "doctor finds the config" grep -q "ok  config: $XDG_CONFIG_HOME/orbit/orbit.conf" "$tmp/doctor.log"
check "doctor runs on X11 platform" bash -c "[ -z \"\${DISPLAY:-}\" ] || QT_QPA_PLATFORM=xcb '$orbit' doctor | grep -q 'icon theme'"
check "-c picks another config" bash -c "echo 'icon_theme = Foo' > '$tmp/alt.conf' && QT_QPA_PLATFORM=offscreen '$orbit' -c '$tmp/alt.conf' doctor | grep -q 'icon theme: Foo (orbit.conf)'"
check "-c accepts a relative path" bash -c "cd '$tmp' && QT_QPA_PLATFORM=offscreen '$orbit' -c alt.conf doctor | grep -q 'icon theme: Foo'"
check "ORBIT_ICON_THEME is honoured" bash -c "ORBIT_ICON_THEME=Baz QT_QPA_PLATFORM=offscreen '$orbit' doctor | grep -q 'icon theme: Baz'"
check "icon theme falls back to something installed" bash -c "HOME='$tmp/nohome' XDG_CONFIG_HOME='$tmp/nohome' XDG_CURRENT_DESKTOP= QT_QPA_PLATFORM=offscreen '$orbit' -c /dev/null doctor | grep -qE 'icon theme: .* \\((installed fallback|fallback|gsettings)\\)'"
check "icon theme read from kdeglobals" bash -c "mkdir -p '$tmp/kde' && printf '[Icons]\\nTheme=hicolor\\n' > '$tmp/kde/kdeglobals' && XDG_CONFIG_HOME='$tmp/kde' QT_QPA_PLATFORM=offscreen '$orbit' -c /dev/null doctor | grep -q 'icon theme: hicolor (kdeglobals)'"
check "reload without a running orbit fails cleanly" bash -c "! '$orbit' reload 2>/dev/null"
check "close without a running orbit is harmless" "$orbit" close
check "isopen without a running orbit says false" bash -c "[ \"\$('$orbit' isopen)\" = false ]"
check "kill without a running orbit is harmless" "$orbit" kill
if command -v sqlite3 > /dev/null; then
    mkdir -p "$XDG_STATE_HOME/caelestia"
    sqlite3 "$XDG_STATE_HOME/caelestia/apps.sqlite" "CREATE TABLE apps(id TEXT PRIMARY KEY, frequency INTEGER); INSERT INTO apps VALUES ('firefox', 7), ('kitty', 3), ('unused', 0);"
    "$orbit" import-caelestia > /dev/null 2>&1
    check "import-caelestia writes history" bash -c "python3 -c 'import json,sys; d=json.load(open(\"$XDG_STATE_HOME/orbit/history.json\")); sys.exit(0 if d == {\"firefox\": 7, \"kitty\": 3} else 1)'"
    rm -f "$XDG_STATE_HOME/orbit/history.json"
fi
check "import-caelestia without a db fails cleanly" bash -c "! XDG_STATE_HOME='$tmp/empty' '$orbit' import-caelestia"

# ---- lifecycle over the socket (offscreen: nothing on screen) -------------------------
section "lifecycle (offscreen)"
export QT_QPA_PLATFORM=offscreen
rm -rf "$XDG_CONFIG_HOME/orbit"
"$orbit" > "$tmp/oneshot.log" 2>&1 &
os=$!
check "one-shot starts and answers" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 50
check "first run created the user config" test -f "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "first run copied the planets" test -f "$XDG_CONFIG_HOME/orbit/planets/saturn.jpg"
check "ping says oneshot" bash -c "printf 'ping\\n' | python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(\"$ORBIT_SOCKET\"); s.sendall(b\"ping\\n\"); print(s.recv(64).decode())' | grep -q oneshot"
check "unknown socket command is rejected" bash -c "python3 -c 'import socket; s=socket.socket(socket.AF_UNIX); s.connect(\"$ORBIT_SOCKET\"); s.sendall(b\"rm -rf\\n\"); print(s.recv(64).decode())' | grep -q error"
"$orbit" toggle
check "toggle closes and the one-shot exits" wait_for "! kill -0 $os 2>/dev/null" 40
wait "$os" 2>/dev/null; check "one-shot exit code 0" test $? -eq 0
check "socket removed after exit" test ! -e "$ORBIT_SOCKET"
check "one-shot ran without QML errors" bash -c "! grep -E 'TypeError|ReferenceError|Binding loop|is not a type|Cannot (open|assign)' '$tmp/oneshot.log'"

"$orbit" open > /dev/null 2>&1 &
os=$!
wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 50
"$orbit" close
check "open/close one-shot" wait_for "! kill -0 $os 2>/dev/null" 40

"$orbit" daemon > "$tmp/daemon.log" 2>&1
check "daemon detaches and returns at once" test $? -eq 0
check "daemon is up" wait_for "[ -n \"\$(pid_of)\" ] && '$orbit' isopen >/dev/null; [ \"\$('$orbit' isopen)\" = false ]" 50
dpid="$(pid_of)"
check "daemon starts hidden" bash -c "[ \"\$('$orbit' isopen)\" = false ]"
check "second daemon refused" bash -c "! '$orbit' daemon 2>/dev/null"
"$orbit" open
check "daemon open" wait_for "[ \"\$('$orbit' isopen)\" = true ]" 30
[[ -n "$dpid" ]] && printf '  info  RAM open (software, offscreen): %s MB Pss\n' "$(awk '/^Pss:/{printf "%.0f", $2/1024}' /proc/"$dpid"/smaps_rollup)"
"$orbit" toggle
check "daemon toggle closes" wait_for "[ \"\$('$orbit' isopen)\" = false ]" 30
sleep 1
[[ -n "$dpid" ]] && printf '  info  RAM hidden: %s MB Pss\n' "$(awk '/^Pss:/{printf "%.0f", $2/1024}' /proc/"$dpid"/smaps_rollup)"
check "daemon still alive after close" kill -0 "$dpid"
check "reload reaches the daemon" "$orbit" reload
check "toggle hands over to the daemon (no new process)" bash -c "'$orbit' toggle && sleep 0.3 && [ \$(pgrep -fc '^$orbit( |\$)') -eq 1 ]"
"$orbit" close
check "daemon survives open/close x10" bash -c "for i in \$(seq 10); do '$orbit' open; sleep 0.15; '$orbit' close; sleep 0.15; done; kill -0 $dpid"
"$orbit" kill > /dev/null
check "kill stops the daemon" wait_for "! kill -0 $dpid 2>/dev/null" 30
check "daemon ran without QML errors" bash -c "! grep -E 'TypeError|ReferenceError|Binding loop|is not a type|Cannot (open|assign)' '$tmp/daemon.log'"

python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.bind('$ORBIT_SOCKET')"
check "stale socket file left by a crash" test -S "$ORBIT_SOCKET"
"$orbit" daemon -F > "$tmp/stale.log" 2>&1 &
st=$!
check "daemon takes over a stale socket" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = false ]" 50
"$orbit" kill > /dev/null; wait "$st" 2>/dev/null

echo "renderer = software" > "$tmp/sw.conf"
"$orbit" -c "$tmp/sw.conf" > "$tmp/sw.log" 2>&1 &
sw=$!
check "renderer = software starts" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 50
"$orbit" close; wait_for "! kill -0 $sw 2>/dev/null" 40
check "custom -c config is not auto-initialised" test ! -e "$tmp/orbit"
unset QT_QPA_PLATFORM

# ---- renders (offscreen, software) ------------------------------------------------------
section "render (offscreen; PNGs in $tmp/render)"
mkdir -p "$tmp/render"
rend() {
    local name="$1"; shift
    printf '%s\n' "$@" > "$tmp/render/$name.conf"
    QT_QPA_PLATFORM=offscreen ORBIT_MAIN_QML="$root/tests/render/native.qml" ORBIT_STATE="$tmp/render/state" \
        ORBIT_OUT="$tmp/render/$name.png" ORBIT_SEARCH="${SEARCH:-}" ORBIT_DELAY=1200 ORBIT_SOCKET="$tmp/render.sock" \
        timeout 20 "$orbit" -c "$tmp/render/$name.conf" daemon -F > "$tmp/render/$name.log" 2>&1
    if [[ -s "$tmp/render/$name.png" ]] && grep -q 'ORBIT-ERRORS \[\]' "$tmp/render/$name.log" && ! qml_errors "$tmp/render/$name.log" > /dev/null && ! grep -q 'no planet image' "$tmp/render/$name.log"; then
        ok "render $name"
    else
        bad "render $name"; grep -E 'ERRORS|no planet' "$tmp/render/$name.log" | head -3; qml_errors "$tmp/render/$name.log" | head -3
    fi
}
for p in earth jupiter mars moon neptune saturn serpulo sun uranus; do rend "planet-$p" "planet = $p"; done
rend size-small "size = 420"
rend size-big "size = 900"
rend search-clear "search_opacity = 0"
rend search-solid "search_opacity = 1"
rend rings-forced "planet = earth" "orbit_style = rings"
rend sphere-saturn "planet = saturn" "orbit_style = sphere"
rend no-labels "show_labels = false" "vignette = false"
rend themed "theme_file = $root/tests/fixtures/scheme-red.json" "planet = auto"
rend custom-planet "planets_dir = $root/tests/fixtures" "planet = test-planet.png"
rend user-planets-dir "planets_dir = $XDG_CONFIG_HOME/orbit/planets" "planet = neptune"
SEARCH=orbitalpha rend search-hit
check "search finds the test app" grep -q 'ORBIT-RESULTS 1 OrbitAlpha' "$tmp/render/search-hit.log"
check "bad planet name is reported" bash -c "printf 'planet = nosuchplanet\\n' > '$tmp/render/bad.conf'; QT_QPA_PLATFORM=offscreen ORBIT_MAIN_QML='$root/tests/render/native.qml' ORBIT_OUT='$tmp/render/bad.png' ORBIT_DELAY=800 ORBIT_SOCKET='$tmp/render.sock' timeout 20 '$orbit' -c '$tmp/render/bad.conf' daemon -F 2>&1 | grep -q 'no planet image'"
python3 - "$tmp/render" <<'EOF' && ok "renders differ per planet (textures really load)" || bad "renders differ per planet (textures really load)"
import hashlib, sys, glob
h = {hashlib.md5(open(f, 'rb').read()).hexdigest() for f in glob.glob(sys.argv[1] + '/planet-*.png')}
sys.exit(0 if len(h) == 9 else 1)
EOF

# ---- install / uninstall ------------------------------------------------------------
section "install"
ORBIT_BUILD_DIR="$tmp/build" "$root/install.sh" --prefix "$tmp/prefix" > "$tmp/install.log" 2>&1
check "install.sh exits 0" grep -q "Orbit installed" "$tmp/install.log"
check "installed binary" test -x "$tmp/prefix/bin/orbit"
check "installed binary runs" bash -c "'$tmp/prefix/bin/orbit' --version | grep -q '^orbit '"
check "installed plugin QML" test -f "$tmp/prefix/share/orbit/Orbit/OrbitWindow.qml"
check "installed planets" test -f "$tmp/prefix/share/orbit/Orbit/planets/saturn.jpg"
check "installed default config" test -f "$tmp/prefix/share/orbit/orbit.conf"
check "installed binary is self-contained" bash -c "cd / && HOME='$tmp/h2' XDG_CONFIG_HOME='$tmp/h2/c' '$tmp/prefix/bin/orbit' init | grep -q 'copied 9'"
"$root/install.sh" --prefix "$tmp/prefix" --uninstall > /dev/null 2>&1
check "uninstall removes files" bash -c "[ ! -e '$tmp/prefix/bin/orbit' ] && [ ! -e '$tmp/prefix/share/orbit' ]"

# ---- live: real windows ------------------------------------------------------------
if [[ $live -eq 1 ]]; then
    section "live (windows will appear on screen)"
    layer_up() { hyprctl layers -j 2>/dev/null | jq -e --arg ns "${1:-orbit}" '[.[] | .levels[] | .[] | select(.namespace == $ns)] | length > 0' > /dev/null; }
    "$orbit" > "$tmp/live-oneshot.log" 2>&1 &
    os=$!
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        check "wayland one-shot opens a layer surface" wait_for layer_up 60
    else
        check "wayland one-shot opens" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 60
    fi
    "$orbit" toggle
    check "wayland toggle closes and exits" wait_for "! kill -0 $os 2>/dev/null" 40
    check "wayland run without QML errors" bash -c "! grep -E 'TypeError|ReferenceError|Binding loop|is not a type' '$tmp/live-oneshot.log'"

    ORBIT_NO_LAYER_SHELL=1 "$orbit" > "$tmp/live-nols.log" 2>&1 &
    os=$!
    check "wayland without layer-shell opens a plain window" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 60
    "$orbit" close; wait_for "! kill -0 $os 2>/dev/null" 40

    if [[ -n "${DISPLAY:-}" ]]; then
        QT_QPA_PLATFORM=xcb "$orbit" > "$tmp/live-x11.log" 2>&1 &
        os=$!
        check "X11 fallback opens" wait_for "[ \"\$('$orbit' isopen 2>/dev/null)\" = true ]" 60
        "$orbit" close
        check "X11 fallback closes and exits" wait_for "! kill -0 $os 2>/dev/null" 40
        check "X11 run without QML errors" bash -c "! grep -E 'TypeError|ReferenceError|Binding loop|is not a type' '$tmp/live-x11.log'"
    fi

    if command -v qs > /dev/null; then
        timeout 20 qs -p "$root/examples/plugin-window" > "$tmp/plugin.log" 2>&1 &
        host=$!
        sleep 2
        qs ipc -p "$root/examples/plugin-window" call orbit open > /dev/null 2>&1
        check "plugin OrbitWindow opens via host ipc" wait_for layer_up 40
        qs ipc -p "$root/examples/plugin-window" call orbit close > /dev/null 2>&1
        check "plugin OrbitWindow closes" wait_for '! layer_up' 40
        kill "$host" 2>/dev/null; wait "$host" 2>/dev/null
        check "plugin host loaded without QML errors" bash -c "! grep -E 'ERROR|TypeError|ReferenceError' '$tmp/plugin.log'"
        timeout 4 qs -p "$root/examples/plugin-embed" > "$tmp/embed.log" 2>&1
        check "plugin OrbitView embeds without QML errors" bash -c "grep -q 'Configuration Loaded' '$tmp/embed.log' && ! grep -E 'ERROR|TypeError|ReferenceError' '$tmp/embed.log'"
    fi
fi

section "result"
printf '  %d passed, %d failed   (scratch: %s)\n' "$pass" "$fail" "$tmp"
[[ $fail -eq 0 ]] && [[ "${KEEP:-0}" != 1 ]] && rm -rf "$tmp"
[[ $fail -eq 0 ]]
