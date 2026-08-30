;;; suderman-nix-test.el --- Focused Nix checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-nix-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-nix)

(defun suderman/test-nix-language-at (text)
  "Return the Tree-sitter language at the start of TEXT."
  (goto-char (point-min))
  (search-forward text)
  (treesit-language-at (- (point) (length text))))

(defun suderman/test-nix-face-at (text)
  "Return the font-lock face at the start of TEXT."
  (goto-char (point-min))
  (search-forward text)
  (get-text-property (- (point) (length text)) 'face))

(ert-deftest suderman/nix-comments-select-embedded-languages ()
  (with-temp-buffer
    (let ((delimiter (make-string 2 39)))
      (insert
       (format
        "{ config, lib, ... }:\n{\n  setting = lib.mkIf config.enabled true;\n  elisp =\n    # elisp\n    %s\n      (defun hello ()\n        (unless (locate-library \"hello\")\n          (error \"missing\")))\n    %s;\n  bash =\n    # sh\n    %s\n      echo \"$HOME\"\n    %s;\n  python =\n    # python\n    %s\n      def hello():\n          return True\n    %s;\n  lua =\n    # lua\n    %s\n      util.exec(\"ALT_R\", \"${toggle}\", { ignore_mods = true })\n      util.exec(\"ALT_R\", \"${toggle}\", { release = true })\n    %s;\n  html =\n    # html\n    %s\n      <main>Hello</main>\n    %s;\n  unknown =\n    # ruby\n    %s\n      puts \"hello\"\n    %s;\n  plain = %splain string%s;\n}\n"
        delimiter delimiter delimiter delimiter delimiter delimiter
        delimiter delimiter delimiter delimiter delimiter delimiter
        delimiter delimiter delimiter delimiter)))
    (nix-ts-mode)
    (should (eq (suderman/test-nix-language-at "defun") 'elisp))
    (should (eq (suderman/test-nix-language-at "echo") 'bash))
    (should (eq (suderman/test-nix-language-at "def hello") 'python))
    (should (eq (suderman/test-nix-language-at "util.exec") 'lua))
    (should (eq (suderman/test-nix-language-at "toggle}") 'nix))
    (should (eq (suderman/test-nix-language-at "ignore_mods") 'lua))
    (should (eq (suderman/test-nix-language-at "<main>") 'html))
    (should (eq (suderman/test-nix-language-at "puts") 'nix))
    (should (eq (suderman/test-nix-language-at "plain string") 'nix))
    (font-lock-ensure)
    (dolist (text '("defun" "echo" "def hello" "util.exec" "main>"))
      (ert-info ((format "Embedded token: %s" text))
        (should-not (eq (suderman/test-nix-face-at text)
                        'font-lock-string-face))))
    (should (eq (suderman/test-nix-face-at "unless")
                'font-lock-keyword-face))
    (should (eq (suderman/test-nix-face-at "locate-library") 'default))
    (should (eq (suderman/test-nix-face-at "error")
                'font-lock-warning-face))
    (should (eq (suderman/test-nix-face-at "config,")
                'font-lock-variable-name-face))
    (should (eq (suderman/test-nix-face-at "setting =")
                'font-lock-property-name-face))
    (should (eq (suderman/test-nix-face-at "lib.mkIf")
                'font-lock-type-face))
    (should (eq (suderman/test-nix-face-at "config.enabled")
                'font-lock-type-face))
    (should (eq (suderman/test-nix-face-at "util.exec") 'default))
    (should (eq (suderman/test-nix-face-at "exec")
                'font-lock-property-use-face))
    (should (eq (suderman/test-nix-face-at "ALT_R")
                'font-lock-string-face))
    (should (eq (suderman/test-nix-face-at "${toggle}")
                'font-lock-punctuation-face))
    (should (eq (suderman/test-nix-face-at "toggle}")
                'font-lock-variable-use-face))
    (should (eq (suderman/test-nix-face-at "ignore_mods")
                'font-lock-property-name-face))
    (should (eq (suderman/test-nix-face-at "release")
                'font-lock-property-name-face))
    (let ((lua-parsers (treesit-parser-list nil 'lua 'embedded)))
      (should (= (length lua-parsers) 1))
      (should (> (length (treesit-parser-included-ranges
                          (car lua-parsers)))
                 1))
      (should-not
       (treesit-query-capture
        (treesit-parser-root-node (car lua-parsers))
        '((ERROR) @error))))
    (let ((settings-count (length treesit-font-lock-settings)))
      (suderman/nix-embedded-languages-setup)
      (should (= (length treesit-font-lock-settings) settings-count)))
    (goto-char (point-min))
    (search-forward "# lua")
    (replace-match "# ruby")
    (treesit-update-ranges)
    (should (eq (suderman/test-nix-language-at "util.exec") 'nix))))

(provide 'suderman-nix-test)
;;; suderman-nix-test.el ends here
