{
  pkgs,
  ...
}:

{
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
        ]
        [
          "${pkgs.quickshell}/bin/quickshell"
          "${pkgs.jq}/bin/jq"
        ]
        (builtins.readFile ./pick.sh)
    ))
  ];
}