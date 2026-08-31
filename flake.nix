{
  description = "NixOS + home-manager (Illogical Impulse) — единый конфиг на базе end-4 Hyprland dotfiles";

  inputs = {
    # Базовый nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager: управление домашними конфигами на языке Nix.
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen Browser (Firefox-форк).
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    # QuickShell (панель/шелл из end-4) и NUR (архив мелких пакетов).
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Файлы dotfiles (end-4 dots с фиксами) — хранятся в этом же репозитории.
    dotfiles = {
      url = "path:./dotfiles";
      flake = false;
    };

    # PortProton — Wine/Proton лаунчер для запуска Windows-игр.
    portproton-nixos = {
      url = "git+https://github.com/Redm00use/PortProton-NixOS";
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell, nur, dotfiles, portproton-nixos, ... }@inputs:
    let
      system = "x86_64-linux";
      hostname = "nixos";

      # Home-manager-модуль Illogical Impulse: лежит здесь же (папки
      # home-module.nix / home-modules / pkgs / dotfiles), так что не нужно
      # тянуть его из GitHub — конфиги под полным контролем в этом репо.
      illogicalModule = { config, lib, pkgs, ... }:
        (import ./home-module.nix) {
          inherit config lib pkgs;
          inputs = { inherit quickshell nur dotfiles; };
        };
    in {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix

          {
            # Модуль ожидает 'gnome-icon-theme', удалённый из свежего unstable.
            # Подменяем на adwaita-icon-theme (уже тянется модулем).
            nixpkgs.overlays = [
              (final: prev: {
                gnome-icon-theme = prev.adwaita-icon-theme;
              })
              portproton-nixos.overlays.${system}.default
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

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.daen2772 = {
                imports = [
                  illogicalModule
                  inputs.zen-browser.homeModules.twilight
                  ./home/daen2772
                ];
              };
            };
          }
        ];
      };
    };
}