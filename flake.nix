{
  description = "Suderman's Emacs configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    emacs-overlay,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [emacs-overlay.overlays.default];
      };
      inherit (pkgs) lib;

      configSource = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./early-init.el
          ./init.el
          ./lisp
          ./assets
        ];
      };

      configFiles =
        [./init.el]
        ++ lib.sort builtins.lessThan
        (builtins.filter
          (file: lib.hasSuffix ".el" (toString file))
          (lib.filesystem.listFilesRecursive ./lisp));

      emacsBase = pkgs.emacs31-pgtk.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./nix/emacs-tty-menu-restore.patch];
      });
      # Preserve package compilation when Home Manager wraps Emacs again.
      emacsSetupHook =
        pkgs.makeSetupHook {
          name = "emacs-load-path-hook";
        }
        emacsBase.setupHook;

      emacsWithDependencies = pkgs.emacsWithPackagesFromUsePackage {
        package = emacsBase;
        config = lib.concatMapStringsSep "\n" builtins.readFile configFiles;
        alwaysEnsure = true;
        extraEmacsPackages = epkgs:
          (with epkgs; [
            vterm
            pdf-tools
            jinx
            treesit-grammars.with-all-grammars
          ])
          ++ (with pkgs; [
            fd
            ripgrep
            git
            python3
            wl-clipboard
            enchant
            hunspell
            hunspellDicts.en_US
            bash-language-server
            basedpyright
            clang-tools
            gopls
            lua-language-server
            marksman
            nil
            phpactor
            ruby-lsp
            rust-analyzer
            taplo
            tree-sitter
            twig-language-server
            typescript-language-server
            vscode-langservers-extracted
            yaml-language-server
            alejandra
            prettier
            ruff
            shellcheck
            shfmt
            sqlfluff
            stylua
            treefmt
            yamlfmt
            pandoc
          ]);
      };

      emacs = pkgs.symlinkJoin {
        inherit (emacsWithDependencies) name;
        paths = [
          emacsWithDependencies
          emacsSetupHook
        ];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram "$out/bin/emacs" \
            --add-flags "--init-directory ${configSource}" \
            --set-default DICPATH "${pkgs.hunspellDicts.en_US}/share/hunspell"
        '';
        meta = emacsWithDependencies.meta // {mainProgram = "emacs";};
      };
    in {
      default = emacs;
      inherit emacs;
    });

    checks = forAllSystems (system: let
      emacs = self.packages.${system}.default;
      pkgs = import nixpkgs {inherit system;};
      smokeTest = pkgs.writeText "emacs-config-smoke.el" ''
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
    in {
      smoke =
        pkgs.runCommand "emacs-config-smoke-test" {
          nativeBuildInputs = [emacs];
        } ''
          export HOME="$TMPDIR/home"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          export XDG_CONFIG_HOME="$TMPDIR/config"
          export XDG_DATA_HOME="$TMPDIR/data"
          export XDG_STATE_HOME="$TMPDIR/state"
          mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
          emacs --batch --load ${smokeTest}
          touch "$out"
        '';
    });
  };
}
