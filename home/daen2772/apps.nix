{ pkgs, ... }:
{
  # Пользовательские приложения. Пакеты из illogical-flake (dolphin, darkly,
  # plasma-integration, ...) приходят из самого модуля.
  home.packages = with pkgs; [
    bottles
  ];

  # Zen Browser (Firefox-форк) — основной браузер.
  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
    profiles.default = {
      id = 0;
      name = "default";
      settings = {
        "widget.gtk.ignore-adwaita" = false;
      };
    };
  };
}