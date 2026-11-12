{ lib
, rustPlatform
, fetchFromGitHub
, fetchurl
, pkg-config
, openssl
, makeWrapper
, mpv
, yt-dlp
, ffmpeg
}:

rustPlatform.buildRustPackage rec {
  pname = "ytmtui";
  version = "0.1.20";

  src = fetchFromGitHub {
    owner = "Bell09";
    repo = "ytmtui";
    rev = "v${version}";
    hash = "sha256-6gCI3GK3JY/iAop3Or5Pc/9wLLfC5NsuPcO59S3Mfbg=";
  };

  # Cargo.lock берём из тега (не тянем весь репозиторий лишний раз).
  cargoLock = {
    lockFile = fetchurl {
      url = "https://raw.githubusercontent.com/Bell09/ytmtui/v${version}/Cargo.lock";
      hash = "sha256-w83dcO8qK7huiP7R+9uLoGXqJnvP+7KhRFHDI04Y4ws=";
    };
  };

  nativeBuildInputs = [ pkg-config makeWrapper ];
  # reqwest с default-tls (native-tls) линкуется с OpenSSL.
  buildInputs = [ openssl ];

  # Рантайм-зависимости: mpv (воспроизведение), yt-dlp (извлечение потока),
  # ffmpeg (скачивание в MP3). Оборачиваем бинарь, чтобы они были в PATH
  # независимо от профиля пользователя.
  postInstall = ''
    wrapProgram $out/bin/ytmtui \
      --prefix PATH : ${lib.makeBinPath [ mpv yt-dlp ffmpeg ]}
  '';

  meta = {
    description = "A full-featured lightning fast YouTube Music TUI client written in Rust";
    homepage = "https://github.com/Bell09/ytmtui";
    license = lib.licenses.mit;
    mainProgram = "ytmtui";
    platforms = lib.platforms.linux;
  };
}
