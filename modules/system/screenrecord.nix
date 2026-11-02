{
  pkgs,
  ...
}:

{
  # gpu-screen-recorder captures a monitor or a region through KMS, and the helper
  # that does the capture — gsr-kms-server — needs CAP_SYS_ADMIN to open the DRM
  # device. Without it the recorder dies at startup with
  #
  #   gsr-kms-client: gsr-kms-server is missing sys_admin cap and will require
  #   root authentication ... pkexec must be setuid root
  #   gsr error: kms server died or never started, exit code: 127
  #
  # because pkexec is not setuid on NixOS. Granting the capability to the helper
  # directly is what lets it run without a password prompt, and it is the fix the
  # recorder itself names.
  #
  # It has to be a wrapper rather than `setcap` on the file: the recorder lives in
  # the Nix store, which is read-only, and every rebuild would hand out a fresh
  # path with the capability gone. security.wrappers puts a copy carrying the
  # capability in /run/wrappers/bin, which is rebuilt from this declaration.
  #
  # The recorder finds it there because its own wrapper script prepends
  # /run/wrappers/bin to PATH before searching, so this copy is seen before
  # anything else called gsr-kms-server.
  security.wrappers.gsr-kms-server = {
    source = "${pkgs.gpu-screen-recorder}/bin/gsr-kms-server";
    capabilities = "cap_sys_admin+ep";
    owner = "root";
    group = "root";
  };
}
