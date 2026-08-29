#!/usr/bin/env bash
#
# Illogical Impulse — установка с нуля.
# Создаёт home-manager flake-конфиг, подключает этот модуль и применяет его.
#
# Использование:
#   ./install.sh [CONFIG_DIR] [CONFIG_NAME]
#
# По умолчанию:
#   CONFIG_DIR  = ~/home-config
#   CONFIG_NAME = default
#
# Переменные окружения:
#   ILLOGICAL_FLAKE_URL  откуда брать модуль (по умолчанию: github:sh1zicus/illogical-flake)
#   HM_BRANCH            ветка home-manager (по умолчанию: master)
#   STATE_VERSION        home.stateVersion (по умолчанию: 24.11)
#   NO_GIT=1             не делать git init в папке конфига
#
set -euo pipefail

CONFIG_DIR="${1:-$HOME/home-config}"
CONFIG_NAME="${2:-default}"
ILLOGICAL_FLAKE_URL="${ILLOGICAL_FLAKE_URL:-github:sh1zicus/illogical-flake}"
HM_BRANCH="${HM_BRANCH:-master}"
STATE_VERSION="${STATE_VERSION:-24.11}"

USERNAME="$(id -un)"
HOME_DIR="$HOME"

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
  echo "Ошибка: nix не найден. Сначала установите Nix: https://nixos.org/download/"
  exit 1
fi

if [ -e "$CONFIG_DIR/flake.nix" ]; then
  echo "Ошибка: в $CONFIG_DIR уже есть конфиг (flake.nix)."
  echo "Для обновления используйте: ./update.sh $CONFIG_DIR"
  echo "Для переустановки: rm -rf $CONFIG_DIR && ./install.sh $CONFIG_DIR"
  exit 1
fi

mkdir -p "$CONFIG_DIR"

say "Пользователь: $USERNAME, HOME: $HOME_DIR"
say "Конфиг будет создан в: $CONFIG_DIR (имя конфигурации: $CONFIG_NAME)"

cat > "$CONFIG_DIR/flake.nix" <<EOF
{
  description = "Home configuration for ${USERNAME}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/${HM_BRANCH}";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    illogical-flake = {
      url = "${ILLOGICAL_FLAKE_URL}";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, illogical-flake, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.\${system};
    in {
      homeConfigurations.${CONFIG_NAME} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          illogical-flake.homeManagerModules.default
          {
            home.username = "${USERNAME}";
            home.homeDirectory = "${HOME_DIR}";
            home.stateVersion = "${STATE_VERSION}";

            programs.illogical-impulse.enable = true;
          }
        ];
      };
    };
}
EOF

say "flake.nix создан."

if [ "${NO_GIT:-0}" != "1" ] && ! git -C "$CONFIG_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say "Инициализирую git-репозиторий в $CONFIG_DIR..."
  git init -q "$CONFIG_DIR"
  git -C "$CONFIG_DIR" add -A
  git -C "$CONFIG_DIR" -c user.email="$(git config --get user.email 2>/dev/null || echo local@host)" \
      -c user.name="$(git config --get user.name 2>/dev/null || echo local)" \
      commit -qm "init: home configuration" || true
fi

say "Формирую flake.lock (загрузка зависимостей)..."
( cd "$CONFIG_DIR" && nix flake update )

echo
say "Применяю конфигурацию. Первая сборка может занять 10–30 минут — это нормально."
switch_config "$CONFIG_DIR" "$CONFIG_NAME"

echo
say "Готово! Конфигурация применена."
say "Чтобы позже обновить всё (включая этот модуль):"
say "  $(pwd)/update.sh $CONFIG_DIR $CONFIG_NAME"