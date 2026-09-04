{
  description = "Suderman's Emacs configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    kitty-graphics.url = "github:cashmeredev/kitty-graphics.el";
    kitty-graphics.flake = false;
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
