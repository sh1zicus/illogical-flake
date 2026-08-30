#!/usr/bin/env bash

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

color=$(tr -d '\n' < "$XDG_STATE_HOME/quickshell/user/generated/color.txt")

# Make GSettings schemas discoverable: NixOS appends these to XDG_DATA_DIRS at
# login, but the already-running session keeps a stale value, so self-heal.
for _schema_dir in /run/current-system/sw/share/gsettings-schemas/*; do
    [ -d "$_schema_dir" ] || continue
    case ":$XDG_DATA_DIRS:" in
        *":$_schema_dir:"*) ;;
        *) XDG_DATA_DIRS="$_schema_dir${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}" ;;
    esac
done

current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [[ -z "$current_mode" || "$current_mode" == "default" ]]; then
    # Fallback when GSettings is unavailable: last applied scheme in
    # kdeglobals, otherwise dark.
    if grep -q "^ColorScheme=.*MaterialYouLight" "$HOME/.config/kdeglobals" 2>/dev/null; then
        current_mode="prefer-light"
    else
        current_mode="prefer-dark"
    fi
fi
if [[ "$current_mode" == "prefer-dark" ]]; then
    mode_flag="-d"
else
    mode_flag="-l"
fi

# Parse --scheme-variant flag
scheme_variant_str=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme-variant)
            scheme_variant_str="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Map string variant to integer
case "$scheme_variant_str" in
    scheme-content) sv_num=0 ;;
    scheme-expressive) sv_num=1 ;;
    scheme-fidelity) sv_num=2 ;;
    scheme-monochrome) sv_num=3 ;;
    scheme-neutral) sv_num=4 ;;
    scheme-tonal-spot) sv_num=5 ;;
    scheme-vibrant) sv_num=6 ;;
    scheme-rainbow) sv_num=7 ;;
    scheme-fruit-salad) sv_num=8 ;;
    "") sv_num=5 ;;
    *)
        echo "Unknown scheme variant: $scheme_variant_str" >&2
        exit 1
        ;;
esac

source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
# stderr is suppressed: on NixOS the tool aborts after writing the scheme files
# (plasma-apply-colorscheme is missing), which we handle below.
kde-material-you-colors "$mode_flag" --color "$color" -sv "$sv_num" 2>/dev/null || true
deactivate

# NixOS compatibility: kde-material-you-colors applies its generated scheme via
# `plasma-apply-colorscheme` (part of plasma-workspace), which isn't installed on
# a Hyprland-only setup. The scheme files are already written though, so merge
# them into ~/.config/kdeglobals ourselves (same effect for Qt/KDE apps).
apply_material_scheme() {
    python3 - "$1" <<'PY'
import configparser
import hashlib
import os
import sys

scheme_path = os.path.expanduser(sys.argv[1])
if not os.path.exists(scheme_path):
    sys.exit(1)

with open(scheme_path, "rb") as f:
    scheme_hash = hashlib.sha1(f.read()).hexdigest()

scheme = configparser.ConfigParser(interpolation=None)
scheme.optionxform = str
scheme.read(scheme_path)

kdeglobals_path = os.path.expanduser("~/.config/kdeglobals")
globals_cfg = configparser.ConfigParser(interpolation=None)
globals_cfg.optionxform = str
globals_cfg.read(kdeglobals_path)

for section in scheme.sections():
    if section.startswith(("Colors", "ColorEffects")):
        if globals_cfg.has_section(section):
            globals_cfg.remove_section(section)
        globals_cfg.add_section(section)
        for key, value in scheme.items(section):
            globals_cfg.set(section, key, value)

if not globals_cfg.has_section("General"):
    globals_cfg.add_section("General")
globals_cfg.set("General", "ColorScheme", os.path.basename(scheme_path)[:-len(".colors")])
globals_cfg.set("General", "ColorSchemeHash", scheme_hash)

with open(kdeglobals_path, "w", encoding="utf-8") as f:
    globals_cfg.write(f, space_around_delimiters=False)
PY
}

if [[ "$mode_flag" == "-d" ]]; then
    scheme_file="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/MaterialYouDark.colors"
else
    scheme_file="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/MaterialYouLight.colors"
fi

apply_material_scheme "$scheme_file"
