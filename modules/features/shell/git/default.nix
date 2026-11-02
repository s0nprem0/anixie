{
  # A fresh machine has to be able to commit before anyone remembers an alias.
  # The git_personal/git_academic aliases still override this per checkout.
  programs.git = {
    enable = true;
    settings.user = {
      name = "s0nprem0";
      email = "s0nprem0@proton.me";
    };
  };
}
