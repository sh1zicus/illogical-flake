{ lib, fetchurl, appimageTools, makeWrapper, fuse2, unzip }:

let
  version = "1.35.0";
  pname = "stalker-gamma-cli";
  src = fetchurl {
    url = "https://github.com/FaithBeam/stalker-gamma-cli/releases/download/${version}/stalker-gamma+linux.x64.AppImage";
    sha256 = "sha256-uJOnhNjxBXXKH/NLTKsRQnz++lRYCrQCJ9G4s+fbc+8=";
  };
  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];
  runtimeDependencies = [ fuse2 unzip ];

  extraPkgs = pkgs: [ pkgs.unzip pkgs.icu ];

  extraInstallCommands = ''
    # The CLI expects to be invoked as "stalker-gamma" (see --help / desktop file).
    ln -s $out/bin/stalker-gamma-cli $out/bin/stalker-gamma
    mkdir -p $out/share/applications
    cp ${appimageContents}/stalker-gamma.desktop $out/share/applications/ 2>/dev/null || true
    cp ${appimageContents}/stalker-gamma.png $out/share/pixmaps/ 2>/dev/null || true
  '';

  meta = {
    description = "CLI to install Stalker Anomaly and the GAMMA mod pack";
    homepage = "https://github.com/FaithBeam/stalker-gamma-cli";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalker-gamma";
  };
}
