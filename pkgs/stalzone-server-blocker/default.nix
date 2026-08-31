{ lib, stdenv, fetchFromGitHub, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "stalzone-server-blocker";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "clovexx";
    repo = "sz-server-blocker";
    rev = "v${version}";
    hash = "sha256-cNdemUtDpKXtIGygbCLODNZhZqFoAOF93dky9+nZGtk=";
  };

  cargoHash = "sha256-hzJHnPM+3rLHokoStoHzHQ6PV99r0T9i0EWW9cN3D2Q=";

  meta = with lib; {
    description = "Linux TUI для блокировки серверов Stalzone/Stalcraft через nftables или iptables";
    homepage = "https://github.com/clovexx/sz-server-blocker";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
