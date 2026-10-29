{ pkgs, ... }:

{
  home.packages = [
    pkgs.opencode
  ];

  # Only the entries below are managed. `~/.config/opencode` itself stays a
  # real directory on purpose: opencode writes `package.json` and installs
  # plugin dependencies into it at runtime, so linking the whole config
  # directory into the store would leave it read-only and break plugin install.
  xdg.configFile = {
    # A directory `source` with the default recursive = false is deployed as a
    # single symlink, so opencode's `**/SKILL.md` scan walks one real tree
    # instead of fanning out over per-skill symlinks.
    #
    # The source is a flake path, and in a git flake only *tracked* files are
    # copied to the store. A new skill that has not been `git add`ed is
    # silently absent from the store copy and will not be deployed.
    "opencode/skills".source = ./skills;

    # Local plugins are read from this tree, not written to it. The V2
    # caveman-blocks port lives here rather than in the installer's writable
    # copy so `hooks install` cannot overwrite it with the V1 template.
    "opencode/plugins".source = ./plugins;

    # Generated rather than a literal file, so the value stays valid JSON with
    # no trailing commas and Nix can interpolate store paths into it later
    # (a pinned `plugin` entry, an MCP server command). opencode validates
    # this file strictly and refuses to start on an unknown key, which is why
    # the upstream copy used "plugins" and "skills" as arrays: neither is a
    # field, so that config was dead on arrival. Anything added here must be
    # checked against https://opencode.ai/config.json first.
    "opencode/opencode.jsonc".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
    };
  };
}
