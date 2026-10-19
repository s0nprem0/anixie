{ pkgs, ... }:

{
  # Equicord: a Discord client with the Vencord plugin set built in, so the
  # plugins are part of the client rather than a patch applied to someone else's
  # binary.
  home.packages = [ pkgs.equicord ];
}
