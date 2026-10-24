-- ------------------------------------------------------------------
-- Media and brightness
--
-- These arrive as hardware keys, so `locked` lets them through a fullscreen
-- window. Volume and brightness also repeat: holding the key should slide
-- rather than move one step. The mute keys and playback controls do not
-- repeat — they are toggles, and a repeating toggle ends wherever the
-- key-release happens to leave it.
--
-- The volume ceiling is 100%, the same one the panel's slider has. Above
-- that the slider cannot show the level or bring it back down, and the OSD
-- — which clamps to 100 — would sit pinned at "100%" while the output kept
-- getting louder.
-- ------------------------------------------------------------------
bind("XF86AudioRaiseVolume", "Volume up",
  "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", { locked = true, repeating = true })
bind("XF86AudioLowerVolume", "Volume down",
  "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", { locked = true, repeating = true })
-- ALT steps by one point. Tapping ALT and a volume key is how a level is
-- set exactly, without dragging the slider and without overshooting.
bind("ALT + XF86AudioRaiseVolume", "Volume up precisely",
  "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 1%+", { locked = true, repeating = true })
bind("ALT + XF86AudioLowerVolume", "Volume down precisely",
  "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-", { locked = true, repeating = true })
bind("XF86AudioMute", "Mute",
  "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", { locked = true })
-- SHIFT on the mute key cycles outputs, the reference's gesture, so moving
-- between speakers, headphones and HDMI needs no panel and no pointer.
bind("SHIFT + XF86AudioMute", "Switch audio output", "audio-output-switch", { locked = true })
bind("XF86AudioMicMute", "Mute microphone",
  "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true })

bind("XF86AudioPlay", "Play/pause", "quickshell ipc call media playPause", { locked = true })
bind("XF86AudioPause", "Play/pause", "quickshell ipc call media playPause", { locked = true })
bind("XF86AudioNext", "Next track", "quickshell ipc call media trackNext", { locked = true })
bind("XF86AudioPrev", "Previous track", "quickshell ipc call media trackPrevious", { locked = true })
-- SHIFT on the playback keys moves between players — Spotify, a browser
-- tab, a local player — the way the reference's keys do. It changes what
-- the shell treats as the active player; it does not change which
-- application is making noise.
bind("SHIFT + XF86AudioPlay", "Switch media source",
  "quickshell ipc call media sourceSwitch", { locked = true })
bind("SHIFT + XF86AudioPause", "Switch media source",
  "quickshell ipc call media sourceSwitch", { locked = true })

-- The focused display decides how brightness is applied: the internal panel
-- through the kernel backlight, an external monitor through DDC/CI. The command
-- keeps that split out of the binds.
bind("XF86MonBrightnessUp", "Brighter", "monitors brightness up 5", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", "Dimmer", "monitors brightness down 5", { locked = true, repeating = true })
-- ALT steps by one point, the same gesture the volume keys have, so a level can
-- be set exactly without holding the key and overshooting.
bind("ALT + XF86MonBrightnessUp", "Brighter precisely", "monitors brightness up 1", { locked = true, repeating = true })
bind("ALT + XF86MonBrightnessDown", "Dimmer precisely", "monitors brightness down 1", { locked = true, repeating = true })
-- SHIFT jumps to the ends, which is what the panel's slider cannot do in one
-- press when the screen is too bright to find it.
bind("SHIFT + XF86MonBrightnessUp", "Maximum brightness", "monitors brightness max", { locked = true })
bind("SHIFT + XF86MonBrightnessDown", "Minimum brightness", "monitors brightness min", { locked = true })
