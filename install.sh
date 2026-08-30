#!/usr/bin/env bash
#
# Установка/применение конфигурации на машине.
#
# Для свежей машины:
#   1. Скопируй репозиторий в /etc/nixos (например: sudo cp -r ~/nixos /etc/nixos)
#   2. Сгенерируй файл железа (обязательно, он привязан к конкретной машине):
#        sudo nixos-generate-config --dir /etc/nixos
#   3. При необходимости замени hostname в flake.nix (переменная HOST).
#   4. Запусти этот скрипт.
#
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="nixos"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [ ! -f "$CONFIG_DIR/flake.nix" ]; then
  echo "Ошибка: $CONFIG_DIR/flake.nix не найден. Скопируй репозиторий в /etc/nixos."
  exit 1
fi

if [ ! -f "$CONFIG_DIR/hardware-configuration.nix" ]; then
  say "Нет hardware-configuration.nix — генерирую..."
  sudo nixos-generate-config --dir "$CONFIG_DIR"
fi

say "Пересобираю и применяю систему..."
sudo nixos-rebuild switch --flake "$CONFIG_DIR#$HOST"

say "Готово!"