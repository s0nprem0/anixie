{
  inputs,
  ...
}:

{
  imports = [ inputs.voidstrap.nixosModules.default ];

  programs.voidstrap.enable = true;
}
