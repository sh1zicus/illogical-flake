#!/usr/bin/env bash
#
# Обновление конфигурации NixOS.
# Собирает и применяет систему из этого репозитория (/etc/nixos).
#
# Использование:
#   ./update.sh          — обновить все входы flake (nixpkgs, home-manager, ...),
#                          пересобрать и применить систему
#   ./update.sh --quick  — НЕ трогать входы, просто пересобрать и применить
#                          (самый частый случай: что-то поменял в конфиге)
#
set -euo pipefail

MODE="full"
if [ "${1:-}" = "--quick" ]; then
  MODE="quick"
  shift
fi

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="nixos"

# В GUI-консоли Quickshell ANSI-цвета не читаются, поэтому при запуске
# из кнопки Build (QS_BUILD=1) печатаем без escape-последовательностей.
if [ "${QS_BUILD:-0}" = "1" ]; then
  say() { printf '==> %s\n' "$*"; }
else
  say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fi

restart_hyprland() {
  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    return 0
  fi
  local hyprctl_bin
  hyprctl_bin="$(command -v hyprctl 2>/dev/null)" || return 0
  [ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ] || return 0
  say "Перезапускаю Hyprland..."
  if [ "$(id -u)" -eq 0 ]; then
    local run_as
    run_as="${QS_USER:-}"
    if [ -z "$run_as" ]; then
      run_as="$(stat -c %U "$XDG_RUNTIME_DIR" 2>/dev/null)" || run_as=""
    fi
    if [ -n "$run_as" ] && command -v runuser >/dev/null 2>&1; then
      runuser -u "$run_as" -- env \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \
        "$hyprctl_bin" dispatch exit >/dev/null 2>&1 || true
      return 0
    fi
  fi
  env \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \
    "$hyprctl_bin" dispatch exit >/dev/null 2>&1 || true
}

if ! command -v nix >/dev/null 2>&1; then
  echo "Ошибка: nix не найден."
  exit 1
fi

if [ ! -f "$CONFIG_DIR/flake.nix" ]; then
  echo "Ошибка: $CONFIG_DIR/flake.nix не найден."
  exit 1
fi

# Проверка прав: строим/применяем систему от имени root.
if ! sudo -v; then
  echo "Ошибка: sudo недоступен." >&2
  exit 1
fi

if [ "$MODE" = "quick" ]; then
  say "Быстрый режим: только пересборка (входы flake не трогаем)..."
else
  say "Обновляю все входы flake (nixpkgs, home-manager, quickshell, ...)..."
  sudo sh -c "cd '$CONFIG_DIR' && nix flake update"
fi

say "Пересобираю и применяю систему..."
sudo nixos-rebuild --print-build-logs switch --flake "$CONFIG_DIR#$HOST"

say "Готово!"
say "Если что-то пошло не так:"
say "  sudo nixos-rebuild switch --rollback"
say "  git -C /etc/nixos log --oneline && git -C /etc/nixos revert HEAD"

if [ "${QS_BUILD:-0}" != "1" ]; then
  restart_hyprland
fi
