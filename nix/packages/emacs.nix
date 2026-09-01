{pkgs, ...}: let
  inherit (pkgs) lib;

  configSource = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../early-init.el
      ../../init.el
      ../../lisp
      ../../assets
    ];
  };

  configFiles =
    [../../init.el]
    ++ lib.sort builtins.lessThan
    (builtins.filter
      (file: lib.hasSuffix ".el" (toString file))
      (lib.filesystem.listFilesRecursive ../../lisp));

  emacsBase = pkgs.emacs31-pgtk.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./emacs-tty-menu-restore.patch];
  });
  # Preserve package compilation when Home Manager wraps Emacs again.
  emacsSetupHook =
    pkgs.makeSetupHook {
      name = "emacs-load-path-hook";
    }
    emacsBase.setupHook;
  epubThumbnailer = pkgs.writeShellScriptBin "epub-thumbnailer" ''
    exec ${pkgs.gnome-epub-thumbnailer}/bin/gnome-epub-thumbnailer \
      -s "$3" "$1" "$2"
  '';

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
        rsync
        python3
        wl-clipboard
        vips
        ffmpegthumbnailer
        mediainfo
        epubThumbnailer
        poppler-utils
        imagemagick
        p7zip
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
in
  pkgs.symlinkJoin {
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
  }
