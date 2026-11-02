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

  # nvm is pinned here rather than cloned at activation time. Its scripts are
  # installed beside the versions it downloads, and the store is read-only, so
  # activation copies this tree into ~/.nvm and leaves `versions/` alone.
  # Without nix-ld (modules/system/dev.nix) the Node builds it fetches cannot
  # load their interpreter.
  nvm = pkgs.fetchFromGitHub {
    owner = "nvm-sh";
    repo = "nvm";
    tag = "v0.40.8";
    hash = "sha256-24FP1brAAyWu+Q0Dk+Y4aXgdCBon9GkBXgFaGXBO7sc=";
  };

  # Inline fragments that are not worth their own file.
  inlineChunks = [
    (lib.mkOrder 500 ''
      # nvm loads on first use: sourcing nvm.sh eagerly costs ~0.2s at startup,
      # and most shells never touch it. `--no-use` still defines every nvm
      # function, so the first `nvm ...` call works normally. Completion comes
      # from _nvm in the fpath below, not from nvm's own setup.
      export NVM_DIR="$HOME/.nvm"
      nvm() {
        unset -f nvm
        if [ -s "$NVM_DIR/nvm.sh" ]; then
          source "$NVM_DIR/nvm.sh" --no-use
          nvm "$@"
        else
          print -u2 "nvm: $NVM_DIR/nvm.sh not found"
          return 1
        fi
      }
    '')
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

    # `-T` copies the tree's contents, not the tree node, so nvm.sh lands at
    # ~/.nvm/nvm.sh where nvm expects it. `-f` is needed on rebuilds: the
    # previous copy's files are the ones being overwritten.
    activation.nvm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.coreutils}/bin/install -d -m 0755 "$HOME/.nvm"
      ${pkgs.coreutils}/bin/cp -rfT --no-preserve=mode,ownership ${nvm} "$HOME/.nvm"
    '';

    # compinit -C never re-checks the dump, so drop it whenever this generation
    # changes. The next shell rebuilds it once, with whatever completions the
    # new generation installed.
    activation.zshCompdump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.coreutils}/bin/rm -f "${config.xdg.cacheHome}/zsh/zcompdump-"*
    '';

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

    # `-C` trusts the dump: it skips both compaudit (the ownership scan over
    # every fpath directory) and the freshness check, which together cost
    # ~40ms per shell. The activation hook below deletes the dump on every
    # rebuild, so new completions are picked up on the next shell. If a package
    # is installed outside a rebuild, delete ~/.cache/zsh/zcompdump-* once.
    completionInit = ''
      autoload -U compinit
      zcompdump_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
      mkdir -p "$zcompdump_dir"
      compinit -C -d "$zcompdump_dir/zcompdump-$ZSH_VERSION"
      unset zcompdump_dir
    '';

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
