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
      QT_QPA_PLATFORMTHEME = "qt6ct";  # Use qt6ct for Qt6 theming
      QT_STYLE_OVERRIDE = "";
      # Make gsettings (used by switchwall.sh theme autogen) find schemas.
      # gsettings-desktop-schemas stores them under share/gsettings-schemas/<name>/glib-2.0/schemas
      GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      ILLOGICAL_IMPULSE_DOTFILES_SOURCE = "${config.home.homeDirectory}/.config";
      XCURSOR_THEME = "Bibata-Modern-Classic";  # Cursor theme (matches hyprctl setcursor)
      XCURSOR_SIZE = "24";                       # Cursor size
    };

    # Install qt6ct for Qt theming
    home.packages = [ pkgs.qt6Packages.qt6ct ];
  };
}
