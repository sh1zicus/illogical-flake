# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, ... }:

let
  # Локальные пакеты из ./pkgs (см. pkgs/default.nix).
  customPkgs = import ./pkgs { inherit pkgs; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./zapret2-discord.nix
      ./warp.nix
    ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sdc";
  boot.loader.grub.useOSProber = false;
  # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
  boot.loader.grub.fsIdentifier = "provided";

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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

  # Скрипт переключения CPU governor (используется кнопкой Power Profile в баре).
  # Устанавливается в systemPackages ниже; sudoers-правило выше разрешает его
  # без пароля.


  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    nano
    opencode

    # Скрипт переключения CPU governor для кнопки Power Profile (см. выше).
    (pkgs.writeShellScriptBin "cpu-gov-set" ''
      set -e
      gov="$1"
      if [ "$gov" != "performance" ] && [ "$gov" != "schedutil" ] && [ "$gov" != "ondemand" ] && [ "$gov" != "powersave" ]; then
        echo "usage: cpu-gov-set <performance|schedutil|ondemand|powersave>" >&2
        exit 1
      fi
      for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "$gov" > "$f"
      done
    '')

    # Полная сборка Wine с поддержкой 64-битных префиксов (wine из 32-битной
    # сборки не может запустить 64-битный клиент Stalcraft/Stalzone).
    winePackages.stableFull

    # PortProton — графический лаунчер Wine/Proton для Windows-игр.
    portproton

    # GSettings + dconf: needed for the end-4 wallpaper pipeline, which stores
    # the dark/light mode in org.gnome.desktop.interface.color-scheme and
    # kde-material-you-colors-wrapper.sh reads it back (see dotfiles).
    gsettings-desktop-schemas
    dconf
  ];

  # Declarative systemd unit для stalzone-server-blocker (вместо того, чтобы
  # инструмент писал unit в read-only /etc/systemd/system на NixOS).
  # Зеркалит то, что делает сам инструмент с apply_on_boot: применяет
  # блокировку при загрузке, снимает при выключении.
  systemd.services.stalzone-server-blocker = {
    description = "Stalzone server blocker";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Инструмент вызывает nft/iptables по PATH — добавляем их в окружение юнита.
    path = with pkgs; [ nftables iptables ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${customPkgs.stalzone-server-blocker}/bin/stalzone-server-blocker apply";
      ExecStop = "${customPkgs.stalzone-server-blocker}/bin/stalzone-server-blocker clear";
    };
  };


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
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

  # Fish shell (login shell for daen2772)
  programs.fish.enable = true;

  # Автологин на tty1: после загрузки пользователь сразу попадает в fish,
  # который вызывает Hyprland (см. loginShellInit ниже).
  services.getty.autologinUser = "daen2772";

  programs.fish.loginShellInit = ''
    # Запускаем Hyprland только на tty1 (логин-шелл при загрузке).
    if test (tty) = /dev/tty1
      # Помечаем сессию как графическую: включает графические сервисы user-сессии
      # (xdg-desktop-portal с gtk-бэкендом, flatpak-session-helper и т.д.), которые
      # зависят от graphical-session.target. Без этого flatpak-приложения (например
      # PortProton) не получают тёмную тему и настройки хоста через портал.
      #
      # Сам graphical-session.target стартовать вручную нельзя (RefuseManualStart),
      # поэтому запускаем nixos-fake-graphical-session.target — он через BindsTo
      # подтягивает настоящий таргет, и портал стартует автоматически.
      systemctl --user start nixos-fake-graphical-session.target
      exec Hyprland
    end
  '';

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

  nix.settings.experimental-features = ["nix-command" "flakes"];

  hardware.graphics.enable32Bit = true;

  programs.hyprland.enable = true;
  programs.firefox.enable = true;
  services.geoclue2.enable = true;

  fonts.packages = with pkgs; [
    rubik
    nerd-fonts.ubuntu
    nerd-fonts.jetbrains-mono
  ];
}
