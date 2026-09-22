# Точка входа системного конфига.
#
# Всё разложено по модулям в system-modules/ — здесь только подключение
# модулей и настройки, специфичные для конкретной машины. Help is available
# in the configuration.nix(5) man page, on https://search.nixos.org/options
# and in the NixOS manual (`nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix

      # Системные модули (по категориям).
      ./system-modules/base.nix       # stateVersion, nix settings, шрифты
      ./system-modules/overlays.nix   # overlay-и для пакетов из flake-входов
      ./system-modules/boot.nix       # загрузчик GRUB
      ./system-modules/locale.nix     # сеть, локализация, раскладка
      ./system-modules/users.nix      # пользователь + права sudo
      ./system-modules/packages.nix   # пакеты системного профиля
      ./system-modules/services.nix   # службы, производительность, графика
      ./system-modules/shell.nix      # fish + автологин / запуск Hyprland

      # Сетевые модули (обход блокировок и защита от них).
      ./system-modules/network/warp.nix
      ./system-modules/network/zapret.nix
      # Чистый NixOS-модуль блокировки серверов Stalzone/Stalcraft
      # (замена sz-server-blocker; настройка декларативно через NixOS).
      ./system-modules/network/stalzone-blocker.nix
    ];

  # Игровой диск (бывший CachyOS) — отформатирован как btrfs, метка "games".
  fileSystems."/mnt/games" =
    { device = "/dev/disk/by-uuid/ea830442-4d52-4b63-a73b-de53126d6c6d";
      fsType = "btrfs";
      options = [ "noatime" "ssd" "discard=async" "space_cache=v2" "compress=zstd:1" "commit=120" ];
    };

  # Динамическая блокировка серверов Stalzone/Stalcraft. Разрешаем только
  # региональные пулы EKB (Екатеринбург) и NSK1 (Новосибирск) — всё остальное
  # блокируется (список IP тянется из API, см. stalzone-blocker.nix).
  services.stalzone-blocker = {
    enable = true;
    login = "nixos";
    excludePools = [ "EKB" "NSK1" ];
  };
}
