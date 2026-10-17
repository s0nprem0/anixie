{ pkgs, ... }:

{
  home.packages = [ pkgs.helix ];

  home.sessionVariables = {
    # Helix installs its binary as hx.
    EDITOR = "hx";
    VISUAL = "hx";
  };
}
