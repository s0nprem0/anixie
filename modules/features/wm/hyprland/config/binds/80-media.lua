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

bind("XF86MonBrightnessUp", "Brighter", "brightnessctl set +5%", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", "Dimmer", "brightnessctl set 5%-", { locked = true, repeating = true })
