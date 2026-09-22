# Базовые системные настройки: версия, Nix, шрифты.

{ config, lib, pkgs, ... }:

{
  # This value defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  system.stateVersion = "26.05"; # Did you read the comment?

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Не предупреждать о грязном (незакоммиченном) /etc/nixos при каждой сборке.
  nix.settings.warn-dirty = false;

  # Отключаем дефолтный канал nixpkgs — с flake он не нужен, только путается.
  nix.channel.enable = false;

  # Локальный реестр: 'nix shell nixpkgs#foo' работает из стора без похода
  # на github за current nixpkgs.
  nix.registry.nixpkgs.to = {
    type = "path";
    path = pkgs.path;
  };

  # Автоматическая уборка /nix: GC раз в неделю (старше 7 дней + не более
  # 10 последних генераций), оптимизация стора (hardlinks дедупликация) —
  # не даём диску забиваться.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d --delete-generations 10";
  };
  nix.optimise.automatic = true;

  # Не генерируем индекс-кэш man-страниц (mandb.service) — man не используется.
  documentation.man.cache.enable = false;

  fonts.packages = with pkgs; [
    rubik
    nerd-fonts.ubuntu
    nerd-fonts.jetbrains-mono
  ];
}
