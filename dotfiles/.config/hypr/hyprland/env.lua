local home_dir = os.getenv("HOME")
local user = os.getenv("USER") or ""

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Nix profile paths
hl.env("PATH",
    home_dir .. "/.nix-profile/bin" ..
    ":/etc/profiles/per-user/" .. user .. "/bin" ..
    ":" .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"))

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS",
    home_dir .. "/.local/share" ..
    ":" .. home_dir .. "/.nix-profile/share" ..
    ":/etc/profiles/per-user/" .. user .. "/share" ..
    ":/run/current-system/sw/share" ..
    ":/var/lib/flatpak/exports/share" ..
    ":/usr/local/share:/usr/share:" .. xdg_data_dirs_old)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Qt plugins from nix profiles
hl.env("QT_PLUGIN_PATH",
    home_dir .. "/.nix-profile/lib/qt-5/plugins" ..
    ":" .. home_dir .. "/.nix-profile/lib/qt-6/plugins" ..
    ":/etc/profiles/per-user/" .. user .. "/lib/qt-6/plugins" ..
    ":" .. (os.getenv("QT_PLUGIN_PATH") or ""))

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
