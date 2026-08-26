{
  description = "Suderman's Emacs configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: let
    blueprint = inputs.blueprint {
      inherit inputs;
      prefix = "nix";
      systems = ["x86_64-linux" "aarch64-linux"];
      nixpkgs.overlays = [inputs.emacs-overlay.overlays.default];
    };
  in {
    inherit (blueprint) checks packages;
  };
}
