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

    # NixOS Configuration Editor — графическое редактирование NixOS-конфига.
    nixos-conf-editor = {
      url = "github:snowfallorg/nixos-conf-editor";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell, nur, dotfiles, portproton-nixos, nixos-conf-editor, ... }@inputs:
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
            # Прокидываем флейк-входы в system-modules/* (их использует
            # system-modules/overlays.nix). Вход по имени input-а = имя
            # аргумента; system — строка, чтобы не завязывать overlays.nix
            # на pkgs (это дало бы цикл: pkgs зависит от overlays).
            _module.args = {
              inherit portproton-nixos nixos-conf-editor system;
            };
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