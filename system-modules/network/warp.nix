# Cloudflare WARP официальный клиент — обход российских блокировок (full tunnel).
#
# После первой пересборки (нужен интернет до engage.cloudflareclient.com):
#   sudo warp-cli --accept-tos registration new
#   sudo warp-cli connect
#   sudo warp-cli status     # должно показать Status: Connected
#
# Проверка: curl --interface CloudflareWARP https://1.1.1.1/cdn-cgi/trace
# должен вернуть warp=on

{ config, lib, pkgs, ... }:

{
  services.cloudflare-warp = {
    enable = true;
    # По умолчанию: rootDir = /var/lib/cloudflare-warp, udpPort = 2408.
    # Модуль сам откроет UDP 2408 в networking.firewall.
  };

  # Системный пакет warp-cli уже ставится модулем (environment.systemPackages).
  # Дополнительно ничего не нужно.
}