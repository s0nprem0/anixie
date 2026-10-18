{ ... }:

{
  wayland.windowManager.hyprland.settings.bind = [
    # --------------------------------------------------------------------
    # Launching
    # --------------------------------------------------------------------
    "$mod, RETURN, exec, $terminal"
    "$mod, SPACE, exec, $menu"
    # A reminder: $mod+R asks how long and then for a message, and the timer it
    # sets keeps running after this shell is gone.
    "$mod, R, exec, reminder -i"

    "$mod SHIFT, V, exec, sh -c 'cliphist list | fuzzel --dmenu | cliphist decode | wl-copy'"

    # Super+period, the emoji picker every other desktop uses. bemoji draws its
    # list through fuzzel and types the choice with wtype rather than only
    # putting it on the clipboard, so it lands in the focused window.
    "$mod, PERIOD, exec, bemoji -t"

    # The dock. Hyprland is what drives it, so the bind asks the shell over its
    # IPC rather than writing a flag the shell would have to notice on a poll —
    # the dock should appear on the keypress, not up to a second later.
    "$mod, D, exec, quickshell ipc call dock toggle"

    # --------------------------------------------------------------------
    # Screen capture
    # One command, several modes, all through `shot` (features/wm/screenshot).
    # The mode names and the keys are the reference shell's, so the habits carry
    # across: the Print key captures, exactly as it does there.
    # --------------------------------------------------------------------
    # The primary binding. `smart` is the picker that can be both a drag and a
    # click on a window, which is the one worth having on a single key.
    #
    # Spelled as a keycode rather than as PRINT, because this Hyprland reads
    # PRINT as a modifier: the line then parsed as dispatcher "shot smart", and
    # the whole bind failed with "Invalid dispatcher".
    "code:133, exec, shot smart"

    # The same capture, for people who reach for the keyboard rather than the
    # keypad — also the reference shell's alias for it.
    "$mod SHIFT, S, exec, shot smart"

    # Snap to a whole window or monitor with no dragging at all.
    "$mod SHIFT, W, exec, shot windows"

    # The colour under the pointer, as a hex code. hyprpicker does this on its
    # own; `pkill` first because one left running would eat the next press.
    "$mod, code:133, exec, pkill hyprpicker || hyprpicker -a"

    # Straight to the clipboard rather than a file, for pasting a screenshot
    # into whatever is focused.
    "$mod SHIFT, C, exec, shot smart copy"

    # Marked up before it is saved: the capture is handed to satty, which opens
    # already in crop mode, so this crops and annotates the focused window rather
    # than the whole screen and then waits to be told what to do.
    "$mod SHIFT, A, exec, shot smart annotate"

    # The whole screen with no picker at all, for when there is nothing to aim at.
    "$mod SHIFT, F, exec, shot fullscreen"

    # --------------------------------------------------------------------
    # Moving focus between windows
    # $mod + HJKL walks the layout; the arrow keys duplicate it for people
    # who reach for those first.
    # --------------------------------------------------------------------
    "$mod, H, movefocus, l"
    "$mod, L, movefocus, r"
    "$mod, K, movefocus, u"
    "$mod, J, movefocus, d"
    "$mod, LEFT, movefocus, l"
    "$mod, RIGHT, movefocus, r"
    "$mod, UP, movefocus, u"
    "$mod, DOWN, movefocus, d"

    # --------------------------------------------------------------------
    # Moving and resizing the focused window
    # Same HJKL shape as focus movement, with a modifier added:
    #   $mod SHIFT + HJKL   nudge the window
    #   $mod CTRL  + HJKL   resize the window
    # resizeactive takes an X,Y step; the sign decides the direction.
    # --------------------------------------------------------------------
    "$mod SHIFT, H, moveactive, -10 0"
    "$mod SHIFT, L, moveactive, 10 0"
    "$mod SHIFT, K, moveactive, 0 -10"
    "$mod SHIFT, J, moveactive, 0 10"
    "$mod CTRL, H, resizeactive, -10 0"
    "$mod CTRL, L, resizeactive, 10 0"
    "$mod CTRL, K, resizeactive, 0 -10"
    "$mod CTRL, J, resizeactive, 0 10"

    # --------------------------------------------------------------------
    # Swapping the focused window with its neighbour
    # --------------------------------------------------------------------
    "$mod SHIFT, LEFT, swapwindow, LEFT"
    "$mod SHIFT, RIGHT, swapwindow, RIGHT"
    "$mod SHIFT, UP, swapwindow, UP"
    "$mod SHIFT, DOWN, swapwindow, DOWN"

    # --------------------------------------------------------------------
    # Window state
    # --------------------------------------------------------------------
    "$mod, Q, killactive,"
    "$mod, F, fullscreen,"
    "$mod, V, togglefloating,"
    # pseudo-tile turns the window into a column the group resizes as a unit;
    # pin floats a window above everything regardless of focus order.
    "$mod, P, pseudo,"
    "$mod SHIFT, P, pin, active, toggle"

    # --------------------------------------------------------------------
    # Workspaces
    # 1-5 jump, comma/period step through all of them so you are not boxed
    # into the first five, and SHIFT + arrows sends the window with you.
    # --------------------------------------------------------------------
    "$mod, 1, workspace, 1"
    "$mod, 2, workspace, 2"
    "$mod, 3, workspace, 3"
    "$mod, 4, workspace, 4"
    "$mod, 5, workspace, 5"
    "$mod, comma, workspace, -1"
    "$mod, period, workspace, 1"

    "$mod SHIFT, 1, movetoworkspace, 1"
    "$mod SHIFT, 2, movetoworkspace, 2"
    "$mod SHIFT, 3, movetoworkspace, 3"
    "$mod SHIFT, 4, movetoworkspace, 4"
    "$mod SHIFT, 5, movetoworkspace, 5"
    "$mod SHIFT, LEFT, movetoworkspace, -1"
    "$mod SHIFT, RIGHT, movetoworkspace, 1"

    # Scrolling the wheel moves between existing workspaces. Hyprland 0.56's
    # hyprlang path rejects the documented `bindm ..., scroll, workspace e-1`
    # form with "too many args", so dispatch through hyprctl instead.
    "$mod, wheel, exec, hyprctl dispatch workspace e-1"
    "$mod, wheel, exec, hyprctl dispatch workspace e+1"

    # --------------------------------------------------------------------
    # Scratchpad
    # A special workspace that keeps its window alive and hidden while every
    # other workspace stays empty. Good for a long-running terminal.
    # --------------------------------------------------------------------
    "$mod, TAB, togglespecialworkspace, name:special, hyprland"

    # --------------------------------------------------------------------
    # Session
    # SHIFT + M is the graceful logout Hyprland's own config recommends: it
    # prefers a shutdown helper when one exists and falls back to a plain
    # compositor exit. Plain $mod + M still exits immediately.
    # --------------------------------------------------------------------
    "$mod, M, exit,"
    "$mod SHIFT, M, exec, command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"
    "$mod SHIFT, A, exec, hyprlock"
    "$mod SHIFT, R, exec, hyprctl reload"

    # --------------------------------------------------------------------
    # Media and brightness
    # The leading comma means "no modifier"; these arrive as hardware keys.
    # --------------------------------------------------------------------
    ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
    ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ", XF86AudioPlay, exec, playerctl play-pause"
    ", XF86AudioNext, exec, playerctl next"
    ", XF86AudioPrev, exec, playerctl previous"

    ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
    ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
  ];

  # ----------------------------------------------------------------------
  # Mouse and trackpad
  # SUPER + left/right drags a window around or resizes it, which is much
  # quicker than holding a modifier and pressing an arrow repeatedly.
  # ----------------------------------------------------------------------
  wayland.windowManager.hyprland.settings.bindm = [
    "$mod, button:1, movewindow"
    "$mod, button:2, resizewindow"
    "$mod, button:3, movewindow"
  ];
}
