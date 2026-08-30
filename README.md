# Конфиг NixOS (Illogical Impulse)

Здесь живёт весь конфиг этой машины: **система NixOS** + **home-manager** (твои
настройки и приложения). Основа — энд-4 «Illogical Impulse» (Hyprland-окружение)
с подключённым QuickShell, тёмной теме Qt (KDE platform theme + Darkly) и
долфином.

Репозиторий — единый и самодостаточный: клонируешь на любую машину, и всё
(конфиги, домашние настройки, файлы dotfiles) приезжает вместе с ним.

---

## Структура (что где лежит)

```
/etc/nixos/
├── flake.nix                # точка входа: inputs + сборка системы и home-manager
├── configuration.nix        # системные настройки (пользователи, драйверы, мосты...)
├── hardware-configuration.nix  # железо (генерируется автоматически)
├── warp.nix, zapret2-discord.nix # сетевые модули машины
├── home/
│   └── daen2772/            # // ЛИЧНЫЕ НАСТРОЙКИ ПОЛЬЗОВАТЕЛЯ //
│       ├── default.nix      # точка входа: username, импорты ниже
│       ├── illogical.nix    # включение end-4 окружения (fish, starship)
│       ├── apps.nix         # твои приложения (bottles, ...)
│       └── shell.nix        # настройки оболочки (fish, starship)
├── home-module.nix          # модуль Illogical Impulse (end-4/QuickShell)
├── home-modules/            # его части: fonts, packages, qt, env, dotfiles...
├── pkgs/                    # локальные пакеты (иконки, шрифты)
├── dotfiles/                # файлы конфигов end-4 (hypr, kitty, ...)
├── update.sh                # обновить и применить конфиг
├── install.sh               # применить/установить (на свежей машине)
└── README.md                # этот файл
```

## Как пользоваться

### 1. Изменить настройки

Выбери файл под нужное, отредактируй и примени (см. ниже):

- **Поставить приложение** → `home/daen2772/apps.nix` (в `home.packages`).
- **Изменить настройки приложения** → добавь файл вида `home/daen2772/<app>.nix`
  с опциями home-manager (например `programs.foo.enable = true;`) и пропиши его
  в `imports` в `home/daen2772/default.nix`.
- **Система** (драйверы, сервисы) → `configuration.nix`.
- **Внешний вид/тема Qt** → `home-modules/qt.nix` и `home-modules/environment.nix`.

### 2. Применить изменения / обновить

```bash
cd /etc/nixos
./update.sh          # полностью: обновить пакеты и применить
./update.sh --quick  # просто применить текущий конфиг (без обновления пакетов)
```

Скрипт спросит пароль `sudo`. После этого система пересобирается и конфиг
применяется.

### 3. Откатиться, если сломалось

```bash
sudo nixos-rebuild switch --rollback   # вернуть предыдущую рабочую версию
cd /etc/nixos && git log --oneline     # посмотреть последние изменения
git revert HEAD                        # отменить последний коммит
```

### 4. Новая машина (бэкап/переезд)

```bash
git clone <адрес-этого-репозитория> ~/nixos
sudo cp -r ~/nixos /etc/nixos
sudo nixos-generate-config --dir /etc/nixos   # сгенерировать файл железа
cd /etc/nixos && ./install.sh
```

## Полезное

- После смены конфига достаточно `./update.sh` — Hyprland после перелогина
  подхватит всё новое (пакеты, переменные окружения).
- Кнопка отката в git: любой коммит можно безопасно `git revert` — система
  переживёт.