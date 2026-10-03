{ pkgs, ... }:
{
  # Пользовательские приложения. Пакеты из illogical-flake (dolphin, darkly,
  # plasma-integration, ...) приходят из самого модуля.

  # udiskie: автоматическое монтирование дисков (USB, NTFS) в пользовательской сессии.
  services.udiskie.enable = true;
  services.udiskie.automount = true;

  # OBS Studio — запись видео и стримы с экрана/камеры.
  # На Wayland (Hyprland) захват экрана идёт через PipeWire-портал
  # (xdg-desktop-portal-hyprland уже запущен), кодирование — через VA-API
  # (драйвер radeonsi_drv_video из mesa, тянется с amdgpu).
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs; [
      # Захват звука приложений на Wayland (без костылей с pulse).
      obs-studio-plugins.obs-pipewire-audio-capture
      # Управление OBS с телефона/Stream Deck.
      obs-studio-plugins.obs-websocket
    ];
  };

  # Диагностика железа для OBS: v4l2-ctl (веб-камера/карта захвата, форматы
  # входа), vainfo (аппаратные кодировщики VA-API).
  home.packages = with pkgs; [
    v4l-utils
    libva-utils
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

        # Экономия памяти — важно под играми, где RAM упирается.
        # Выгружать фоновые вкладки при нехватке памяти вместо свапа.
        "browser.tabs.unloadOnLowMemory" = true;
        # Не держать JS-объекты в разделяемой памяти.
        "javascript.options.shared_memory" = false;
        # Агрессивнее усыплять таймеры в фоновых вкладках.
        "dom.min_background_timeout_value" = 1000;
        # Не хранить в памяти историю переходов для документов.
        "browser.sessionhistory.max_total_viewers" = 0;
        # Не держать content-процессы наготове: в простое это 100–250 МБ
        # RAM, которые не нужны, пока не открываешь новые вкладки.
        "dom.ipc.processPrelaunch.enabled" = false;
        # 16 ядер, а дефолт 8 — меньше процессов, меньше overhead.
        "dom.ipc.processCount" = 4;
        # Не предзагружать ссылки в фоне: во время игры лишний трафик и CPU.
        "network.prefetch-next" = false;
        # 25 закрытых вкладок в истории — многовато.
        "browser.sessionstore.max_tabs_undo" = 5;
      };
    };
  };
}