# Fish shell и автологин на tty1 (запуск Hyprland).

{ config, lib, pkgs, ... }:

{
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
}
