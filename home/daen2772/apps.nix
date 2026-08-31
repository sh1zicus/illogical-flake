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

    # Расширения, force-install с addons.mozilla.org (последние версии).
    policies.ExtensionSettings = let
      mkExtensionSettings = builtins.mapAttrs (_: slug: {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
        installation_mode = "force_installed";
      });
    in mkExtensionSettings {
      "uBlock0@raymondhill.net" = "ublock-origin";
      "addon@darkreader.org" = "darkreader";
    };
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