{ pkgs, ... }:
pkgs.mkShell {
  shellHook = ''
    printf '%s\n' \
      "" \
      "suderman/emacs - Emacs 31 configuration for NixOS and Android" \
      "" \
      "  nix run                Run Emacs on NixOS" \
      "  nix run .#update-use-packages" \
      "                         Refresh Nix's use-package list" \
      "  ./android/install.sh   Build and install Android Emacs" \
      ""
  '';
}
