{ pkgs }:

let
  # Papirus с исправленным наследованием: Default breeze → Adwaita. Зачем:
  # у breeze нет иконок inode-directory, поэтому папки в файловых диалогах
  # GTK отображались битыми. Раньше это правилось sed-ом в activation-скрипте
  # (home-modules/dotfiles.nix) при каждом переключении; теперь патч делается
  # при СБОРКЕ пакета — детерминированно и без рантайм-мутаций.
  # Сюда же заранее создаются inode-directory симлинки (folder.svg).
  papirus-patched = pkgs.papirus-icon-theme.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      for theme in Papirus Papirus-Dark Papirus-Light; do
        index="$out/share/icons/$theme/index.theme"
        if [ -f "$index" ]; then
          sed -i 's/Inherits=breeze-dark,/Inherits=Adwaita,/g' "$index"
          sed -i 's/Inherits=breeze-light,/Inherits=Adwaita,/g' "$index"
          sed -i 's/Inherits=breeze,/Inherits=Adwaita,/g' "$index"
        fi
        for size_dir in "$out/share/icons/$theme"/*/places; do
          if [ -d "$size_dir" ] && [ -f "$size_dir/folder.svg" ] && [ ! -e "$size_dir/inode-directory.svg" ]; then
            ln -s folder.svg "$size_dir/inode-directory.svg"
          fi
        done
      done
    '';
  });
in
{
  material-symbols = pkgs.callPackage ./material-symbols { };
  papirus-patched  = papirus-patched;
}