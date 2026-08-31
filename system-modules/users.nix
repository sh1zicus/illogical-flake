# Пользователи и права sudo.

{ config, lib, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."daen2772" = {
    isNormalUser = true;
    description = "daen2772";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  # Разрешить daen2772 переключать CPU governor (performance/schedutil) без
  # пароля — это нужно кнопке "Power Profile" в Quickshell, которая пишет
  # прямо в /sys/.../scaling_governor вместо power-profiles-daemon.
  security.sudo.extraRules = [
    {
      users = [ "daen2772" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/cpu-gov-set *";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
