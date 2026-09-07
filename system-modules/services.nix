# Системные службы, производительность и графика.

{ config, lib, pkgs, ... }:

{
  # Flatpak: portable sandboxed apps from Flathub.
  services.flatpak.enable = false;

  # udisks2: needed for udiskie auto-mount of removable disks (USB, NTFS, etc.)
  services.udisks2.enable = true;

  # power-profiles-daemon: отключён — конфликтует с cpuFreqGovernor="performance"
  # (оба управляют губернатором CPU). Для стабильного performance в играх
  # оставляем только cpuFreqGovernor.
  # services.power-profiles-daemon.enable = true;

  # CPU frequency governor = performance (для игр): intel_cpufreq (intel_pstate
  # passive) поддерживает performance штатно через cpupower. Заметно плавнее
  # FPS в Stalcraft, чем дефолтный schedutil.
  powerManagement.cpuFreqGovernor = "performance";

  hardware.graphics.enable32Bit = true;

  # GameMode: поднимает приоритет игры, переводит CPU в performance,
  # ускоряет IO планировщик и шейдерный кэш во время запуска игры.
  programs.gamemode.enable = true;
  programs.gamemode.settings = {
    general = {
      desiredgov = "performance";
      softrealtime = "auto";
      renice = 10;
    };
    gpu = {
      apply_gpu_optimisations = "accept-responsibility";  # no-op на RADV/Mesa
      gpu_device = 0;
    };
    custom = {
      start = "";
      end = "";
    };
  };

  programs.hyprland.enable = true;
  programs.firefox.enable = true;
  services.geoclue2.enable = true;
}
