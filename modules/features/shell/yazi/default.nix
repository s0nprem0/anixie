{
  programs.yazi = {
    enable = true;

    # `y` opens yazi and, on quit, leaves the shell in the directory yazi was
    # in — a program cannot change its parent's working directory, so this
    # takes a shell function. Named explicitly so a stateVersion bump does not
    # quietly rename it.
    enableZshIntegration = true;
    shellWrapperName = "y";
  };
}
