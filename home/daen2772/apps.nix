{ pkgs, ... }:
{
  # Пользовательские приложения. Пакеты из illogical-flake (dolphin, darkly,
  # plasma-integration, ...) приходят из самого модуля.
  home.packages = with pkgs; [
    bottles
  ];
}