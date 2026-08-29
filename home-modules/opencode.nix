inputs:

{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.programs.illogical-impulse.opencode;
in
{
  options.programs.illogical-impulse.opencode.enable =
    mkEnableOption "opencode, the AI coding agent";

  config = mkIf cfg.enable {
    home.packages = [ pkgs.opencode ];
    programs.opencode.enable = true;
  };
}
