{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;

    # WirePlumber is the policy layer above PipeWire: which device is the
    # default, which profile a card is put on, and what Bluetooth is allowed to
    # negotiate. Stock policy is deliberately conservative, and these are the
    # places where the reference system's choices are better on this hardware.
    #
    # Nothing here is device-specific: a rule that only helps one laptop's
    # amplifier belongs in the machine's own configuration, not in the module
    # every host imports.
    wireplumber.extraConfig = {
      # Software volume for every card. Some Realtek codecs — including the
      # ALC897 here — put a non-linear hardware mixer curve in the way, so the
      # quiet half of the range sounds muffled and different devices do not
      # volume-match. A software mixer is linear and identical everywhere.
      "51-alsa-soft-mixer" = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "device.name" = "~alsa_card.*"; } ];
            actions.update-props = {
              "api.alsa.soft-mixer" = true;
            };
          }
        ];
      };

      # Bluetooth. A2DP is offered as soon as a device advertises it instead of
      # waiting for a profile to be picked by hand; the headset's own hardware
      # volume is used where it has one, so the laptop keys and the headset stay
      # in step; and the microphone negotiates wideband mSBC, which is the
      # difference between a headset call that is intelligible and one that is
      # not. SBC-XQ raises the bitpool on headphones that would otherwise fall
      # back to plain SBC.
      "52-bluez" = {
        "monitor.bluez.rules" = [
          {
            matches = [ { "device.name" = "~bluez_card.*"; } ];
            actions.update-props = {
              "bluez5.auto-connect" = [
                "a2dp_sink"
                "a2dp_source"
              ];
            };
          }
        ];

        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
        };
      };
    };
  };

  services.pulseaudio.enable = false;
}
