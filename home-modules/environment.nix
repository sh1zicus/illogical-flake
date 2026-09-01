inputs:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.illogical-impulse;
  pythonEnv = cfg.internal.pythonEnv;
in
{
  config = lib.mkIf cfg.enable {
    # Environment variables for Illogical Impulse
    home.sessionVariables = {
      # KDE platform theme (reads kdeglobals for color scheme, icons and fonts).
      # Matches upstream end-4/dots-hyprland. qt6ct broke theming because its
      # plugin is not in the QT_PLUGIN_PATH of nix-wrapped Qt apps.
      QT_QPA_PLATFORMTHEME = "kde";
      # Ensure Qt plugins from home.packages (plasma-integration, darkly, ...)
      # are found even for nix-wrapped apps like Dolphin. Wrappers append to
      # this value, so it does not clobber per-app paths.
      QT_PLUGIN_PATH = "${config.home.homeDirectory}/.nix-profile/lib/qt-5/plugins:${config.home.homeDirectory}/.nix-profile/lib/qt-6/plugins:/etc/profiles/per-user/${config.home.username}/lib/qt-6/plugins";
      # Make gsettings (used by switchwall.sh theme autogen) find schemas.
      # gsettings-desktop-schemas stores them under share/gsettings-schemas/<name>/glib-2.0/schemas
      GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      ILLOGICAL_IMPULSE_DOTFILES_SOURCE = "${config.home.homeDirectory}/.config";
      XCURSOR_THEME = "Bibata-Modern-Classic";  # Cursor theme (matches hyprctl setcursor)
      XCURSOR_SIZE = "24";                       # Cursor size
    };

    # X11 cursor settings for XWayland applications (Steam, Wine, etc.)
    xresources.properties = {
      "Xcursor.theme" = "Bibata-Modern-Classic";
      "Xcursor.size" = 24;
    };

    # Qt platform theme integration (kde) + Darkly widget style from upstream
    home.packages = [
      pkgs.kdePackages.plasma-integration  # Provides the "kde" platform theme plugin
      pkgs.darkly                           # Qt6 Darkly widget style (kdeglobals widgetStyle=Darkly)
    ];
  };
}
