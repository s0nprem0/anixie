{ pkgs, ... }:

{
  # AMD integrated graphics (Lucienne/Renoir) on the VivoBook M513UA.
  # RADV is the default Vulkan driver in Mesa and needs no extra wiring;
  # these packages add VA-API video decode/encode and the diagnostic tools.
  hardware.graphics = {
    extraPackages = with pkgs; [
      mesa
      libva
      libva-utils
    ];
    # 32-bit graphics are already enabled by gaming.nix (enable32Bit), which
    # supplies the 32-bit Mesa. Listing it again here makes buildEnv choke on
    # two identical derivations.
  };

  environment.systemPackages = with pkgs; [
    vulkan-tools
  ];
}
