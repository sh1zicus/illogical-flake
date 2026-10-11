{ config, pkgs, lib, inputs, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) system;

  # zen-wabi autoconfig must live in the *unwrapped* application directory.
  # The launcher (bin/zen-twilight) execs through a symlink to the unwrapped
  # binary, so Gecko resolves its app dir (/proc/self/exe) to the unwrapped
  # store path and reads defaults/pref/*.js + the general.config file from
  # there. wrapFirefox's own copies (in the wrapped output) are never loaded
  # -- the same reason the module injects policies into the unwrapped package.
  #
  # We use filenames that do NOT collide with wrapFirefox's autoconfig.js /
  # mozilla.cfg, otherwise wrapFirefox's `cat >` would write through the
  # symlink into the read-only store and fail the build.
  zenBase = inputs.zen-browser.packages.${system}."twilight-unwrapped".override {
    inherit (config.programs.zen-browser) policies enablePrivateDesktopEntry;
  };

  patchedZen = zenBase.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      for libdir in "$out"/lib/zen-bin-*; do
        chmod -R u+w "$libdir/defaults"
        install -m 0644 ${../../zen-wabi/config.js} "$libdir/zen-matugen.cfg"
        install -D -m 0644 ${../../zen-wabi/autoconfig.js} \
          "$libdir/defaults/pref/zen-matugen-autoconfig.js"
      done
    '';
  });
in
{
  programs.zen-browser = {
    unwrappedPackage = patchedZen;

    profiles.default.settings = {
      # Load chrome/*.css and chrome/JS/*.uc.js from the profile.
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "userChromeJS.experimental.enabled" = true;
      # Let matugen-bridge.uc.js attach universal Zen Boosts per page.
      "zen.boosts.enabled" = true;
      # Browser Toolbox (debugging the bridge).
      "devtools.chrome.enabled" = true;
      "devtools.debugger.remote-enabled" = true;
    };
  };

  # Static fx-autoconfig assets. The matugen-generated files
  # (userChrome.css, userContent.css, matugen-vars.json, ...) are written by
  # matugen into the same chrome/ directory on every wallpaper change.
  xdg.configFile = {
    "zen/default/chrome/utils".source = ../../zen-wabi/chrome/utils;
    "zen/default/chrome/JS".source = ../../zen-wabi/chrome/JS;
  };
}
