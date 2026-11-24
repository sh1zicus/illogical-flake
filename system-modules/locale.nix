# Сеть, локализация и раскладка клавиатуры.

{ config, lib, pkgs, ... }:

{
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  networking.extraHosts = ''
    162.159.129.233 media.discordapp.net images.discordapp.net images-ext-1.discordapp.net images-ext-2.discordapp.net
    162.159.133.233 media.discordapp.net images.discordapp.net images-ext-1.discordapp.net images-ext-2.discordapp.net
    162.159.134.233 media.discordapp.net images.discordapp.net images-ext-1.discordapp.net images-ext-2.discordapp.net
    162.159.135.233 media.discordapp.net images.discordapp.net images-ext-1.discordapp.net images-ext-2.discordapp.net
  '';

  # Set your time zone.
  time.timeZone = "Asia/Novosibirsk";

  # Select internationalisation properties.
  i18n.defaultLocale = "ru_RU.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
