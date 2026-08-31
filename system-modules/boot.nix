# Загрузчик GRUB.

{ config, lib, pkgs, ... }:

{
  boot.loader.grub = {
    enable = true;
    device = "/dev/sdc";
    useOSProber = false;
    # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
    fsIdentifier = "provided";
  };
}
