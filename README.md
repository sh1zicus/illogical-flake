# Illogical Impulse Flake

Home-manager module for [end-4's Illogical Impulse Hyprland dotfiles](https://github.com/end-4/dots-hyprland) with QuickShell integration.

**Based on**: [xBLACKICEx/end-4-dots-hyprland-nixos](https://github.com/xBLACKICEx/end-4-dots-hyprland-nixos)

**Source structure**: the dotfiles live **inside this repository** (in `dotfiles/`), so the config is fully self-contained and versioned on GitHub via this repo. There is **no** external `end-4/dots-hyprland` dependency anymore.

## Table of contents

- [Installation](#installation)
- [How the config is sourced](#how-the-config-is-sourced)
- [Directory layout](#directory-layout)
- [Changing the config](#changing-the-config)
- [Applying changes](#applying-changes)
- [Adding / removing packages](#adding--removing-packages)
- [Fixing icon themes](#fixing-icon-themes)
- [Updating the flake](#updating-the-flake)
- [Rolling back](#rolling-back)
- [Troubleshooting](#troubleshooting)
- [What's included](#whats-included)
- [Credits](#credits)

## Prerequisites

Configure these at the system level (in `configuration.nix`):

```nix
# Enable Hyprland
programs.hyprland.enable = true;

# Required services
services.geoclue2.enable = true;        # For QtPositioning
services.networkmanager.enable = true;  # For network management

# System fonts (optional but recommended)
fonts.packages = with pkgs; [
  rubik
  nerd-fonts.ubuntu
  nerd-fonts.jetbrains-mono
];
```

## Installation

Add this flake to your system flake's inputs and use it as a home-manager module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    illogical-flake = {
      url = "github:sh1zicus/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, illogical-flake, ... }: {
    homeConfigurations.default = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        illogical-flake.homeManagerModules.default
        {
          programs.illogical-impulse.enable = true;
        }
      ];
    };
  };
}
```

### Full configuration

```nix
{
  programs.illogical-impulse = {
    enable = true;

    # Optional: enable OpenCode AI coding agent
    opencode.enable = true;

    # Customize shell tools (all enabled by default)
    dotfiles = {
      fish.enable = true;     # Fish shell with custom config
      kitty.enable = true;    # Kitty terminal emulator
      starship.enable = true; # Starship prompt
    };
  };
}
```

## How the config is sourced

The dotfiles are stored **in this repository** under `dotfiles/` and are sourced from the flake itself (`self`). This means:

- When you consume this flake via `github:sh1zicus/illogical-flake`, the config is read from **the GitHub checkout** of this repo.
- During local development (using `path:`, for example), it is read from your local working copy.
- There is no separate `dotfiles` flake-input to override anymore.

> **Note:** A flake locks its inputs to a specific Git revision (stored in `flake.lock`). To get the latest config after pushing, you must update the `illogical-flake` input — see [Updating the flake](#updating-the-flake).

## Directory layout

```
illogical-flake/
├── flake.nix                  # flake definition, dotfiles sourced via `self`
├── home-module.nix            # main home-manager module
├── home-modules/
│   ├── dotfiles.nix           # copies dotfiles/ → $HOME, generates hypr custom/*.lua
│   ├── packages.nix           # core packages (tools, GUI apps, themes)
│   ├── qt.nix                 # Qt/QuickShell packages
│   ├── environment.nix        # session environment variables
│   ├── fonts.nix              # fonts
│   └── opencode.nix           # OpenCode agent (optional)
├── pkgs/                      # custom packages (icons, etc.)
└── dotfiles/
    └── dots/
        ├── .config/           # main configuration (hypr, quickshell, kitty, fish, ...)
        └── .local/share/      # icons, konsole profiles
```

The most useful edit targets:

```
dotfiles/dots/.config/hypr/                      # Hyprland config (lua-based)
dotfiles/dots/.config/hypr/custom/               # your overrides: env.lua, general.lua, keybinds.lua, ...
dotfiles/dots/.config/quickshell/                # QuickShell panel / UI
dotfiles/dots/.config/fish/                      # fish shell config
dotfiles/dots/.config/kitty/                     # kitty terminal config
dotfiles/dots/.config/fuzzel/                    # launcher
dotfiles/dots/.config/wlogout/                   # logout menu
dotfiles/dots/.config/starship.toml              # prompt
```

## Changing the config

1. Edit any file under `dotfiles/dots/.config/` in this repository.
2. Commit and push:

```bash
cd ~/Repos/illogical-flake
git add -A
git commit -m "update hypr config"
git push
```

The `dotfiles.nix` module copies the contents of `dotfiles/dots/.config` and `dotfiles/dots/.local/share` into your `$HOME` on every activation. Files are **copied** (not symlinked), and the `hypr/custom/*.lua` overrides are regenerated at activation time.

> **Heads-up:** because files are copied, anything already present in `~/.config` from a previous run is replaced. This is how the upstream Illogical Impulse config is designed to behave. If you need a value that survives switching, prefer editing the files in `dotfiles/` and committing them.

## Applying changes

Because the config is pulled from GitHub, the flow is:

```bash
cd ~/Repos/configs/hosts
nix flake update illogical-flake
home-manager switch --flake .#default
```

Or, as a one-liner:

```bash
cd ~/Repos/configs && nix flake update illogical-flake && home-manager switch --flake .#default
```

> Replace `default` with your actual home-manager configuration name, and `~/Repos/configs` with the path to your system flake.

## Adding / removing packages

Packages are declared in `home-modules/packages.nix` under `home.packages`. Add or remove entries and then apply the change:

```bash
# edit home-modules/packages.nix
git add -A && git commit -m "add package" && git push

# apply
cd ~/Repos/configs && nix flake update illogical-flake && home-manager switch --flake .#default
```

## Fixing icon themes

Icon theme fixes (OneUI/Papirus inheritance, `inode-directory` symlinks, icon cache updates) are applied by the activation script in `home-modules/dotfiles.nix`. You don't need to do anything manually — they run on every switch.

## Updating the flake

To pull the latest changes from GitHub into your system:

```bash
cd ~/Repos/configs/hosts
nix flake update illogical-flake
nix flake lock --update-input illogical-flake   # alternative, updates only this input
home-manager switch --flake .#default
```

To update the underlying `nixpkgs` / `home-manager` inputs as well:

```bash
cd ~/Repos/configs/hosts
nix flake update
home-manager switch --flake .#default
```

## Rolling back

Roll back to the previous home-manager generation:

```bash
home-manager generations
home-manager switch --flake .#default --rollback
```

Or simply point the `illogical-flake` input back to a previous revision of this repository.

## Troubleshooting

**Changes to `dotfiles/` are not applied.**
Make sure you committed and pushed the changes in `illogical-flake`, then ran `nix flake update illogical-flake`. Flakes lock inputs to a revision; uncommitted or unpushed edits are not picked up.

**Build fails with a removed package error.**
If a package in `home-modules/packages.nix` was removed from `nixpkgs` (for example `gnome-icon-theme`), remove the line, commit, push, and update.

**`home.stateVersion` / `home.username` not set.**
Your system flake must define `home.username`, `home.homeDirectory`, and `home.stateVersion`.

## What's included

- **QuickShell**: Qt6-based desktop shell with Material Design 3
- **Dynamic Theming**: automatic color palette generation from wallpapers
- **Complete UI**: bar, sidebars, lock screen, logout menu
- **Power Management**: hypridle, hyprlock, hyprsunset
- **Tools**: fuzzel launcher, wlogout, hyprshot, hyprpicker, and more
- **Python Environment**: pre-configured for wallpaper analysis scripts
- **Qt/QML Modules**: complete Qt6 setup including QtPositioning
- **Fonts**: Material Symbols, Nerd Fonts, and UI fonts
- **OpenCode** (optional): AI coding agent

## Credits

- **[end-4](https://github.com/end-4)** - Creator of the Illogical Impulse dotfiles
- **[xBLACKICEx](https://github.com/xBLACKICEx)** - Original NixOS flake
- **[outfoxxed](https://git.outfoxxed.me/outfoxxed/quickshell)** - QuickShell developer
