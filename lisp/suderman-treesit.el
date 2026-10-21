;;; suderman-treesit.el --- Tree-sitter grammars -*- lexical-binding: t; -*-

;;; Commentary:
;; Desktop gets grammars from Nix; Android builds them with Termux git and
;; clang.  Org source blocks look up `<lang>-mode', so languages without one
;; map to their tree-sitter mode once the grammar exists.  The Android
;; installer loads this file alone in batch, so it must not depend on the
;; rest of the configuration.

;;; Code:

(require 'treesit)

(defvar org-src-lang-modes)
(declare-function org-src-get-lang-mode "org-src" (lang))

;; Each LANG has a `LANG-ts-mode'.
(defconst suderman/treesit-languages
  '(nix yaml json typescript markdown dockerfile bash html css lua php))

;; Emacs ships no Nix mode to carry a recipe.  Nixpkgs builds this commit for
;; the desktop.
(add-to-list 'treesit-language-source-alist
             '(nix "https://github.com/nix-community/tree-sitter-nix"
                   :commit "eabf96807ea4ab6d6c7f09b671a88cd483542840"))

(defun suderman/treesit-map-org-src ()
  "Use tree-sitter modes for Org blocks that have no other mode.
Without a grammar, as on a fresh Android install, their blocks stay plain."
  (dolist (lang suderman/treesit-languages)
    (let ((name (symbol-name lang)))
      (when (and (treesit-ready-p lang t)
                 (not (fboundp (org-src-get-lang-mode name))))
        (add-to-list 'org-src-lang-modes
                     (cons name (intern (format "%s-ts" lang))))))))

(defun suderman/treesit-install-grammars ()
  "Build missing grammars for `suderman/treesit-languages'."
  (interactive)
  (let ((treesit-auto-install-grammar 'always)
        failed)
    (dolist (lang suderman/treesit-languages)
      (let ((mode (intern (format "%s-ts-mode" lang))))
        ;; Built-in modes install their grammar and its dependencies, such as
        ;; Markdown's inline grammar, when they start.
        (when (fboundp mode)
          (ignore-errors
            (with-temp-buffer (delay-mode-hooks (funcall mode)))))
        (unless (or (treesit-language-available-p lang)
                    (ignore-errors (treesit-install-language-grammar lang)
                                   (treesit-language-available-p lang)))
          (push lang failed))))
    (when (featurep 'org-src)
      (suderman/treesit-map-org-src))
    (if failed
        (user-error "Could not build grammars: %s"
                    (mapconcat #'symbol-name (nreverse failed) ", "))
      (message "Tree-sitter grammars are installed"))))

(provide 'suderman-treesit)
;;; suderman-treesit.el ends here
