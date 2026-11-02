{ config, ... }:

let
  render = config.anixie.theme.template.render;
in
{
  programs.kitty = {
    enable = true;

    # The colours above are the built-in default; this pulls in the file the
    # `theme` command writes, and lands after them — kitty takes the last value it
    # reads, so a theme set at runtime wins without a rebuild. SIGUSR1 makes a
    # running kitty re-read it.
    #
    # The second include is the same arrangement for the text size, written by the
    # `textsize` command. Both are defaulted by Home Manager so a fresh login
    # never includes a file that is not there yet.
    extraConfig = ''
      include ${config.anixie.theme.stateDir}/live/kitty.conf
      include ${config.anixie.theme.stateDir}/kitty-font.conf
    '';

    font = {
      name = "GohuFont 11 Nerd Font Mono";
      size = 11;
    };

    settings = {
      background_opacity = "0.96";

      background = render "@BG@";
      foreground = render "@FG@";

      selection_background = render "@ACCENT@";
      selection_foreground = render "@BG@";

      # A beam that does not blink: this is a terminal, not a text field, and
      # the blinking block draws the eye away from the command line.
      cursor_shape = "beam";
      cursor_blink_interval = "0";

      # 2000 lines loses real build output. 10000 costs nothing until used.
      scrollback_lines = "10000";

      # Select-to-copy, without holding shift. kitty only copies a selection
      # on release when this is on, so ordinary text selection still works.
      copy_on_select = "yes";

      # A terminal bell in a session that already has a notification daemon and
      # a status bar is noise.
      enable_audio_bell = "no";
    };

    keybindings = {
      # Incremental scrollback search with its own prompt: tab toggles regex,
      # up/f3 jumps to the previous match, enter commits, esc reverts. Shift
      # the same key for the next match, and the query is remembered per
      # session.
      "ctrl+f" =
        "launch --location=hsplit --allow-remote-control kitty +kitten search.py @active-kitty-window-id";
      "kitty_mod+f" =
        "launch --location=hsplit --allow-remote-control kitty +kitten search.py @active-kitty-window-id";

      # ctrl+c and ctrl+v are deliberately left unbound. Ctrl+V has to reach
      # the application so agent harnesses can read an image from the
      # clipboard, and Ctrl+C has to stay an interrupt. Text copy/paste is on
      # kitty's ctrl+shift+c/v, and SUPER+C/V reaches the same actions through
      # the compositor's universal clipboard binds.

      # Font size across every window, so a long paste does not have to be read
      # squinting, and ctrl+0 puts it back.
      "ctrl+plus" = "change_font_size all +2.0";
      "ctrl+equal" = "change_font_size all +2.0";
      "ctrl+minus" = "change_font_size all -2.0";
      "ctrl+0" = "change_font_size all 0";

      # Tab and window navigation that works the way tmux and browsers do,
      # instead of kitty's default ctrl+shift+arrow for everything.
      "ctrl+shift+enter" = "new_window";
      "ctrl+shift+right" = "next_window";
      "ctrl+shift+left" = "previous_window";
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+q" = "close_window";
      "ctrl+shift+alt+t" = "set_tab_title";
    };
  };

  # The kittens are scripts, not configuration, so Home Manager does not own
  # them through programs.kitty. Source paths, not copies: the store is
  # read-only and a kitten only ever executes.
  xdg.configFile = {
    "kitty/kittens/search.py".source = ./kittens/search.py;
    "kitty/kittens/scroll_mark.py".source = ./kittens/scroll_mark.py;
  };
}
