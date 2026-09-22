# Overlay-и для пакетов из flake-входов (перенесено из flake.nix).
# Здесь собраны все «нестандартные» правки пакетов, чтобы точка входа
# оставалась только про проводку входов и модулей.
#
# ВАЖНО: этот модуль НЕ должен принимать и использовать `pkgs`/`config` в своей
# сигнатуре — nixpkgs.overlays влияет на pkgs, и зависимость pkgs <- config
# замкнулась бы в бесконечную рекурсию. system передаётся строкой из flake.

{ lib, portproton-nixos, nixos-conf-editor, system, ... }:

{
  nixpkgs.overlays = [
    # Модуль ожидает 'gnome-icon-theme', удалённый из свежего unstable.
    # Подменяем на adwaita-icon-theme (уже тянется модулем).
    (final: prev: {
      gnome-icon-theme = prev.adwaita-icon-theme;
    })

    # Overlays PortProton-NixOS (даёт базовый пакет `portproton`).
    portproton-nixos.overlays.${system}.default

    # NixOS Configuration Editor (графический редактор конфигов).
    (final: prev: {
      nixos-conf-editor =
        nixos-conf-editor.packages.${system}.nixos-conf-editor;
    })

    # Правка пакаджа PortProton: штатный steam-run не содержит GTK3,
    # из-за чего GUI (yad_gui_pp) не открывается
    # («libgtk-3.so.0: cannot open shared object file»).
    # Заменяем на buildFHSEnv, внутрь которого добавляем GTK и
    # библиотеки, нужные и GUI, и Wine/играм.
    (final: prev: {
      portproton = let
        # FHS-окружение с GTK3 и всем, что нужно GUI/Wine/играм.
        fhsEnv = final.buildFHSEnv {
          name = "portproton-fhs";
          # 32-битный слой для i386 wine-префиксов PortProton.
          multiArch = true;
          # 64-bit-часть: GUI и CLI-утилиты.
          targetPkgs = pkgs: with pkgs; [
            # GTK и зависимости GUI (yad_gui_pp)
            gtk3 gdk-pixbuf cairo pango glib
            # Тема GTK (adw-gtk3), используемая в системе; без неё
            # внутри песочницы GTK откатывается на дефолтную Adwaita.
            adw-gtk3
            # GUI/CLI-утилиты, которые были в примеч. пакете
            yad zenity bash cabextract coreutils curl file findutils
            gawk gnugrep gnutar gnused gzip icoutils jq lsof pciutils
            procps python3 systemd xdg-utils unzip usbutils
            util-linux wget which xz zstd
            # Графика 64-bit
            libGL libGLU freetype fontconfig alsa-lib pipewire
            pulseaudio vulkan-loader mesa vulkan-tools xrandr gamescope
            # X11-утилиты и crypto, нужные wine в 64-bit тоже
            libxcb gnutls
            libxcb-util libxcb-image libxcb-keysyms
            libxcb-render-util libxcb-wm
            libxshmfence libxxf86vm libxfixes libxcomposite
          ];
          multiPkgs = pkgs: with pkgs; [
            # 32-битные версии этих библиотек ставятся автоматически
            # только при multiArch; здесь — базовые либы.
            libGL alsa-lib zlib libx11 libxext libxcursor
            libxi libxrandr libxrender freetype fontconfig
            expat
            # Для 32-битной игры/лаунчера (ExboLauncher — 32 bit):
            # без 32-битного vulkan DXVK не стартует (Failed to load
            # libvulkan.so.1); libxcb/gnutls/xcb-util — требования wine.
            vulkan-loader libxcb gnutls
            libxcb-util libxcb-image libxcb-keysyms
            libxcb-render-util libxcb-wm
            libxshmfence libxxf86vm libxfixes libxcomposite
            # 32-битный radv (ICD), чтобы 32-битный DXVK видел GPU с тем
            # же именем, что и 64-битный системный Vulkan (vulkaninfo),
            # иначе фильтр DXVK не совпадает -> "No adapters found".
            mesa
          ];
          runScript = "${prev.portproton}/bin/.portproton-unwrapped";
        };
      in final.symlinkJoin {
        name = "portproton";
        # Внешняя обёртка: cd в $HOME до запуска bwrap, иначе
        # падает «bwrap: Can't chdir», если запускают не из $HOME.
        paths = [
          (final.writeShellScriptBin "portproton-wrapper" ''
            cd "$HOME"
            # Тема: внутри песочницы GTK не читает dconf/portal,
            # поэтому задаём тему явно (adw-gtk3-dark ~ prefer-dark).
            export GTK_THEME="adw-gtk3-dark"
            export GSETTINGS_BACKEND=memory
            exec ${fhsEnv}/bin/portproton-fhs "$@"
          '')
          (final.writeShellScriptBin "portproton" ''
            cd "$HOME"
            export GTK_THEME="adw-gtk3-dark"
            export GSETTINGS_BACKEND=memory
            exec ${fhsEnv}/bin/portproton-fhs "$@"
          '')
        ];
        postBuild = ''
          cp -r ${prev.portproton}/share $out/share
        '';
      };
    })
  ];
}