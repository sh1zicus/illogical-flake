# Загрузчик GRUB.

{ config, lib, pkgs, ... }:

{
  # Xanmod kernel — игровая производительность (preempt full, low-latency,
  # futex/scheduler-оптимизации). Аналог CachyOS, доступный в нашем nixpkgs.
  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  boot.loader.grub = {
    enable = true;
    device = "/dev/sdb";
    useOSProber = false;
    # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
    fsIdentifier = "provided";
  };
}
