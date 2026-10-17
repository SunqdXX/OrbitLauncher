#!/usr/bin/env bash
# Orbit test suite.
#
#   tests/run.sh            unit + CLI + install tests (nothing appears on screen)
#   tests/run.sh --live     also open the real launcher / daemon / plugin windows
#   tests/run.sh --render   also render every planet/style to PNGs (background layer)
#
# Everything runs in a throwaway directory: your ~/.config, ~/.local/state and
# history are never read or written.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live=0 render=0
for a in "$@"; do
    case "$a" in
        --live) live=1 ;;
        --render) render=1 ;;
        --all) live=1; render=1 ;;
    esac
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/orbit-test.XXXXXX")"
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data"
export QS_ICON_THEME="${QS_ICON_THEME:-hicolor}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME/applications"

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32mPASS\e[0m %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf '  \e[31mFAIL\e[0m %s\n' "$*"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
section() { printf '\n\e[1m%s\e[0m\n' "$*"; }

orbit="$root/bin/orbit"
share="$root/standalone"
qs_pid() { pgrep -f "^qs -p $share" | head -n1; }
wait_for() { local i; for i in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.1; done; return 1; }
layer_up() { hyprctl layers -j 2>/dev/null | jq -e --arg ns "${1:-orbit}" '[.[] | .levels[] | .[] | select(.namespace == $ns)] | length > 0' >/dev/null; }

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

# ---- unit tests (QML) -----------------------------------------------------------
section "unit tests"
mkdir -p "$tmp/unit"
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
ORBIT_TEST_DIR="$tmp/unit" timeout 30 qs -p "$root/tests/unit" > "$tmp/unit.log" 2>&1
grep -E 'PASS|FAIL' "$tmp/unit.log" | sed -E 's/.*qml.*: (PASS|FAIL)/\1/' | while read -r line; do
    case "$line" in PASS*) printf '  \e[32mPASS\e[0m %s\n' "${line#PASS }" ;; FAIL*) printf '  \e[31mFAIL\e[0m %s\n' "${line#FAIL }" ;; esac
done
u_pass=$(grep -c ' PASS ' "$tmp/unit.log"); u_fail=$(grep -c ' FAIL ' "$tmp/unit.log")
grep -q RESULT "$tmp/unit.log" || { u_fail=$((u_fail + 1)); echo "  unit run did not finish:"; grep -vE 'INFO|PASS|DEBUG' "$tmp/unit.log" | head; }
pass=$((pass + u_pass)); fail=$((fail + u_fail))
grep -E 'ERROR|TypeError|ReferenceError' "$tmp/unit.log" | grep -v 'orbit:' | head -5

# ---- CLI ----------------------------------------------------------------------
section "cli"
check "orbit --version" bash -c "'$orbit' --version | grep -q '^orbit '"
check "orbit --help" bash -c "'$orbit' --help | grep -q daemon"
check "unknown command fails" bash -c "! '$orbit' frobnicate"
"$orbit" init > "$tmp/init.log" 2>&1
check "init writes orbit.conf" test -f "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "init copies 9 planets" bash -c "[ \$(ls '$XDG_CONFIG_HOME/orbit/planets' | wc -l) -eq 9 ]"
check "init points planets_dir at the copy" grep -q "^planets_dir = $XDG_CONFIG_HOME/orbit/planets" "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "init refuses to overwrite" bash -c "'$orbit' init | grep -q 'already exists'"
echo "planet = mars" >> "$XDG_CONFIG_HOME/orbit/orbit.conf"
"$orbit" init -f > /dev/null 2>&1
check "init -f backs up the old config" bash -c "grep -l 'planet = mars' '$XDG_CONFIG_HOME'/orbit/orbit.conf.bak-* "
check "init -f keeps user planets" bash -c "[ \$(ls '$XDG_CONFIG_HOME/orbit/planets' | wc -l) -eq 9 ]"
check "planets lists bundled + custom" bash -c "cp '$root/Orbit/planets/moon.jpg' '$XDG_CONFIG_HOME/orbit/planets/my-planet.jpg' && '$orbit' planets | grep -q my-planet"
check "doctor runs" bash -c "'$orbit' doctor | grep -q quickshell"
check "-c picks another config" bash -c "echo 'icon_theme = Foo' > '$tmp/alt.conf' && '$orbit' -c '$tmp/alt.conf' doctor | grep -q 'icon theme: Foo'"
check "icon theme read from config" bash -c "echo 'icon_theme = Bar' >> '$XDG_CONFIG_HOME/orbit/orbit.conf' && '$orbit' doctor | grep -q 'icon theme: Bar'"
sed -i '/^icon_theme = Bar/d' "$XDG_CONFIG_HOME/orbit/orbit.conf"
check "reload without daemon fails cleanly" bash -c "! '$orbit' reload 2>/dev/null"
check "kill without daemon is harmless" "$orbit" kill
if command -v sqlite3 >/dev/null; then
    mkdir -p "$XDG_STATE_HOME/caelestia"
    sqlite3 "$XDG_STATE_HOME/caelestia/apps.sqlite" "CREATE TABLE apps(id TEXT PRIMARY KEY, frequency INTEGER); INSERT INTO apps VALUES ('firefox', 7), ('kitty', 3), ('unused', 0);"
    "$orbit" import-caelestia > /dev/null 2>&1
    check "import-caelestia writes history" bash -c "python3 -c 'import json,sys; d=json.load(open(\"$XDG_STATE_HOME/orbit/history.json\")); sys.exit(0 if d == {\"firefox\": 7, \"kitty\": 3} else 1)'"
fi

# ---- install / uninstall ------------------------------------------------------------
section "install"
"$root/install.sh" --prefix "$tmp/prefix" > "$tmp/install.log" 2>&1
check "install.sh exits 0" grep -q "Orbit installed" "$tmp/install.log"
check "installed binary" test -x "$tmp/prefix/bin/orbit"
check "installed QML" test -f "$tmp/prefix/share/orbit/Orbit/OrbitWindow.qml"
check "installed planets" test -f "$tmp/prefix/share/orbit/Orbit/planets/saturn.jpg"
check "installed binary finds its QML" bash -c "'$tmp/prefix/bin/orbit' doctor | grep -q 'QML files: $tmp/prefix/share/orbit'"
"$root/install.sh" --prefix "$tmp/prefix" --uninstall > /dev/null 2>&1
check "uninstall removes files" bash -c "[ ! -e '$tmp/prefix/bin/orbit' ] && [ ! -e '$tmp/prefix/share/orbit' ]"

# ---- live: real windows ------------------------------------------------------------
if [[ $live -eq 1 ]]; then
    section "live (windows will flash on screen)"
    "$orbit" kill > /dev/null 2>&1
    "$orbit" > "$tmp/oneshot.log" 2>&1 &
    check "one-shot opens a layer surface" wait_for layer_up 60
    check "one-shot answers ipc" bash -c "qs ipc -p '$share' call orbit isOpen | grep -q true"
    "$orbit" toggle
    check "toggle closes and the process exits" wait_for '[ -z "$(qs_pid)" ]' 40
    grep -E 'ERROR|TypeError|ReferenceError|Cannot open' "$tmp/oneshot.log" | grep -v 'Could not load icon' | head -3

    "$orbit" daemon > "$tmp/daemon.log" 2>&1
    check "daemon starts" wait_for '[ -n "$(qs_pid)" ]' 50
    check "daemon starts hidden" bash -c "! hyprctl layers -j | jq -e '[.[] | .levels[] | .[] | select(.namespace == \"orbit\")] | length > 0'"
    check "second daemon refused" bash -c "! '$orbit' daemon 2>/dev/null"
    "$orbit" open
    check "daemon open shows the launcher" wait_for layer_up 40
    pid="$(qs_pid)"
    [[ -n "$pid" ]] && printf '  info  RAM while open: %s MB (Pss)\n' "$(awk '/^Pss:/{printf "%.0f", $2/1024}' /proc/"$pid"/smaps_rollup)"
    "$orbit" close
    check "daemon close removes the surface" wait_for '! layer_up' 40
    sleep 1
    [[ -n "$pid" ]] && printf '  info  RAM while hidden: %s MB (Pss)\n' "$(awk '/^Pss:/{printf "%.0f", $2/1024}' /proc/"$pid"/smaps_rollup)"
    "$orbit" toggle
    check "daemon toggle reopens" wait_for layer_up 40
    sed -i 's/^planet = .*/planet = jupiter/' "$XDG_CONFIG_HOME/orbit/orbit.conf"
    check "daemon reload" "$orbit" reload
    "$orbit" toggle
    wait_for '! layer_up' 40
    check "daemon survives open/close x5" bash -c "for i in 1 2 3 4 5; do '$orbit' open; sleep 0.4; '$orbit' close; sleep 0.7; done; [ -n \"\$(pgrep -f '^qs -p $share')\" ]"
    "$orbit" kill > /dev/null
    check "kill stops the daemon" wait_for '[ -z "$(qs_pid)" ]' 30
    grep -E 'ERROR|TypeError|ReferenceError|Cannot open' "$tmp/daemon.log" | grep -v 'Could not load icon' | head -3

    # Plugin mode: a host quickshell config that imports the module
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

# ---- render: PNG per variant ----------------------------------------------------------
if [[ $render -eq 1 ]]; then
    section "render (flashes on screen, input passes through; PNGs in $tmp/render)"
    mkdir -p "$tmp/render"
    rend() {
        local name="$1"; shift
        printf '%s\n' "$@" > "$tmp/render/$name.conf"
        ( ORBIT_CONFIG="$tmp/render/$name.conf" ORBIT_STATE="$tmp/render/state" ORBIT_OUT="$tmp/render/$name.png" ORBIT_SEARCH="${SEARCH:-}" \
            timeout 20 qs -p "$root/tests/render" > "$tmp/render/$name.log" 2>&1 ) 2>/dev/null
        if [[ -s "$tmp/render/$name.png" ]] && grep -q 'ORBIT-ERRORS \[\]' "$tmp/render/$name.log" && ! grep -qE 'TypeError|ReferenceError|Cannot open' "$tmp/render/$name.log"; then
            ok "render $name"
        else
            bad "render $name"; grep -E 'ERRORS|TypeError|ReferenceError|Cannot open' "$tmp/render/$name.log" | head -3
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
    SEARCH=fire rend search-fire
    printf '  info  PNGs: %s\n' "$tmp/render"
fi

section "result"
printf '  %d passed, %d failed   (scratch: %s)\n' "$pass" "$fail" "$tmp"
[[ $fail -eq 0 ]] && [[ "${KEEP:-0}" != 1 ]] && [[ $render -eq 0 ]] && rm -rf "$tmp"
[[ $fail -eq 0 ]]
