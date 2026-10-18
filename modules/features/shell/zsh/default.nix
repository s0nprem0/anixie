{ lib, pkgs, ... }:

let
  confDir = ".config/zsh";

  # Load order matters and is expressed against Home Manager's own init
  # orders: compinit runs at 570, autosuggestions at 700, and syntax
  # highlighting at 1200 (which must stay last so widgets exist first).
  files = [
    {
      name = "options";
      order = 560;
    }
    {
      name = "completion";
      order = 580;
    }
    {
      name = "history";
      order = 850;
    }
    {
      name = "fzf";
      order = 900;
    }
    {
      name = "aliases";
      order = 1000;
    }
    {
      name = "prompt";
      order = 1140;
    }
    {
      name = "bindings";
      order = 1160;
    }
  ];

  sourcedFiles = lib.listToAttrs (
    map (file: {
      name = "${confDir}/${file.name}.zsh";
      value.source = ./. + "/${file.name}.zsh";
    }) files
  );

  # Inline fragments that are not worth their own file.
  inlineChunks = [
    (lib.mkOrder 520 ''
      # Full upstream completion set, alongside the curated nix-zsh-completions
      # that Home Manager adds for enableCompletion.
      fpath+=("${pkgs.zsh-completions}/share/zsh/site-functions")
    '')
    (lib.mkOrder 800 ''
      # fzf-tab replaces the completion menu, so it has to be sourced after
      # Home Manager runs compinit at order 570.
      source "${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.zsh"
    '')
  ];
in
{
  home = {
    file = sourcedFiles;

    packages = with pkgs; [
      atuin
      bat
      eza
      fd
      fzf
      zoxide
    ];

    sessionVariables = {
      MANPAGER = "bat -l man -p";
      PAGER = "bat --paging=always";
      GNUPGHOME = "\${XDG_DATA_HOME:-$HOME/.local/share}/gnupg";
    };
  };

  programs.zsh = {
    enable = true;

    autosuggestion.enable = true;
    fastSyntaxHighlighting.enable = true;

    initContent = lib.mkMerge (
      inlineChunks
      ++ map (file: lib.mkOrder file.order ''source "$HOME/${confDir}/${file.name}.zsh"'') files
    );
  };
}
