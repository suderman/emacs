{
  perSystem,
  pkgs,
  ...
}: let
  emacs = perSystem.self.default;
  checkScript =
    pkgs.writeText
    "emacs-config-check.el"
    # elisp
    ''
      ;;; -*- lexical-binding: t; -*-
      (load (expand-file-name "init.el" user-emacs-directory))
      (dolist (library '("meow" "vterm" "pdf-tools" "jinx"))
        (unless (locate-library library)
          (error "Missing Emacs library: %s" library)))
      (dolist (executable '("fd" "rg" "pandoc" "treefmt" "wl-copy"))
        (unless (executable-find executable)
          (error "Missing executable: %s" executable)))
      (unless (treesit-language-available-p 'c)
        (error "Missing C tree-sitter grammar"))
    '';
in
  pkgs.runCommand "emacs-config-check" {}
  # bash
  ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_STATE_HOME="$TMPDIR/state"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
    ${emacs}/bin/emacs --batch --load ${checkScript}
    touch "$out"
  ''
