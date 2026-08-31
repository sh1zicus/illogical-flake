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

  # Динамическая блокировка серверов Stalzone/Stalcraft (московские пулы).
  # Список IP тянется из API при каждой загрузке и периодически (см.
  # stalzone-blocker.nix). login обязателен, но любое значение даёт полный
  # общий список пулов — замени на свой логин при желании.
  services.stalzone-blocker = {
    enable = true;
    login = "nixos";
    pools = [ "MSK1" "MSK2" ];
  };
}
