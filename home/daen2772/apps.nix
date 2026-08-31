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

        # Русский интерфейс (Download langpack при первом запуске).
        "intl.locale.requested" = "ru";
        "intl.accept_languages" = "ru,en-US";
        "intl.multilingual.downloadEnabled" = true;

        # Look & feel — collapsed sidebar (сайдбар сворачивается, выезжает по наведению).
        "zen.view.sidebar.expanded" = false;
        "zen.view.compact.hide-tabbar" = true;
      };
    };
  };
}