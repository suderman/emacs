;;; suderman-languages-test.el --- Focused language checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-languages-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-languages)

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
        "{\n  elisp =\n    # elisp\n    %s\n      (defun hello ()\n        (unless (locate-library \"hello\")\n          (error \"missing\")))\n    %s;\n  bash =\n    # sh\n    %s\n      echo \"$HOME\"\n    %s;\n  python =\n    # python\n    %s\n      def hello():\n          return True\n    %s;\n  lua =\n    # lua\n    %s\n      local answer = true\n    %s;\n  html =\n    # html\n    %s\n      <main>Hello</main>\n    %s;\n  unknown =\n    # ruby\n    %s\n      puts \"hello\"\n    %s;\n  plain = %splain string%s;\n  interpolation = %shello ''${name}%s;\n}\n"
        delimiter delimiter delimiter delimiter delimiter delimiter
        delimiter delimiter delimiter delimiter delimiter delimiter
        delimiter delimiter delimiter delimiter)))
    (nix-ts-mode)
    (should (eq (suderman/test-nix-language-at "defun") 'elisp))
    (should (eq (suderman/test-nix-language-at "echo") 'bash))
    (should (eq (suderman/test-nix-language-at "def hello") 'python))
    (should (eq (suderman/test-nix-language-at "local answer") 'lua))
    (should (eq (suderman/test-nix-language-at "<main>") 'html))
    (should (eq (suderman/test-nix-language-at "puts") 'nix))
    (should (eq (suderman/test-nix-language-at "plain string") 'nix))
    (should (eq (suderman/test-nix-language-at "name}") 'nix))
    (font-lock-ensure)
    (dolist (text '("defun" "echo" "def hello" "local answer" "main>"))
      (ert-info ((format "Embedded token: %s" text))
        (should-not (eq (suderman/test-nix-face-at text)
                        'font-lock-string-face))))
    (should (eq (suderman/test-nix-face-at "unless")
                'font-lock-keyword-face))
    (should (eq (suderman/test-nix-face-at "locate-library") 'default))
    (should (eq (suderman/test-nix-face-at "error")
                'font-lock-warning-face))
    (let ((settings-count (length treesit-font-lock-settings)))
      (suderman/nix-embedded-languages-setup)
      (should (= (length treesit-font-lock-settings) settings-count)))
    (goto-char (point-min))
    (search-forward "# lua")
    (replace-match "# ruby")
    (treesit-update-ranges)
    (should (eq (suderman/test-nix-language-at "local answer") 'nix))))

(provide 'suderman-languages-test)
;;; suderman-languages-test.el ends here
