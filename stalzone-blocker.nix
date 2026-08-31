# Динамический NixOS-модуль блокировки серверов Stalzone/Stalcraft.
#
# Полностью заменяет оригинальный sz-server-blocker (Rust-TUI), но в отличие
# от статического варианта — берёт актуальный список серверов ИЗ API при
# каждой загрузке и периодически, как это делал оригинал (sync).
#
#   services.stalzone-blocker.enable = true;
#   services.stalzone-blocker.login  = "ваш_логин";  # обязателен (без него API 500)
#
# Что происходит:
#   * systemd-юнит stalzone-blocker-fetch.service (oneshot, запуск после сети)
#     делает GET https://backend.stalcraftx.ru/address_list?login=...
#     и через jq вытаскивает IP из pipelines tunnels[].address ("ip:port"),
#     фильтрует по выбранным пулам и применяет nftables-правила (hook output):
#       - drop исходящего tcp/udp к этим IP на портах 29450-29460
#       - пропуск пакетов с mark 0x535a (пинги игры) — как в оригинале
#   * stalzone-blocker-fetch.timer обновляет правила с заданным интервалом.
#
# Применение таблицы рантайм (не через декларативный networking.nftables.tables),
# т.к. список адресов меняется динамически.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.stalzone-blocker;

  portSpec = "${toString cfg.portRange.start}-${toString cfg.portRange.end}";

  # Куда что складываем: кэш последнего JSON и итоговый nft-скрипт.
  stateDir = "/var/lib/stalzone-blocker";
  jsonFile = "${stateDir}/address_list.json";
  nftScript = "${stateDir}/rules.nft";

  # Скрипт: качает список, парсит jq, собирает правила, применяет nft.
  updateScript = pkgs.writeShellScript "stalzone-blocker-update" ''
    set -euo pipefail

    mkdir -p "${stateDir}"

    # URL API; логин обязателен, но любое значение отдаёт полный общий список.
    url="${cfg.apiBase}?login=${lib.escapeShellArg cfg.login}"

    # -k: на этой машине TLS-сертификат не проходит проверку из-за MITM
    # (WARP/zapret); см. services.stalzone-blocker.tlsVerify.
    ${if cfg.tlsVerify then "curl -sSL --fail" else "curl -skSL --fail"} \
      "$url" -o "${jsonFile}"

    # Извлекаем IP из выбранных пулов (или всех, если pools = []).
    ${lib.optionalString (cfg.pools != []) ''
    pools_json="$(
      jq -r '[ .pools[] | select(.name as $n | [${lib.concatMapStringsSep ", " (p: "\"${p}\"") cfg.pools}] | index($n)) ]' \
        "${jsonFile}"
    )"
    ''}
    ${lib.optionalString (cfg.pools == []) ''
    pools_json="$(jq -r '.pools' "${jsonFile}")"
    ''}

    # Список IP: из tunnels[] + статические servers.
    ips="$(
      { echo "$pools_json" | jq -r '.[].tunnels[].address | split(":")[0]' ; \
        for ip in ${lib.concatStringsSep " " cfg.servers}; do echo "$ip"; done; } \
      | sed '/^$/d' | sort -u
    )"

    # Собираем nft-скрипт (hook output приоритет 0) — как оригинальный инструмент.
    {
      echo "table inet stalzone_blocker {"
      echo "  chain output {"
      echo "    type filter hook output priority 0; policy accept;"
      ${lib.optionalString cfg.allowPings ''
      echo "    meta mark 0x535a accept"
      ''}
      while read -r ip; do
        [ -n "$ip" ] || continue
        echo "    ip daddr $ip tcp dport ${portSpec} drop"
        echo "    ip daddr $ip udp dport ${portSpec} drop"
      done <<< "$ips"
      echo "  }"
      echo "}"
    } > "${nftScript}"

    # Применяем атомарно: удаляем прошлую таблицу, если есть, затем грузим новую.
    nft -f "${nftScript}" || {
      # на случай, если таблица уже существует — пересоздаём
      nft delete table inet stalzone_blocker 2>/dev/null || true
      nft -f "${nftScript}"
    }
  '';
in
{
  options.services.stalzone-blocker = {
    enable = lib.mkEnableOption "динамическую блокировку серверов Stalzone/Stalcraft";

    apiBase = lib.mkOption {
      type = lib.types.str;
      default = "https://backend.stalcraftx.ru/address_list";
      description = "URL API получения списка серверов.";
    };

    login = lib.mkOption {
      type = lib.types.str;
      description = ''
        Логин для запроса address_list. API без login возвращает 500; любое
        значение отдаёт полный (общий) список пулов/серверов.
      '';
      example = "myaccount";
    };

    pools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Ограничить блокировку только этими пулами (имена из address_list,
        напр. "MSK2", "EKB"). Пустой список = блокировать все пулы.
      '';
      example = [ "MSK2" "EKB" ];
    };

    servers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Дополнительные постоянные IP-адреса для блокировки (помимо динамических из API).";
    };

    portRange = lib.mkOption {
      type = lib.types.submodule {
        options = {
          start = lib.mkOption { type = lib.types.port; default = 29450; };
          end   = lib.mkOption { type = lib.types.port; default = 29460; };
        };
      };
      default = { };
      description = "Диапазон игровых портов для блокировки (tcp и udp).";
    };

    allowPings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Пропускать пакеты с mark 0x535a (пинги игры) к заблокированным серверам.";
    };

    tlsVerify = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Проверять TLS-сертификат при запросе API. По умолчанию false, т.к. на
        многих системах (WARP/zapret) сертификат проходит через MITM и не
        валидируется системными CA.
      '';
    };

    updateInterval = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = "Интервал периодического обновления списка (systemd OnCalendar).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.login != "";
        message = "services.stalzone-blocker.login обязателен (API без login возвращает 500)";
      }
    ];

    # Инструменты, нужные скрипту.
    environment.systemPackages = [ pkgs.curl pkgs.jq ];

    systemd.services.stalzone-blocker-fetch = {
      description = "Stalzone server blocker: fetch addresses and apply nftables rules";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ curl jq nftables coreutils gnused ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = updateScript;
      };
    };

    systemd.timers.stalzone-blocker-fetch = {
      description = "Periodic refresh of Stalzone blocker rules";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = cfg.updateInterval;
        Unit = "stalzone-blocker-fetch.service";
      };
    };
  };
}
