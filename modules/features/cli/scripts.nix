# Build one of the shell commands the features install.
#
# Every module used to repeat the same writeShellScriptBin + replaceStrings
# block and carry its own copy of the binary table. Keeping the mechanics in one
# place also makes the public/internal split deliberate: a command added to
# home.packages is on PATH, while a helper that only another script or a unit
# calls is used through `command` and never appears there.
{ pkgs }:
{
  name,
  file ? null,
  text ? null,
  bins ? { },
}:
let
  source = if text != null then text else builtins.readFile file;
  rendered = builtins.replaceStrings (builtins.attrNames bins) (builtins.attrValues bins) source;
  package = pkgs.writeShellScriptBin name rendered;
in
{
  inherit package;

  # The executable itself, for a dispatcher, a bind, or an ExecStart.
  command = "${package}/bin/${name}";
}
