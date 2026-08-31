# Cloudflare WARP official client — обход российских блокировок (full tunnel).
#
# Применение:
#   sudo install -m 0644 /tmp/opencode/warp.nix /etc/nixos/warp.nix
#   # добавить ./warp.nix в imports в /etc/nixos/configuration.nix
#   sudo nixos-rebuild switch --flake /etc/nixos#nixos
#
# После пересборки (нужен интернет до engage.cloudflareclient.com):
#   sudo warp-cli --accept-tos registration new
#   sudo warp-cli connect
#   sudo warp-cli status     # должно показать Status: Connected
#
# Проверка:  curl --interface CloudflareWARP https://1.1.1.1/cdn-cgi/trace
#            должен вернуть warp=on
#
# Если 2408/UDP режут (RKN), см. комментарий ниже.

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