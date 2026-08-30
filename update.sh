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

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

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
sudo nixos-rebuild switch --flake "$CONFIG_DIR#$HOST"

say "Готово!"
say "Если что-то пошло не так:"
say "  sudo nixos-rebuild switch --rollback"
say "  git -C /etc/nixos log --oneline && git -C /etc/nixos revert HEAD"