{pkgs, ...}:
pkgs.writeShellApplication {
  name = "update-use-packages";
  runtimeInputs = [pkgs.git];
  text =
    # bash
    ''
      root="$(git rev-parse --show-toplevel)"
      nix eval --json "$root#emacs.parsedUsePackages" |
        sed 's/^\[/[\n  /; s/,/,\n  /g; s/\]$/\n]/' >"$root/nix/packages/use-packages.json"
    '';
}
