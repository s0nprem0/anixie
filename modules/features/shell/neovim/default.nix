{
  config,
  pkgs,
  flakeDir,
  ...
}:

let
  # LazyVim writes lazy-lock.json and lazyvim.json back into its config
  # directory, so the whole tree is linked out of the checkout rather than
  # copied into the store: a store path is read-only, and lazy.nvim would fail
  # to pin updates. It also means new plugin files need no rebuild to appear.
  configDir = "${config.home.homeDirectory}/${flakeDir}/modules/features/shell/neovim/nvim";
in
{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    # Home Manager would otherwise write its own ~/.config/nvim/init.lua (the
    # provider stubs), which collides with the config directory linked below:
    # the generated file resolves through that symlink and lands outside $HOME,
    # failing the build. Sideloading passes it to the wrapper instead and
    # leaves init.lua to the checkout.
    sideloadInitLua = true;

    # On Neovim's PATH only, not the profile's. LazyVim boots lazy.nvim with
    # git, compiles treesitter parsers and fzf-native with cc/make, and lets
    # Mason install its npm-based servers and Prettier with node. ripgrep, fd
    # and lazygit are what fzf-lua and snacks shell out to.
    extraPackages = with pkgs; [
      curl
      fd
      gcc
      git
      gnumake
      imagemagick
      kdePackages.qtdeclarative
      lazygit
      nodejs
      ripgrep
      tree-sitter
      unzip
      wget
      wl-clipboard
    ];
  };

  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink configDir;
}
