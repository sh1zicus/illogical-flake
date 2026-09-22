{ config, lib, pkgs, inputs, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.programs.illogical-impulse;
in
{
  # Import all sub-modules
  imports = [
    ./home-modules/fonts.nix
    ./home-modules/packages.nix
    ./home-modules/qt.nix
    ./home-modules/environment.nix
    ./home-modules/dotfiles.nix
  ];

  # Входы flake (quickshell, nur, dotfiles) прокидываем под-модулям через
  # _module.args, а не через (import ./x.nix inputs). Так файлы в
# home-modules/ остаются «обычными» модулями (их можно импортировать куда
# угодно без обёрток), а все вложенные импорты видят эти аргументы.
  config._module.args = {
    inherit (inputs) quickshell nur dotfiles;
  };

  # Main options for Illogical Impulse
  options.programs.illogical-impulse = {
    enable = mkEnableOption "Enable the Illogical Impulse Hyprland configuration";

    # Internal options (not meant to be set by users)
    internal = {
      pythonEnv = mkOption {
        type = types.package;
        internal = true;
        description = "Python environment for QuickShell (internal use only)";
      };
    };
  };

  # Main configuration is now handled by sub-modules
  # Each sub-module checks cfg.enable and provides its own configuration
}