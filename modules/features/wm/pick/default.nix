{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.pick;
in
{
  options.my.wm.pick.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the pick command, a question picker over Quickshell IPC (replaces fuzzel).";
  };

  config = lib.mkIf cfg.enable {
    # The picker, as a command, because everything that needs to ask a question
    # needs it and none of them should have to know about IPC. This is what
    # replaced fuzzel at every call site: a script writes its choices down, names
    # the command to run with the answer, and is finished.
    home.packages = [
      (pkgs.writeShellScriptBin "pick" (
        builtins.replaceStrings
          [
            "@QUICKSHELL@"
            "@JQ@"
            "@ANIXIE_LIB@"
          ]
          [
            "${pkgs.quickshell}/bin/quickshell"
            "${pkgs.jq}/bin/jq"
            "${../../cli/lib.sh}"
          ]
          (builtins.readFile ./pick.sh)
      ))
    ];
  };
}
