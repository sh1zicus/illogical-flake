{
  # end-4 «Illogical Impulse» Hyprland dotfiles (через sh1zicus/illogical-flake fork).
  programs.illogical-impulse = {
    enable = true;
    dotfiles = {
      fish.enable = true;
      starship.enable = true;
    };
  };
}