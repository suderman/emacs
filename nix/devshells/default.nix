{ pkgs, ... }:
pkgs.mkShell {
  shellHook = ''
    printf '%s\n' \
      "" \
      "suderman/emacs - Emacs 31 configuration for NixOS and Android" \
      "" \
      "  nix run                Run Emacs on NixOS" \
      "  ./android/install.sh   Build and install Android Emacs" \
      ""
  '';
}
