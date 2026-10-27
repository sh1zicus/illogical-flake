# Discord DPI bypass для хоста "nixos" через NixOS-модуль zapret2.

{ config, pkgs, ... }:

{
  services.zapret2 = {
    enable = true;

    firewall = {
      # Матчим физические интерфейсы по шаблону, а не одно имя: при
      # переименовании enp6s0 или подключении Wi-Fi/USB-модема обход
      # продолжит работать. VPN/tun-интерфейсы намеренно не трогаем.
      interfaces = [ "en*" "eth*" "wl*" "ww*" "usb*" ];

      # Focus: Discord uses TLS on 443 and voice (STUN/QUIC) over UDP.
      # Cloudflare WARP API (api.cloudflareclient.com) is SNI-blocked the same way,
      # so it is covered by the cloudflare-warp profile below.
      tcpPorts = [ 443 ];
      udpPorts = [ 443 ];

      # Only the first few packets of each connection need anti-DPI work.
      maxPackets = 16;

      # Use a queue number and mark that nothing else on this machine uses.
      queue = 200;
      desyncFwmark = "0x40000000";
    };

    profiles = {
      # Cloudflare WARP API/endpoint: РКН режет TLS по SNI (cloudflareclient.com).
      # Fake TLS splits the ClientHello so the SNI filter can't match it.
      # Must come before discord profiles (priority = 5).
      cloudflare-warp = {
        priority = 5;
        hosts.include = [
          "api.cloudflareclient.com"
          "engage.cloudflareclient.com"
          "cloudflareclient.com"
        ];
        parameters = [
          "--filter-tcp=443"
          "--payload=tls_client_hello"
          "--lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=1"
          "--lua-desync=fakedsplit:pos=1,midsld:tcp_ts=-1000"
        ];
      };

      discord-tls = {
        priority = 10;
        hosts.include = [
          "discord.com"
          "discord.gg"
          "discord.media"
          "discordapp.com"
          "discordapp.net"
          "discord.new"
          "discord.dev"
          "discordstatus.com"
        ];
        parameters = [
          "--filter-tcp=443"
          "--payload=tls_client_hello"
          "--lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=1"
          "--lua-desync=fakedsplit:pos=1,midsld:tcp_ts=-1000"
        ];
      };

      discord-voice = {
        priority = 20;
        hosts.include = [
          "discord.com"
          "discord.gg"
          "discord.media"
          "discordapp.com"
          "discordapp.net"
        ];
        parameters = [
          "--filter-udp=443"
          "--payload=stun,discord_ip_discovery"
          "--lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2"
        ];
      };

      youtube-tls = {
        priority = 30;
        hosts.include = [
          "youtube.com"
          "youtu.be"
          "youtube-nocookie.com"
          "googlevideo.com"
          "ytimg.com"
          "ggpht.com"
          "youtubei.googleapis.com"
          "youtube.googleapis.com"
        ];
        parameters = [
          "--filter-tcp=443"
          "--payload=tls_client_hello"
          "--lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=1"
          "--lua-desync=fakedsplit:pos=1,midsld:tcp_ts=-1000"
        ];
      };

      youtube-quic = {
        priority = 40;
        hosts.include = [
          "youtube.com"
          "googlevideo.com"
          "youtubei.googleapis.com"
          "youtube.googleapis.com"
        ];
        parameters = [
          "--filter-udp=443"
          "--payload=quic_initial"
          "--lua-desync=fake:blob=fake_default_quic:repeats=3"
        ];
      };

      openai-tls = {
        priority = 50;
        hosts.include = [
          "chatgpt.com"
          "openai.com"
          "oaistatic.com"
          "oaiusercontent.com"
        ];
        parameters = [
          "--filter-tcp=443"
          "--payload=tls_client_hello"
          "--lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=1"
          "--lua-desync=fakedsplit:pos=1,midsld:tcp_ts=-1000"
        ];
      };
    };
  };
}