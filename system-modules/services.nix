# Системные службы, производительность и графика.

{ config, lib, pkgs, ... }:

{
  # Flatpak: удалён — PortProton/Bottles теперь ставятся из nix.
  services.flatpak.enable = false;
  # Одноразовая зачистка осиротевших данных (3.9G в /var/lib/flatpak):
  # вытирается при старте, пока flatpak снова не включён.
  systemd.tmpfiles.rules = [ "R /var/lib/flatpak" ];

  # Btrfs scrub: периодическая проверка контрольных сумм — раннее обнаружение
  # повреждений файловой системы / битых секторов диска.
  services.btrfs.autoScrub.enable = true;

  # rtkit: даёт pipewire/wireplumber реалтайм-планирование (SCHED_RR) —
  # ниже задержка звука без фризов под нагрузкой в играх.
  security.rtkit.enable = true;

  # Низкая задержка PipeWire (меньше quantum) для игр и голосового чата.
  services.pipewire.extraConfig.pipewire."99-lowlatency" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.quantum" = 512;
      "default.clock.min-quantum" = 256;
      "default.clock.max-quantum" = 1024;
    };
  };

  # zram: сжатый swap в RAM вместо сброса на SSD — игры не фризят при
  # нехватке памяти, отзывчивость под нагрузкой выше.
  zramSwap = {
    enable = true;
    memoryMax = 8589934592; # 8 GiB
  };

  # Сетевой и дисковый тюнинг ядра: ниже латенси под нагрузкой, меньше
  # стука по диску при фоновой записи (без фризов FPS).
  boot.kernel.sysctl = {
    # zram (8 GiB) уже имеет наивысший приоритет, поэтому при нехватке
    # памяти страницы уходят в сжатый RAM, а не на SSD. Низкая
    # swappiness держит page cache в памяти — это важнее для игр.
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 2;
    # Меньше вытеснения page cache: иначе ассеты игры вытесняются в btrfs
    # и потом перечитываются — лишняя синхронная запись под игрой.
    "vm.vfs_cache_pressure" = 50;
    # Java + Wine активно мапят память; дефолтных 65530 может не хватить.
    "vm.max_map_count" = 262144;
    "net.ipv4.tcp_congestion_control" = "bbr";
    # cake вместо fq: AQM сглаживает джиттер и буферблоат под нагрузкой.
    # Для игрового UDP (Stalcraft) это важнее, чем для TCP — bbr лечит только TCP.
    "net.core.default_qdisc" = "cake";
    # Большие сокет-буферы и TCP Fast Open — меньше задержек и хендшейков.
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_fastopen" = 3;
  };

  # Модуль cake нужен доступным до применения net.core.default_qdisc.
  boot.kernelModules = [ "sch_cake" ];

  # Планировщик ввода-вывода: mq-deadline → kyber (ниже латентность
  # случайных чтений ассетов игры). Применяется при ресиде юнита
  # или после `udevadm trigger --action=change` для sd*.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="kyber"
  '';

  # systemd-oomd: при нехватке памяти корректно гасит проблемный процесс
  # вместо зависания всей системы.
  systemd.oomd.enable = true;

  # Не пишем coredump при крашах — меньше записей на SSD, быстрый выход игры.
  systemd.coredump.enable = false;

  # Без systemd-coredump ядро пишет дампы (core.PID) прямо в рабочую папку
  # упавшего процесса при ulimit unlimited. Обнуляем лимит — дампы не создаются.
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "core"; value = "0"; }
    { domain = "*"; type = "hard"; item = "core"; value = "0"; }
    # Wine/Proton-играм нужен запас файловых дескрипторов и mlock.
    { domain = "*"; type = "soft"; item = "nofile"; value = "1048576"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "1048576"; }
    { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
  ];

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

  # CoreCtrl + overdrive: кульки, частоты и лимит мощности RX 580.
  hardware.amdgpu.overdrive.enable = true;
  programs.corectrl.enable = true;

  # sched-ext: BPF-планировщик для ровного frame-time (ядро 6.18).
  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
  };

  # ananicy-cpp: автоматические nice/IONice для игр и фоновых задач.
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-cpp;
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
  # services.geoclue2.enable = true;  # отключено: геолокация не используется
  # (погода работает по городу из конфига quickshell, GPS не задействован)

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
