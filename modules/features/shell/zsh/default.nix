{
  config,
  lib,
  pkgs,
  ...
}:

let
  confDir = ".config/zsh";

  # Load order matters and is expressed against Home Manager's own init
  # orders: compinit runs at 570, autosuggestions at 700, and syntax
  # highlighting at 1200 (which must stay last so widgets exist first).
  #
  # Home Manager's history block runs at 910, after history.zsh, so HISTFILE,
  # HISTSIZE and SAVEHIST are set through programs.zsh.history below instead of
  # in that file, where the later block would silently overwrite them.
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

    # atuin comes from programs.atuin below; it is not repeated here.
    packages = with pkgs; [
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

    history = {
      size = 10000;
      save = 20000;
      path = "${config.xdg.stateHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      extended = true;
      share = true;
    };

    # Home Manager does not map these two from programs.zsh.history. Both were
    # in the old history.zsh and are wanted whether or not Atuin is present.
    setOptions = [
      "HIST_REDUCE_BLANKS"
      "HIST_VERIFY"
    ];

    initContent = lib.mkMerge (
      inlineChunks
      ++ map (file: lib.mkOrder file.order ''source "$HOME/${confDir}/${file.name}.zsh"'') files
    );
  };

  # Atuin owns interactive history. Integration is disabled here because
  # history.zsh sources the cached init itself (its `--disable-ai` flag lives
  # there, not in programs.atuin.flags, which the module only passes to its own
  # eval). Home Manager still writes the config, so the leading-space filter
  # lives in Nix rather than a file Atuin rewrites after every command.
  #
  # forceOverwriteSettings is deliberate: Atuin's generated config has no
  # user settings here beyond enter_accept, and without the force HM refuses to
  # replace an existing file, leaving history_filter unapplied.
  programs.atuin = {
    enable = true;
    enableZshIntegration = false;
    forceOverwriteSettings = true;
    settings = {
      enter_accept = true;
      history_filter = [ "^ " ];
    };
  };
}
