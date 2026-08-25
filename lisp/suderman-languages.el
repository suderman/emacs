;;; suderman-languages.el --- Language mode associations -*- lexical-binding: t; -*-

;;; Commentary:
;; Broad language-mode wiring that does not need a dedicated module yet.
;; Promote sections out of here when they gain custom commands or larger setup.

;;; Code:

(require 'use-package)
(require 'suderman-markdown)

(use-package treesit-auto
  :demand t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :custom
  (treesit-auto-install nil)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

(use-package nix-ts-mode
  :mode "\\.nix\\'")

(use-package web-mode
  :mode ("\\.twig\\'" . web-mode))

(use-package php-mode
  :mode "\\.php\\'")

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

(provide 'suderman-languages)
;;; suderman-languages.el ends here
