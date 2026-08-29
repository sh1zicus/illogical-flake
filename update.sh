#!/usr/bin/env bash
#
# Illogical Impulse — полное обновление и применение.
# Обновляет входы flake (по умолчанию ВСЕ: nixpkgs, home-manager, illogical-flake, ...)
# и пересобирает конфигурацию.
#
# Использование:
#   ./update.sh [CONFIG_DIR] [CONFIG_NAME]
#   ./update.sh --quick [CONFIG_DIR] [CONFIG_NAME]
#
# По умолчанию:
#   CONFIG_DIR  = ~/home-config
#   CONFIG_NAME = default
#
# --quick — обновить ТОЛЬКО illogical-flake (если остальное не нужно).
# Если вы правите dotfiles в локальной копии illogical-flake,
# сначала закоммитьте и запушьте их, затем запускайте этот скрипт.
#
set -euo pipefail

MODE="full"
if [ "${1:-}" = "--quick" ]; then
  MODE="quick"
  shift
fi

CONFIG_DIR="${1:-$HOME/home-config}"
CONFIG_NAME="${2:-default}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

switch_config() {
  local dir="$1" name="$2"
  if command -v home-manager >/dev/null 2>&1; then
    say "Использую установленный home-manager..."
    home-manager switch --flake "$dir#$name"
  else
    say "home-manager не установлен, активирую напрямую через flake..."
    local out
    out="$(nix build --no-link --print-out-paths "$dir#homeConfigurations.$name.activationPackage")"
    "$out/activate"
  fi
}

if ! command -v nix >/dev/null 2>&1; then
  echo "Ошибка: nix не найден."
  exit 1
fi

if [ ! -f "$CONFIG_DIR/flake.nix" ]; then
  echo "Ошибка: $CONFIG_DIR/flake.nix не найден."
  echo "Сначала установите конфиг: ./install.sh $CONFIG_DIR"
  exit 1
fi

if [ "$MODE" = "quick" ]; then
  say "Обновляю ТОЛЬКО illogical-flake..."
  ( cd "$CONFIG_DIR" && nix flake update illogical-flake )
else
  say "Полное обновление всех входов (nixpkgs, home-manager, illogical-flake ...)"
  ( cd "$CONFIG_DIR" && nix flake update )
fi

say "Применяю конфигурацию '$CONFIG_NAME'..."
switch_config "$CONFIG_DIR" "$CONFIG_NAME"

say "Готово!"