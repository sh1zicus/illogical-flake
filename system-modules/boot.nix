# Загрузчик GRUB.

{ config, lib, pkgs, ... }:

{
  # Xanmod kernel — игровая производительность (preempt full, low-latency,
  # futex/scheduler-оптимизации). Аналог CachyOS, доступный в нашем nixpkgs.
  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  boot.loader.grub = {
    enable = true;
    # Системный диск (223,6G, by-id вместо sdb/sdc — буквы плавают между загрузками).
    device = "/dev/disk/by-id/ata-P4-240_0013084119617";
    # Ищем другие ОС (Windows на отдельном диске) и добавляем в меню GRUB.
    useOSProber = true;
    # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
    fsIdentifier = "provided";
  };
}
