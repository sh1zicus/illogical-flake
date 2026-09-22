# Пакеты системного профиля + разрешение проприетарных (unfree).

{ config, pkgs, ... }:

let
  # Локальные пакеты из этого репо (pkgs/).
  customPkgs = import ../pkgs { inherit pkgs; };
in

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    vim
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

    # PortProton — графический лаунчер Wine/Proton для Windows-игр. Тянет СВОЙ
    # wine/proton внутри bwrap-песочницы, поэтому дублирует winePackages выше.
    # Оба нужны: системный wine = прямой запуск клиентов/игр (Stalcraft),
    # portproton = остальные Windows-игры через GUI-лаунчер.
    portproton

    # NixOS Configuration Editor — графическое редактирование NixOS-конфига.
    nixos-conf-editor

    # GSettings + dconf: needed for the end-4 wallpaper pipeline, which stores
    # the dark/light mode in org.gnome.desktop.interface.color-scheme and
    # kde-material-you-colors-wrapper.sh reads it back (see dotfiles).
    gsettings-desktop-schemas
    dconf
  ];
}
