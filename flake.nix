{
  description = "Suderman's Emacs configuration";

  inputs = {
    # Pin until nixos-unstable builds diff-cover (for sqlfluff) again.
    # Matches nixpkgs-unstable in suderman/nixos.
    nixpkgs.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    kitty-graphics.url = "github:cashmeredev/kitty-graphics.el";
    kitty-graphics.flake = false;
    pins.url = "github:suderman/pins";
    pins.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      blueprint = inputs.blueprint {
        inherit inputs;
        prefix = "nix";
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        nixpkgs.overlays = [ inputs.emacs-overlay.overlays.default ];
        nixpkgs.config = {
          android_sdk.accept_license = true;
          allowUnfreePredicate =
            package:
            builtins.elem (inputs.nixpkgs.lib.getName package) [
              "android-sdk-build-tools"
              "build-tools"
            ];
        };
      };
    in
    {
      inherit (blueprint) checks packages;
      devShells = inputs.nixpkgs.lib.mapAttrs (
        system: shells: if system == "x86_64-linux" then shells else removeAttrs shells [ "android" ]
      ) blueprint.devShells;
    };
}
