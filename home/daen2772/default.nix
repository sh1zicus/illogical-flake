{
  # Точка входа в home-manager конфигурацию пользователя daen2772.
  # Каждое приложение/область вынесено в отдельный файл в этой папке.
  imports = [
    ./illogical.nix   # end-4 (Illogical Impulse) dotfiles
    ./apps.nix        # пользовательские приложения (bottles, ...)
    ./shell.nix       # fish, starship, ... (по мере надобности)
  ];

  home.username = "daen2772";
  home.homeDirectory = "/home/daen2772";
  home.stateVersion = "26.05";
}