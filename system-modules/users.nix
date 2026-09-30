# Пользователи и права sudo.

{ config, lib, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."daen2772" = {
    isNormalUser = true;
    description = "daen2772";
    shell = pkgs.fish;
    # video — доступ к /dev/video* (веб-камера, карта захвата) для OBS.
    # audio — прямая работа с устройствами ALSA/Pulse (в pipewire и так есть
    # rtkit, но группу стоит иметь для студии).
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
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
