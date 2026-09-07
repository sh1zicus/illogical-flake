{ pkgs }:

{
  material-symbols               = pkgs.callPackage ./material-symbols { };
  stalker-gamma-cli              = pkgs.callPackage ./stalker-gamma-cli { };
}
