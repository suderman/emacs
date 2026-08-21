;;; suderman-defaults.el --- Small built-in defaults -*- lexical-binding: t; -*-

;;; Commentary:
;; Boring Emacs behavior tweaks that do not need package setup.  Domain-specific
;; helpers live in their own modules instead of accumulating here.

;;; Code:

(setq ring-bell-function #'ignore
      use-short-answers t
      confirm-kill-emacs #'y-or-n-p
      read-process-output-max (* 1024 1024)
      large-file-warning-threshold (* 100 1024 1024)
      enable-recursive-minibuffers t
      scroll-preserve-screen-position 'always
      scroll-error-top-bottom t)

(savehist-mode 1)
(save-place-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(electric-pair-mode 1)
(global-visual-line-mode 1)

(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.1)

(provide 'suderman-defaults)
;;; suderman-defaults.el ends here
