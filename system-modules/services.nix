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

  programs.hyprland.enable = true;
  programs.firefox.enable = true;
  services.geoclue2.enable = true;
}
