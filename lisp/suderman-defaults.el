;;; suderman-defaults.el --- Small built-in defaults -*- lexical-binding: t; -*-

;;; Commentary:
;; Boring Emacs behavior tweaks that do not need package setup.  Domain-specific
;; helpers live in their own modules instead of accumulating here.

;;; Code:

(require 'project)
(require 'so-long)

(add-to-list 'project-vc-extra-root-markers ".stignore")

(setq ring-bell-function #'ignore
      use-short-answers t
      read-answer-short t
      confirm-kill-emacs #'y-or-n-p
      read-process-output-max (* 1024 1024)
      multiple-terminals-merge-keyboards t
      large-file-warning-threshold (* 100 1024 1024)
      enable-recursive-minibuffers t
      scroll-preserve-screen-position 'always
      scroll-error-top-bottom t)

(setq-default indent-tabs-mode nil
              tab-width 2
              standard-indent 2)

(savehist-mode 1)
(save-place-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(electric-pair-mode 1)

(global-visual-line-mode -1)
(add-hook 'text-mode-hook #'visual-line-mode)
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'text-mode)
      (visual-line-mode 1))))

(setq so-long-action 'so-long-minor-mode
      so-long-variable-overrides
      (assq-delete-all 'buffer-read-only so-long-variable-overrides))
(dolist (mode '(display-fill-column-indicator-mode indent-bars-mode))
  (add-to-list 'so-long-minor-modes mode))
(global-so-long-mode 1)

(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.1)

(provide 'suderman-defaults)
;;; suderman-defaults.el ends here
