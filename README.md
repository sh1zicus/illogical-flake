# NixOS + Hyprland (Illogical Impulse)

Конфигурация машины `nixos`: NixOS, home-manager, Hyprland и окружение
Illogical Impulse на QuickShell. В репозитории лежат и системные настройки, и
домашние конфиги, и dotfiles.

> Это конфиг конкретной машины, а не универсальный установщик. При переезде на
> другое железо обязательно обнови `hardware-configuration.nix` и проверь
> диски, имя хоста и пользователя.

## Быстрый старт

Требуется NixOS с включёнными flakes и доступом в интернет.

```bash
cd /etc/nixos

./update.sh --quick   # применить текущий конфиг
./update.sh           # обновить flake-входы и применить
```

`update.sh` сам запросит пароль `sudo`. Для обычных правок в конфиге используй
`--quick`: он не обновляет nixpkgs и другие входы.

Проверить конфиг без сборки:

```bash
nix flake check --no-build
```

## Где что менять

| Что нужно | Где смотреть |
|---|---|
| Пакеты пользователя | `home/daen2772/apps.nix` |
| Системные пакеты | `system-modules/packages.nix` |
| Пользователь и его настройки | `home/daen2772/default.nix` |
| Системные службы и железо | `configuration.nix`, `system-modules/` |
| Тема, шрифты, Qt | `home-modules/environment.nix`, `home-modules/qt.nix`, `home-modules/fonts.nix` |
| Dotfiles Hyprland/QuickShell | `dotfiles/` |
| Сеть, WARP, zapret, Stalzone | `system-modules/network/` |

После правок снова запусти `./update.sh --quick`.

## Структура

```text
.
├── flake.nix                 # входы flake и сборка NixOS + home-manager
├── configuration.nix         # точка входа системного конфига
├── hardware-configuration.nix
├── system-modules/           # системные модули
│   ├── base.nix              # Nix, GC, базовые настройки
│   ├── boot.nix              # загрузчик и ядро
│   ├── locale.nix            # сеть, локаль, раскладка
│   ├── users.nix             # пользователь и sudo
│   ├── packages.nix          # системные пакеты
│   ├── services.nix          # службы и графика
│   ├── shell.nix             # fish, автологин, Hyprland
│   └── network/              # WARP, zapret2, stalzone-blocker
├── home/daen2772/            # домашние настройки пользователя
├── home-module.nix           # модуль Illogical Impulse
├── home-modules/             # его части: fonts, packages, qt, dotfiles
├── pkgs/                     # локальные пакеты
├── dotfiles/                 # конфиги Hyprland/QuickShell
├── update.sh                 # обновить и применить конфиг
├── install.sh                # установить на свежей машине
└── README.md
```

## NixOS Config в QuickShell

В QuickShell есть окно управления конфигом: дерево файлов, редактор с
подсветкой, поиск пакетов nixpkgs и кнопка пересборки.

- пересборка идёт через `pkexec` и требует подтверждения паролем;
- кнопка отмены останавливает всю сборку, а не только внешний процесс;
- лог сборки: `/var/log/nixos-build.log`;
- перед закрытием окна с несохранёнными файлами редактор попросит сохранить их.

## Новая машина

1. Скопируй репозиторий в `/etc/nixos`:

   ```bash
   git clone https://github.com/sh1zicus/illogical-flake.git ~/nixos
   sudo cp -r ~/nixos/. /etc/nixos/
   ```

   Если `/etc/nixos` уже существует, сначала сохрани нужные файлы.
2. Сгенерируй конфиг железа:

   ```bash
   sudo nixos-generate-config --dir /etc/nixos
   ```

   Если старый `hardware-configuration.nix` уже есть, сначала сохрани или
   удали его, иначе `install.sh` не будет генерировать новый.
3. Проверь и поправь под себя:
   - имя хоста в `flake.nix`, `update.sh` и `install.sh`;
   - пользователя в `flake.nix`, `home/daen2772/` и `system-modules/users.nix`;
   - диск `/mnt/games` в `configuration.nix`;
   - шаблоны сетевых интерфейсов в `system-modules/network/zapret.nix`.
4. Примени:

   ```bash
   cd /etc/nixos
   ./install.sh
   ```

## WARP

После первой установки WARP нужно зарегистрировать и подключить вручную:

```bash
sudo warp-cli --accept-tos registration new
sudo warp-cli connect
sudo warp-cli status
```

## Stalzone

Модуль блокирует игровые серверы Stalzone/Stalcraft. Сейчас разрешены пулы
`EKB` и `NSK1`, остальные блокируются. Настройки находятся в
`configuration.nix`:

```nix
services.stalzone-blocker = {
  enable = true;
  login = "nixos";
  excludePools = [ "EKB" "NSK1" ];
};
```

Список серверов обновляется службой `stalzone-blocker-fetch.service`.

## Если что-то сломалось

Вернуться к предыдущей системе:

```bash
sudo nixos-rebuild switch --rollback
```

Посмотреть последние изменения:

```bash
git log --oneline
git revert HEAD
```

Логи служб:

```bash
journalctl -u stalzone-blocker-fetch.service -n 50 --no-pager
journalctl -u nfqws2@default.service -n 50 --no-pager
```
