# Загрузчик GRUB.

{ config, lib, pkgs, ... }:

{
  # Xanmod kernel — игровая производительность (preempt full, low-latency,
  # futex/scheduler-оптимизации). Аналог CachyOS, доступный в нашем nixpkgs.
  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  # Ядро 6.18+ с собранным по умолчанию драйвером ntsync (модуль, не встроенный),
  # поэтому грузим его на старте — иначе Wine не сможет использовать ntsync.
  boot.kernelModules = [ "ntsync" ];

  boot.loader.grub = {
    enable = true;
    # Системный диск (223,6G, by-id вместо sdb/sdc — буквы плавают между загрузками).
    device = "/dev/disk/by-id/ata-P4-240_0013084119617";
    # Ищем другие ОС (Windows на отдельном диске) и добавляем в меню GRUB.
    useOSProber = true;
    # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
    fsIdentifier = "provided";

    # Не держать меню 5 секунд — перезагрузка быстрее; при желании выбрать ОС
    # в меню всё ещё можно (нажатие клавиши останавливает таймер).
  };

  boot.loader.timeout = 1;
}
