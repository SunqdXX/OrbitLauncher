# Orbit

A planet app launcher for Wayland. Your apps orbit a spinning planet; type to
search and the orbit turns the match towards you.

It's a standalone program like wofi or rofi, with its own config file. It can
also be loaded as a module inside any quickshell config.

Discord: https://discord.gg/eBAz5q7TpY

## Install

Requires [quickshell](https://quickshell.org) and a compositor with
layer-shell (Hyprland, Sway, river, ...).

```
git clone https://github.com/SunqdXX/OrbitLauncher
cd OrbitLauncher
./install.sh                  # installs to ~/.local
sudo ./install.sh --system    # installs to /usr
```

`./install.sh --uninstall` removes it again (add `--system` if you installed
it that way). Your `~/.config/orbit` is not touched.

## Usage

```
orbit
```

opens the launcher; running it again closes it. In Hyprland:

```
bind = SUPER, A, exec, orbit
```

Keys: type to search, Enter launches, Up/Down, Tab or Ctrl+J/K move between
results, Esc closes. You can drag the orbit to spin it.

Other commands:

```
orbit daemon            stay in memory so it opens instantly
orbit open | close      explicit open/close
orbit reload            re-read the config
orbit kill              stop the daemon
orbit init [-f]         write a fresh config and copy the planets
orbit planets           list available planets
orbit import-caelestia  import app launch counts from caelestia
orbit doctor            check dependencies and config
orbit -c FILE ...       use a different config file
```

By default Orbit only runs while it's open and exits when you close it. With
`orbit daemon` (e.g. `exec-once = orbit daemon`) it opens faster but stays in
memory; the window and everything in it is unloaded while hidden.

## Configuration

The first run creates `~/.config/orbit/orbit.conf` and copies the planets to
`~/.config/orbit/planets/`. Changes to the file apply as soon as you save it.
Every option is listed with its default in
[standalone/orbit.conf](standalone/orbit.conf). Some of them:

```
planet = saturn          # file name in planets_dir, or auto / random
size = 600               # orbit diameter in px, auto fits the screen
search_opacity = 0.6     # 0 transparent, 1 solid
theme_file = ~/.local/state/caelestia/scheme.json
favourite_apps = firefox, kitty
hidden_apps = /^steam_app/
max_fps = 60
renderer = software
```

Planets: earth, jupiter, mars, moon, neptune, saturn, serpulo, sun and uranus
are included. To add one, put an image (png, jpg, webp or svg) in the planets
folder and set `planet` to its name. Square images where the planet fills the
frame work best.

Colours default to a dark palette. `theme_file` reads the JSON written by
caelestia, matugen or pywal and follows it when it changes. Individual colours
can also be set directly.

On Hyprland the search bar gets background blur through a runtime layer rule
(`blur = false` turns it off). Nothing is written to your Hyprland config. The
layer namespace is `orbit` if you want your own rules.

## Using it inside a quickshell config

Copy the `Orbit` directory next to your `shell.qml` (or run
`sudo ./install.sh --system`, which makes `import Orbit` available everywhere)
and add:

```qml
import qs.Orbit

ShellRoot {
    // ...

    OrbitWindow {
        config: OrbitConfig {
            source: Quickshell.env("HOME") + "/.config/orbit/orbit.conf"
        }
    }
}
```

Toggle it with `bind = SUPER, A, global, quickshell:orbit`, or
`qs -c <config> ipc call orbit toggle`.

Config options are also properties, so you can bind them to your shell's
colours instead of using a file:

```qml
OrbitConfig {
    primary: Colours.palette.m3primary
    surfaceContainer: Colours.palette.m3surfaceContainer
    textColour: Colours.palette.m3onSurface
}
```

`OrbitView` is the launcher without a window, for putting inside a panel you
already have. It emits `requestClose()` when it wants to be hidden. Both setups
are in [examples/](examples) and can be run with `qs -p examples/plugin-window`.

## Memory

Closed: nothing, the process exits. Open: roughly 95-180 MB depending on the
GPU driver, most of which is Qt itself (an empty quickshell window is about
80 MB on NVIDIA). `renderer = software` saves about 45 MB at the cost of some
CPU.

## Tests

```
tests/run.sh            # unit, cli and install tests
tests/run.sh --live     # also opens real windows
tests/run.sh --render   # also renders each planet/option to png
```

They run in a temporary directory and don't touch your config.

## Credits

See [CREDITS.md](CREDITS.md). Licensed under the GPL-3.0.
