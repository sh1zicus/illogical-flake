# Пакеты системного профиля + разрешение проприетарных (unfree).

{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    nano
    opencode
    ncdu

    # Скрипт переключения CPU governor для кнопки Power Profile (см. users.nix).
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
}
