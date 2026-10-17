{ pkgs, ... }:

{
  home.packages = [ pkgs.helix ];

  home.sessionVariables = {
    EDITOR = "helix";
    VISUAL = "helix";
  };
}
