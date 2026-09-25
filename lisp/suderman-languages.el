;;; suderman-languages.el --- Language mode associations -*- lexical-binding: t; -*-

;;; Commentary:
;; Broad language-mode wiring that does not need a dedicated module.

;;; Code:

(require 'use-package)

(use-package treesit-auto
  :demand t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :custom
  (treesit-auto-install nil)
  :config
  ;; Keep mappings static.  The global mode rebuilds every remap at each mode
  ;; probe; opening 53 Agenda files triggered it 159 times and blocked Android
  ;; for 25-30 seconds.
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode -1))

(use-package web-mode
  :mode ("\\.twig\\'" . web-mode))

(use-package php-mode
  :mode "\\.php\\'")

(use-package csv-mode
  :mode "\\.csv\\'"
  :hook (csv-mode . (lambda () (visual-line-mode -1))))

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

(provide 'suderman-languages)
;;; suderman-languages.el ends here
