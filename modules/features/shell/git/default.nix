{
  # A fresh machine has to be able to commit before anyone remembers an alias.
  # The git_personal/git_academic aliases still override this per checkout.
  programs.git = {
    enable = true;
    settings = {
      init = {
        defaultBranch = "main";
      };
      core = {
        editor = "nvim";
      };
      pull = {
        rebase = true;
      };
      fetch = {
        prune = true;
      };
      push = {
        default = "current";
      };
      status = {
        short = true;
      };
      diff = {
        colorMoved = "on";
      };
      commit = {
        template = "~/.config/git/conventional-template";
      };
      user = {
        name = "s0nprem0";
        email = "s0nprem0@proton.me";
      };
    };
  };

  # Conventional-commit template; `commit.template` above points at it.
  home.file.".config/git/conventional-template".text = ''
    <type>(<scope>): <subject>

    <body>

    <footer>
  '';
}
