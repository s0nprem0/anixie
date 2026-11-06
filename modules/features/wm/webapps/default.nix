{
  lib,
  ...
}:

{
  # Kept for the option's sake only: `webapp` is native in alexie now, and
  # Chromium (which it shells out to) comes from the browser module.
  options.anixie.wm.webapps.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the webapp command, which turns a website into a Chromium --app desktop entry.";
  };
}
