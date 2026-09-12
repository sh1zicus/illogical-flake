# Системные службы, производительность и графика.

{ config, lib, pkgs, ... }:

{
  # Flatpak: portable sandboxed apps from Flathub.
  services.flatpak.enable = false;

  # zram: сжатый swap в RAM вместо сброса на SSD — игры не фризят при
  # нехватке памяти, отзывчивость под нагрузкой выше.
  zramSwap = {
    enable = true;
    memoryMax = 8589934592; # 8 GiB
  };

  # Сетевой и дисковый тюнинг ядра: ниже латенси под нагрузкой, меньше
  # стука по диску при фоновой записи (без фризов FPS).
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 2;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
  };

  # systemd-oomd: при нехватке памяти корректно гасит проблемный процесс
  # вместо зависания всей системы.
  systemd.oomd.enable = true;

  # Не пишем coredump при крашах — меньше записей на SSD, быстрый выход игры.
  systemd.coredump.enable = false;

  # Логи в RAM (volatile), максимум 64M — журнал не валит страницы на диск.
  services.journald.settings.Journal = {
    Storage = "volatile";
    SystemMaxUse = "64M";
  };

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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      vulkan-tools
    ];
  };

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
  services.geoclue2.enable = true;

  # GPU Screen Recorder: запись экрана с минимальной нагрузкой (VAAPI/AMF).
  # Модуль создаёт setcap wrapper для gsr-kms-server (cap_sys_admin),
  # иначе запись монитора падает с "kms server died".
  programs.gpu-screen-recorder.enable = true;

  # Steam + Gamescope: игры запускаются в эксклюзивном фулскрине в обход
  # композитора Hyprland — выше FPS и ниже input-lag на AMD/Wayland.
  # gamescopeSession активируется пунктом "Game Mode" ("Steam Deck mode")
  # в Steam. Программа steam (раньше был просто пакетом) теперь ставится
  # этим модулем + setcap для gamescope (cap_sys_nice).
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };
}
