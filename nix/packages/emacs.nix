{
  inputs,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;

  configSource = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../early-init.el
      ../../init.el
      (lib.fileset.fileFilter (file: file.hasExt "el") ../../lisp)
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
  # nixpkgs' twig-language-server is a different, older implementation.
  twiggyLanguageServer = pkgs.stdenvNoCC.mkDerivation {
    pname = "twiggy-language-server";
    version = "26.4.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/twiggy-language-server/-/twiggy-language-server-26.4.1.tgz";
      hash = "sha256-GlV9NhBLReD6eS6w61WDZ6fv7LvujkcEpCiAEW6zufA=";
    };
    nativeBuildInputs = [pkgs.makeWrapper];
    installPhase = ''
      mkdir -p $out/lib/twiggy-language-server $out/bin
      cp -r . $out/lib/twiggy-language-server
      makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/twiggy-language-server \
        --add-flags $out/lib/twiggy-language-server/bin/server.js
    '';
  };

  emacsWithDependencies = pkgs.emacsWithPackagesFromUsePackage {
    package = emacsBase;
    config = lib.concatMapStringsSep "\n" builtins.readFile configFiles;
    alwaysEnsure = true;
    extraEmacsPackages = epkgs:
      let
        kitty-graphics = epkgs.trivialBuild {
          pname = "kitty-graphics";
          version = inputs.kitty-graphics.shortRev;
          src = inputs.kitty-graphics;
          packageRequires = [];
        };
      in
        (with epkgs; [
          kitty-graphics
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
        ffmpeg
        ffmpegthumbnailer
        mediainfo
        mpv
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
        twiggyLanguageServer
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
