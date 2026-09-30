# Загрузчик GRUB.

{ config, lib, pkgs, ... }:

{
  # Xanmod kernel — игровая производительность (preempt full, low-latency,
  # futex/scheduler-оптимизации). Аналог CachyOS, доступный в нашем nixpkgs.
  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  # Ядро 6.18+ с собранным по умолчанию драйвером ntsync (модуль, не встроенный),
  # поэтому грузим его на старте — иначе Wine не сможет использовать ntsync.
  boot.kernelModules = [ "ntsync" ];

  # Игровые параметры ядра (XanMod + Xeon E5-2667 v4, 8 ядер / 16 потоков).
  #
  # Изоляция физического ядра под игру: isolcpus — планировщик не кладёт туда
  # ничего постороннего, nohz_full — ядро не шлёт тик 250/1000 Гц, rcu_nocbs —
  # убирает IPIs и grace-period ставы (главный источник микрофризов),
  # managed_irq — все прерывания (включая звук) уходят на housekeeping-ядро.
  # CPU 2 и его SMT-сиблинг 10 (thread_siblings_list CPU2 = "2,10") — оба,
  # иначе соседний поток снова включит тик и затенит L2 этого ядра.
  # На изолированное ядро игра вешается через STALZONE_CPUS
  # в ~/.Games/StalZone/start.sh, остальное (композитор, звук) живёт на
  # других ядрах. Побочный эффект: одно физическое ядро простаивает.
  boot.kernelParams = [
    "nohz_full=2,10"
    "isolcpus=managed_irq,2,10"
    "rcu_nocbs=2,10"

    # THP для всего, а не только по madvise: JVM сам не просит huge pages,
    # с always куча получает 2M-страницы и меньше TLB-промахов.
    "transparent_hugepage=always"

    # NMI-сторож раз в секунду на каждое CPU даёт микрофриз в игре.
    "nowatchdog"
    "nmi_watchdog=0"

    # На Broadwell spectre_v2 = retpoline + IBPB вокруг каждого syscall:
    # минус единицы процентов на CPU-bound (JIT/GC). Цена — нет защиты
    # от Spectre, здесь это осознанно (своя машина, только свои процессы).
    "mitigations=off"

    # Не синхронизировать TSC: без дрейфа и без лишних остановок.
    "tsc=reliable"
  ];

  boot.loader.grub = {
    enable = true;
    # Системный диск (223,6G, by-id вместо sdb/sdc — буквы плавают между загрузками).
    device = "/dev/disk/by-id/ata-P4-240_0013084119617";
    # Ищем другие ОС (Windows на отдельном диске) и добавляем в меню GRUB.
    useOSProber = true;
    # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
    fsIdentifier = "provided";

    # Не держать меню 5 секунд — перезагрузка быстрее; при желании выбрать ОС
    # в меню всё ещё можно (нажатие клавиши останавливает таймер).
  };

  boot.loader.timeout = 1;
}
